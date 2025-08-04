#!/bin/sh
set -e

data_dir="${DATA_FOLDER:-/data}"
backup_dir="${BACKUP_FOLDER:-/backup}"

date=$(date '+%Y%m%d')
time=$(date '+%H%M')
timestamp="$date-$time"

archive_name="${ARCHIVE_PREFIX:-archive}-$timestamp.tar"
archive_path="$backup_dir/$archive_name"

add_files_to_archive() {
    base_dir="$1"
    target="$2"

    # Find matching files and directories
    items=$(find "$base_dir" -maxdepth 1 -name "$target" 2>/dev/null)
    if [ -n "$items" ]; then
        echo "$items" | while IFS= read -r item; do
            # Get relative path from base_dir
            relative_path="${item#"$base_dir"/}"

            # Skip if it's just the base directory itself
            if [ "$relative_path" != "$item" ] && [ -n "$relative_path" ]; then
                tar -rf "$archive_path" -C "$base_dir" "$relative_path"
                log "Added to archive: $relative_path"
            fi
        done
    else
        log "Warning: no files or directories matching '$target' found in $base_dir, skipping"
    fi
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
    add_files_to_archive "$data_dir" "rsa_key.*"

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
    echo "$ENCRYPTION_PASSPHRASE" | gpg --homedir /tmp --batch --yes --quiet --cipher-algo AES256 \
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
    # Build S3 path with optional folder
    if [ -n "$S3_FOLDER" ]; then
        # Remove leading and trailing slashes from S3_FOLDER and ensure proper path structure
        folder=$(echo "$S3_FOLDER" | sed 's|^/*||; s|/*$||')
        bucket_path="s3://$S3_BUCKET/$folder/$date/$archive_name"
    else
        bucket_path="s3://$S3_BUCKET/$date/$archive_name"
    fi

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
    echo "[backup] $1"
}

create_backup
if [ -n "$ENCRYPTION_PASSPHRASE" ]; then
    encrypt_archive
fi
if [ -n "$S3_BUCKET" ] && [ -n "$S3_ENDPOINT" ]; then
    upload_archive_to_bucket
fi
cleanup_older_backups
