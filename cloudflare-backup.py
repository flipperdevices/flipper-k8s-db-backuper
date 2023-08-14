#!/usr/bin/env python3

import os
import json
import boto3
import CloudFlare
from datetime import datetime
from pathlib import Path, PurePath


class Settings:
    def __init__(self) -> None:
        self.cf_token = os.environ.get("BACKUP_CLOUDFLARE_TOKEN")
        self.backup_dir = os.environ.get("BACKUP_DUMP_BASEDIR")
        self.namespace = os.environ.get("BACKUP_CLOUDFLARE_NAMESPACE")
        self.hostname = os.environ.get("BACKUP_CLOUDFLARE_HOSTNAME")
        self.backup_aws_region = os.environ.get("BACKUP_AWS_REGION")
        self.backup_aws_bucket = os.environ.get("BACKUP_AWS_BUCKET")
        self.backup_aws_access_key = os.environ.get("BACKUP_AWS_ACCESS_KEY")
        self.backup_aws_secret_key = os.environ.get("BACKUP_AWS_SECRET_KEY")


class Backup:
    def __init__(self, settings: Settings) -> None:
        self.settings = settings
        self.backup_dir_path = self.get_backup_dir_path()
        self.cf = CloudFlare.CloudFlare(token=self.settings.cf_token)
        self.zones = self.cf.zones.get()
        self.s3_bucket = self.s3_connect_get_bucket()

    def backup_all_zones(self) -> None:
        local_path = Path(self.settings.backup_dir) / self.backup_dir_path
        local_path.mkdir(parents=True)
        for zone in self.zones:
            zone_id = zone["id"]
            zone_name = zone["name"]
            with open((local_path / f"{zone_name}.bind"), "w") as f:
                f.write(self.cf.zones.dns_records.export.get(zone_id))
            with open((local_path / f"{zone_name}.json"), "w") as f:
                json.dump(self.cf.zones.pagerules.get(zone_id), f, indent=4)

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

    def s3_upload_directory(self):
        local_path = Path(self.settings.backup_dir) / self.backup_dir_path
        for file in list(local_path.glob("*.*")):
            remote_path = self.backup_dir_path / file.name
            self.s3_bucket.upload_file(str(file), str(remote_path))

    def run(self) -> None:
        self.backup_all_zones()
        self.s3_upload_directory()


def main():
    settings = Settings()
    backup = Backup(settings)
    backup.run()


if __name__ == "__main__":
    main()
