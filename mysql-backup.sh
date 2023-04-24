#!/bin/bash

set -euo pipefail; # bash unofficial strict mode

# public
BACKUP_SLACK_TOKEN=${BACKUP_SLACK_TOKEN:-""};
BACKUP_SLACK_CHANNEL_SUCCESS=${BACKUP_SLACK_CHANNEL_SUCCESS:-""};
BACKUP_SLACK_CHANNEL_FAIL=${BACKUP_SLACK_CHANNEL_FAIL:-""};

# public required
#BACKUP_MYSQL_USER=
#BACKUP_MYSQL_PASSWORD=
#BACKUP_MYSQL_HOSTNAME=
#BACKUP_MYSQL_NAMESPACE=
#BACKUP_MYSQL_PORT=
#BACKUP_AWS_REGION=
#BACKUP_AWS_BUCKET=
#BACKUP_AWS_ACCESS_KEY=
#BACKUP_AWS_SECRET_KEY=

# private
BACKUP_DUMP_BASEDIR="/backup";
BACKUP_DUMP_NAME="mysqldump_all_databases.sql";
BACKUP_SLACK_MESSAGE_URL="https://slack.com/api/chat.postMessage";
BACKUP_DUMP_DIRECTORY="$BACKUP_MYSQL_NAMESPACE/$BACKUP_MYSQL_HOSTNAME/$(date +%Y-%m-%d_%H-%M_%Z)";
BACKUP_DUMP_LOCATION="$BACKUP_DUMP_BASEDIR/$BACKUP_DUMP_DIRECTORY";
BACKUP_MYSQL_FQDN="$BACKUP_MYSQL_HOSTNAME.$BACKUP_MYSQL_NAMESPACE.svc.cluster.local";

function create_dump() {
    mkdir -p "$BACKUP_DUMP_LOCATION";
    mysqldump \
        -h "$BACKUP_MYSQL_FQDN" \
        -P "$BACKUP_MYSQL_PORT" \
        -u "$BACKUP_MYSQL_USER" \
        -p"$BACKUP_MYSQL_PASSWORD" \
        --all-databases \
        2>/dev/null \
        > "$BACKUP_DUMP_LOCATION/$BACKUP_DUMP_NAME";
}

function upload_to_s3() {
    AWS_ACCESS_KEY_ID="$BACKUP_AWS_ACCESS_KEY" \
        AWS_SECRET_ACCESS_KEY="$BACKUP_AWS_SECRET_KEY" \
        AWS_DEFAULT_REGION="$BACKUP_AWS_REGION" \
        aws s3 cp "$BACKUP_DUMP_LOCATION/$BACKUP_DUMP_NAME" \
        "s3://$BACKUP_AWS_BUCKET/$BACKUP_DUMP_DIRECTORY/$BACKUP_DUMP_NAME";
}

function __is_reports_enabled__() {
    if [[ -z "$BACKUP_SLACK_TOKEN" ]] || [[ -z "$BACKUP_SLACK_CHANNEL_SUCCESS" ]] || [[ -z "$BACKUP_SLACK_CHANNEL_FAIL" ]]; then
        return 1;
    else
        return 0;
    fi
}

function __report_to_slack__() {
    local TEXT;
    local DATA;
    local SLACK_CHANNEL;
    SLACK_CHANNEL="$1";
    TEXT="$2";
    if ! __is_reports_enabled__; then
        echo "Slack reports disabled!";
        echo -e "$TEXT";
        return;
    fi
    DATA="{\"channel\":\"$SLACK_CHANNEL\",\"blocks\":[{\"type\":\"section\",\"text\":{\"type\":\"mrkdwn\",\"text\":\"$TEXT\"}}]}";
    curl --data "$DATA" \
        -H "Authorization: Bearer $BACKUP_SLACK_TOKEN" \
        -H "Content-type: application/json" \
        -X POST "$BACKUP_SLACK_MESSAGE_URL";
}

function report_fail() {
    TEXT="Failed to backup $BACKUP_MYSQL_FQDN!";
    __report_to_slack__ "$BACKUP_SLACK_CHANNEL_FAIL" "$TEXT";
    exit 1;
}

function report_success() {
    local BACKUP_TIME;
    local UPLOAD_TIME;
    BACKUP_TIME="$1";
    UPLOAD_TIME="$2";
    TEXT="Success backup $BACKUP_MYSQL_FQDN!";
    TEXT+="\nBackup time: ${BACKUP_TIME}s, upload time: ${UPLOAD_TIME}s";
    __report_to_slack__ "$BACKUP_SLACK_CHANNEL_SUCCESS" "$TEXT";
    exit 0;
}

trap report_fail EXIT;
BACKUP_TIME="$(TIMEFORMAT='%R';time (create_dump) 2>&1 1>/dev/null)";
UPLOAD_TIME="$(TIMEFORMAT='%R';time (upload_to_s3) 2>&1 1>/dev/null)";
trap - EXIT;
report_success "$BACKUP_TIME" "$UPLOAD_TIME";
