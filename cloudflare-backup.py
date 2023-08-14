#!/usr/bin/env python3

import os
import sys
import json
import time
import boto3
import slack_sdk
import CloudFlare
from datetime import datetime
from pathlib import Path, PurePath


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
        self.backup_slack_token = os.environ.get("BACKUP_SLACK_TOKEN")
        self.backup_slack_channel_success = os.environ.get(
            "BACKUP_SLACK_CHANNEL_SUCCESS"
        )
        self.backup_slack_channel_fail = os.environ.get("BACKUP_SLACK_CHANNEL_FAIL")


class SlackReport:
    def __init__(self, settings: Settings):
        self.settings = settings
        self.success_message_template = "Success backup {fqdn}!\nBackup time: {backup_time:.3f}s, upload time: {upload_time:.3f}s"
        self.fail_message_template = "Failed to backup {fqdn}!"

    def report(self, success: bool, backup_time: float = 0.0, upload_time: float = 0.0):
        slack_client = slack_sdk.WebClient(token=self.settings.backup_slack_token)
        fqdn = f"{self.settings.hostname}.{self.settings.namespace}.svc.cluster.local"
        if success:
            slack_channel = self.settings.backup_slack_channel_success
            message = self.success_message_template.format(
                fqdn=fqdn, backup_time=backup_time, upload_time=upload_time
            )
        else:
            slack_channel = self.settings.backup_slack_channel_fail
            message = self.fail_message_template.format(fqdn=fqdn)
        slack_client.chat_postMessage(channel="#" + slack_channel, text=message)


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
    slack_report = SlackReport(settings)
    backup = Backup(settings)
    try:
        backup_time, upload_time = backup.run()
        slack_report.report(
            success=True, backup_time=backup_time, upload_time=upload_time
        )
    except Exception as e:
        slack_report.report(success=False)
        raise e


if __name__ == "__main__":
    main()
