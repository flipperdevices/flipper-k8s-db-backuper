#!/usr/bin/env python3

import os
import sys
import json
import time
import boto3
import CloudFlare
from datetime import datetime
from pathlib import Path, PurePath
from prometheus_client import CollectorRegistry, Gauge, push_to_gateway


class Settings:
    def __init__(self):
        self.cf_token = os.environ.get("BACKUP_CLOUDFLARE_TOKEN")
        self.backup_dir = os.environ.get("BACKUP_DUMP_BASEDIR")
        self.namespace = os.environ.get("BACKUP_CLOUDFLARE_NAMESPACE")
        self.hostname = os.environ.get("BACKUP_CLOUDFLARE_HOSTNAME")
        self.backup_aws_region = os.environ.get("BACKUP_AWS_REGION")
        self.backup_aws_bucket = os.environ.get("BACKUP_AWS_BUCKET")
        self.backup_aws_access_key = os.environ.get("BACKUP_AWS_ACCESS_KEY")
        self.backup_aws_secret_key = os.environ.get("BACKUP_AWS_SECRET_KEY")
        self.backup_pushgateway_url = os.environ.get("BACKUP_PUSHGATEWAY_URL")


class PushGatewayReport:
    def __init__(self, settings: Settings):
        self.settings = settings

    def __is_reports_enabled__(self) -> bool:
        return bool(self.settings.backup_pushgateway_url)

    def report(self, backup_time: float, upload_time: float) -> None:
        if not self.__is_reports_enabled__():
            print("Prometheus reports are disabled!")
            print(f"Backup time: {backup_time:.3f} s")
            print(f"Upload time: {upload_time:.3f} s")
            return
        registry = CollectorRegistry()
        backup_time_gauge = Gauge("backup_time", "backup_time", registry=registry)
        upload_time_gauge = Gauge("upload_time", "upload_time", registry=registry)
        backup_time_gauge.set(backup_time)
        upload_time_gauge.set(upload_time)
        labels = {
            "hostname": self.settings.hostname,
            "namespace": self.settings.namespace,
        }
        push_to_gateway(
            self.settings.backup_pushgateway_url,
            job="flipper-k8s-db-backuper",
            registry=registry,
            grouping_key=labels,
        )


class Backup:
    def __init__(self, settings: Settings):
        self.settings = settings
        self.backup_dir_path = self.get_backup_dir_path()
        self.s3_bucket = self.s3_connect_get_bucket()
        self.backup_time = 0
        self.upload_time = 0

    def measure_time(func):
        def run(self):
            start = time.time()
            func(self)
            end = time.time()
            return end - start

        return run

    @measure_time
    def backup_all_zones(self):
        cf = CloudFlare.CloudFlare(token=self.settings.cf_token)
        zones = cf.zones.get()
        local_path = Path(self.settings.backup_dir) / self.backup_dir_path
        local_path.mkdir(parents=True)
        for zone in zones:
            zone_id = zone["id"]
            zone_name = zone["name"]
            with open((local_path / f"{zone_name}.bind"), "w") as f:
                f.write(cf.zones.dns_records.export.get(zone_id))
            with open((local_path / f"{zone_name}.json"), "w") as f:
                json.dump(cf.zones.pagerules.get(zone_id), f, indent=4)

    def get_backup_dir_path(self):
        date_str = datetime.now().astimezone().strftime("%Y-%m-%d_%H-%M_%Z")
        return Path(self.settings.namespace) / self.settings.hostname / date_str

    def s3_connect_get_bucket(self):
        session = boto3.Session(
            aws_access_key_id=self.settings.backup_aws_access_key,
            aws_secret_access_key=self.settings.backup_aws_secret_key,
            region_name=self.settings.backup_aws_region,
        )
        s3 = session.resource("s3")
        return s3.Bucket(self.settings.backup_aws_bucket)

    @measure_time
    def s3_upload_directory(self):
        local_path = Path(self.settings.backup_dir) / self.backup_dir_path
        for file in list(local_path.glob("*.*")):
            remote_path = self.backup_dir_path / file.name
            self.s3_bucket.upload_file(str(file), str(remote_path))

    def run(self):
        backup_time = self.backup_all_zones()
        upload_time = self.s3_upload_directory()
        return backup_time, upload_time


def main():
    settings = Settings()
    pushgateway_report = PushGatewayReport(settings)
    backup = Backup(settings)
    backup_time, upload_time = backup.run()
    pushgateway_report.report(backup_time=backup_time, upload_time=upload_time)


if __name__ == "__main__":
    main()
