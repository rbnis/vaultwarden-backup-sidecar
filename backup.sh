#!/bin/sh
set -e

data_dir="${DATA_FOLDER:-/data}"
backup_dir="${BACKUP_FOLDER:-/backup}"

date=$(date '+%Y%m%d')
time=$(date '+%H%M')
timestamp="$date-$time"

archive_name="archive-$timestamp.tar"
archive_path="$backup_dir/$archive_name"

add_files_to_archive() {
    base_dir="$1"
    target="$2"
    tar -rf "$archive_path" -C "$base_dir" "$target"
}
create_backup() {
    # Create staging area
    staging_area="$backup_dir/staging"
    mkdir -p "$staging_area"

    # Create sqlite backup
    sqlite3 "$data_dir/db.sqlite3" ".backup '$staging_area/db.sqlite3'"
    log "Created sqlite backup: $staging_area/db.sqlite3"

    # Create archive
    tar -cf "$archive_path" -T /dev/null
    add_files_to_archive "$staging_area" "db.sqlite3"
    add_files_to_archive "$data_dir" "attachments"
    add_files_to_archive "$data_dir" "sends"
    add_files_to_archive "$data_dir" "config.json"
    add_files_to_archive "$data_dir" "rsa_key.der"
    add_files_to_archive "$data_dir" "rsa_key.pem"
    add_files_to_archive "$data_dir" "rsa_key.pub.der"
    log "Created archive: $archive_path"

    # Cleanup staging area
    rm -rf "$staging_area"
}

upload_archive_to_bucket() {
    bucket_path="s3://$S3_BUCKET/$date/$archive_name"
    s5cmd --endpoint-url "$S3_ENDPOINT" cp "$archive_path" "$bucket_path"
    log "Uploaded archive to $bucket_path via $S3_ENDPOINT"
}

cleanup_older_backups() {
    find "$backup_dir" -name 'archive-*.tar' -type f -mtime +7 -delete
    log "Cleaned up archives older than 7 days"
}

log() {
    echo "$(date '+%Y-%m-%d %H:%M') [backup] $1"
}

log "Starting"
create_backup
if [ -n "$S3_BUCKET" ] && [ -n "$S3_ENDPOINT" ]; then
    upload_archive_to_bucket
fi
cleanup_older_backups
log "Finished"
