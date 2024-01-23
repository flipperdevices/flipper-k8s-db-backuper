#!/bin/bash

set -euo pipefail; # bash unofficial strict mode

# public
BACKUP_PUSHGATEWAY_URL="${BACKUP_PUSHGATEWAY_URL:-""}";
BACKUP_POSTGRESQL_PASSWORD=${BACKUP_POSTGRESQL_PASSWORD:-""};

# public required
#BACKUP_POSTGRESQL_VERSION=
#BACKUP_POSTGRESQL_USER=
#BACKUP_POSTGRESQL_HOSTNAME=
#BACKUP_POSTGRESQL_NAMESPACE=
#BACKUP_POSTGRESQL_PORT=
#BACKUP_AWS_REGION=
#BACKUP_AWS_BUCKET=
#BACKUP_AWS_ACCESS_KEY=
#BACKUP_AWS_SECRET_KEY=

# private
BACKUP_DUMP_BASEDIR="/backup";
BACKUP_DUMP_NAME="psql_dumpall.sql";
BACKUP_DUMP_DIRECTORY="$BACKUP_POSTGRESQL_NAMESPACE/$BACKUP_POSTGRESQL_HOSTNAME/$(date +%Y-%m-%d_%H-%M_%Z)";
BACKUP_DUMP_LOCATION="$BACKUP_DUMP_BASEDIR/$BACKUP_DUMP_DIRECTORY";
BACKUP_POSTGRESQL_FQDN="$BACKUP_POSTGRESQL_HOSTNAME.$BACKUP_POSTGRESQL_NAMESPACE.svc.cluster.local";

function install_posgresql_client() {
    DEBIAN_FRONTEND=noninteractive apt update;
    DEBIAN_FRONTEND=noninteractive apt -y install "postgresql-client-$BACKUP_POSTGRESQL_VERSION";
}

function create_dump() {
    mkdir -p "$BACKUP_DUMP_LOCATION";
    PGPASSWORD="$BACKUP_POSTGRESQL_PASSWORD" \
        pg_dumpall \
        -h "$BACKUP_POSTGRESQL_FQDN" \
        -U "$BACKUP_POSTGRESQL_USER" \
        -p "$BACKUP_POSTGRESQL_PORT" > "$BACKUP_DUMP_LOCATION/$BACKUP_DUMP_NAME";
}

function upload_to_s3() {
    AWS_ACCESS_KEY_ID="$BACKUP_AWS_ACCESS_KEY" \
        AWS_SECRET_ACCESS_KEY="$BACKUP_AWS_SECRET_KEY" \
        AWS_DEFAULT_REGION="$BACKUP_AWS_REGION" \
        aws s3 cp "$BACKUP_DUMP_LOCATION/$BACKUP_DUMP_NAME" \
        "s3://$BACKUP_AWS_BUCKET/$BACKUP_DUMP_DIRECTORY/$BACKUP_DUMP_NAME";
}

function __is_reports_enabled__() {
    if [[ -z "$BACKUP_PUSHGATEWAY_URL" ]]; then
        return 1;
    else
        return 0;
    fi
}

function report_to_prom() {
    local BACKUP_TIME;
    local UPLOAD_TIME;
    BACKUP_TIME="$1";
    UPLOAD_TIME="$2";
    if ! __is_reports_enabled__; then
        echo "Prometheus reports are disabled!";
        echo "Backup time $BACKUP_TIME";
        echo "Upload time: $UPLOAD_TIME";
        return;
    fi
    echo -e "# TYPE backup_time gauge\nbackup_time $BACKUP_TIME" | \
        curl --fail-with-body \
        --data-binary @- \
        "$BACKUP_PUSHGATEWAY_URL/metrics/job/flipper-k8s-db-backuper/namespace/$BACKUP_POSTGRESQL_NAMESPACE/hostname/$BACKUP_POSTGRESQL_HOSTNAME";
    echo -e "# TYPE upload_time gauge\nupload_time $UPLOAD_TIME" | \
        curl --fail-with-body \
        --data-binary @- \
        "$BACKUP_PUSHGATEWAY_URL/metrics/job/flipper-k8s-db-backuper/namespace/$BACKUP_POSTGRESQL_NAMESPACE/hostname/$BACKUP_POSTGRESQL_HOSTNAME";
}

install_posgresql_client;

{ TIMEFORMAT='%R'; time create_dump 2>&1 ; } 2> create_dump_time.txt
{ TIMEFORMAT='%R'; time upload_to_s3 2>&1 ; } 2> upload_to_s3_time.txt

BACKUP_TIME="$(cat create_dump_time.txt)";
UPLOAD_TIME="$(cat upload_to_s3_time.txt)";
report_to_prom "$BACKUP_TIME" "$UPLOAD_TIME";
