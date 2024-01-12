#!/bin/bash

set -euo pipefail; # bash unofficial strict mode

# public
BACKUP_PUSHGATEWAY_URL="${BACKUP_PUSHGATEWAY_URL:-""}";
BACKUP_MONGO_GZIP="${BACKUP_MONGO_GZIP:-""}";

# public required
#BACKUP_MONGO_HOSTNAME=
#BACKUP_MONGO_NAMESPACE=
#---------
#BACKUP_MONGO_PORT=
# or
#BACKUP_MONGO_URI=
#---------
#BACKUP_AWS_REGION=
#BACKUP_AWS_BUCKET=
#BACKUP_AWS_ACCESS_KEY=
#BACKUP_AWS_SECRET_KEY=

# private
BACKUP_DUMP_BASEDIR="/backup";
BACKUP_DUMP_DIRECTORY="$BACKUP_MONGO_NAMESPACE/$BACKUP_MONGO_HOSTNAME/$(date +%Y-%m-%d_%H-%M_%Z)";
BACKUP_DUMP_LOCATION="$BACKUP_DUMP_BASEDIR/$BACKUP_DUMP_DIRECTORY";
BACKUP_MONGO_FQDN="$BACKUP_MONGO_HOSTNAME.$BACKUP_MONGO_NAMESPACE.svc.cluster.local";

function is_gzip_enabled() {
    GZIP_ARG_STRING="";
    if [[ -n "${BACKUP_MONGO_GZIP:-""}" ]]; then
        if [[ "$BACKUP_MONGO_GZIP" == "true" ]]; then
            GZIP_ARG_STRING="--gzip";
        fi
    fi
}

function create_dump() {
    is_gzip_enabled;
    mkdir -p "$BACKUP_DUMP_LOCATION";
    if [[ -n "${BACKUP_MONGO_PORT:-""}" ]]; then
        mongodump \
            --host "$BACKUP_MONGO_FQDN" \
            --port "$BACKUP_MONGO_PORT" \
            --out "$BACKUP_DUMP_LOCATION" \
            "$GZIP_ARG_STRING";
    elif [[ -n "${BACKUP_MONGO_URI:-""}" ]]; then
        mongodump \
            "$BACKUP_MONGO_URI" \
            --out "$BACKUP_DUMP_LOCATION" \
            "$GZIP_ARG_STRING";
    else
        echo "BACKUP_MONGO_PORT or BACKUP_MONGO_PORT required!";
        exit 1;
    fi
}

function upload_to_s3() {
    AWS_ACCESS_KEY_ID="$BACKUP_AWS_ACCESS_KEY" \
        AWS_SECRET_ACCESS_KEY="$BACKUP_AWS_SECRET_KEY" \
        AWS_DEFAULT_REGION="$BACKUP_AWS_REGION" \
        aws s3 cp --recursive "$BACKUP_DUMP_LOCATION" \
        "s3://$BACKUP_AWS_BUCKET/$BACKUP_DUMP_DIRECTORY/";
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
        "$BACKUP_PUSHGATEWAY_URL/metrics/job/flipper-k8s-db-backuper/namespace/$BACKUP_MONGO_NAMESPACE/hostname/$BACKUP_MONGO_HOSTNAME";
    echo -e "# TYPE upload_time gauge\nupload_time $UPLOAD_TIME" | \
        curl --fail-with-body \
        --data-binary @- \
        "$BACKUP_PUSHGATEWAY_URL/metrics/job/flipper-k8s-db-backuper/namespace/$BACKUP_MONGO_NAMESPACE/hostname/$BACKUP_MONGO_HOSTNAME";
}

{ TIMEFORMAT='%R'; time create_dump 2>&1 ; } 2> create_dump_time.txt
{ TIMEFORMAT='%R'; time upload_to_s3 2>&1 ; } 2> upload_to_s3_time.txt

BACKUP_TIME="$(cat create_dump_time.txt)";
UPLOAD_TIME="$(cat upload_to_s3_time.txt)";
report_to_prom "$BACKUP_TIME" "$UPLOAD_TIME";
