#!/bin/sh
set -e

log() {
    echo "time=\"$(date '+%Y-%m-%dT%H:%M:%SZ')\" level=$1 msg=\"$2\""
}

mkdir -p /tmp/crontabs
echo "$CRON_SCHEDULE /usr/local/bin/backup.sh" > /tmp/crontabs/backup

log "info" "Using cron schedule: $CRON_SCHEDULE"
supercronic /tmp/crontabs/backup
