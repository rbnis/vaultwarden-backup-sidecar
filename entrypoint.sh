#!/bin/sh
set -e

log() {
    echo "$1[$(date '+%Y-%m-%dT%H:%M:%SZ')] [entrypoint] $2"
}

mkdir -p /tmp/crontabs
echo "$CRON_SCHEDULE /usr/local/bin/backup.sh" > /tmp/crontabs/backup

log "INFO" "Using cron schedule: $CRON_SCHEDULE"
supercronic /tmp/crontabs/backup
