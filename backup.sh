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

    gzip "$archive_path"

    # Set archive references to compressed archive
    archive_name="$archive_name.gz"
    archive_path="$archive_path.gz"

    log "Created archive: $archive_path"

    # Cleanup staging area
    rm -rf "$staging_area"
}

encrypt_archive() {
    # Encrypt using GPG with symmetric encryption
    echo "$ENCRYPTION_PASSPHRASE" | gpg --batch --yes --quiet --cipher-algo AES256 \
        --compress-algo 0 --symmetric --passphrase-fd 0 \
        --output "$archive_path.gpg" "$archive_path"

    # Remove unencrypted archive
    rm -f "$archive_path"

    # Set archive references to encrypted archive
    archive_name="$archive_name.gpg"
    archive_path="$archive_path.gpg"

    log "Encrypted archive: $archive_path"
}

upload_archive_to_bucket() {
    bucket_path="s3://$S3_BUCKET/$date/$archive_name"
    s5cmd --endpoint-url "$S3_ENDPOINT" cp "$archive_path" "$bucket_path"
    log "Uploaded archive to $bucket_path via $S3_ENDPOINT"
}

cleanup_older_backups() {
    local_retention_time_in_days="${RETENTION_DAYS:-7}"

    # Only cleanup if retention time is a number greater than 0
    if [ "$local_retention_time_in_days" -gt 0 ] 2>/dev/null; then
        find "$backup_dir" \( -name 'archive-*.tar.gz' -o -name 'archive-*.tar.gz.gpg' \) -type f -mtime "+$local_retention_time_in_days" -delete
        log "Cleaned up archives older than $local_retention_time_in_days days"
    else
        log "Backup cleanup disabled (RETENTION_DAYS not greater than 0)"
    fi
}

log() {
    echo "$(date '+%Y-%m-%d %H:%M') [backup] $1"
}

log "Starting"
create_backup
if [ -n "$ENCRYPTION_PASSPHRASE" ]; then
    encrypt_archive
fi
if [ -n "$S3_BUCKET" ] && [ -n "$S3_ENDPOINT" ]; then
    upload_archive_to_bucket
fi
cleanup_older_backups
log "Finished"
