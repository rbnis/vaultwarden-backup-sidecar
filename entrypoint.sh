#!/bin/sh
set -e

log() {
    echo "$(date '+%Y-%m-%d %H:%M') [entrypoint] $1"
}

echo "$CRON_SCHEDULE /usr/local/bin/backup.sh >> /dev/stdout 2>&1" > /etc/crontabs/root

log "Using cron schedule: $CRON_SCHEDULE"
log "Starting cron..."
crond -f -l 2
