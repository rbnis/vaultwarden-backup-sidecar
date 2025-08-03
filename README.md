# Vaultwarden Backup Sidecar

A lightweight Docker sidecar container for backing up Vaultwarden data automatically on a scheduled basis. This container creates compressed archives of your Vaultwarden data and optionally uploads them to S3-compatible storage.

## Features

- 📅 **Scheduled Backups**: Automated backups using cron scheduling
- 🗄️ **SQLite Backup**: Proper SQLite database backup using `.backup` command
- 📦 **Complete Data Backup**: Backs up database, attachments, sends, and configuration files
- 🔒 **Encryption Support**: Optional GPG encryption with AES256 for secure backups
- ☁️ **S3 Integration**: Optional upload to S3-compatible storage (AWS S3, MinIO, etc.)
- 🧹 **Automatic Cleanup**: Configurable retention policy for local backups
- 🪶 **Lightweight**: Based on Alpine Linux for minimal footprint

## Backup Contents

The backup includes the following Vaultwarden data:
- `db.sqlite3` - Main database (backed up using SQLite backup command)
- `attachments/` - File attachments
- `sends/` - Send files
- `config.json` - Configuration file
- `rsa_key.der` - RSA private key (DER format)
- `rsa_key.pem` - RSA private key (PEM format)
- `rsa_key.pub.der` - RSA public key

## Quick Start

### Kubernetes Deployment Example

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: vaultwarden
  labels:
    app.kubernetes.io/name: vaultwarden
spec:
  replicas: 1
  selector:
    matchLabels:
      app.kubernetes.io/name: vaultwarden
  template:
    metadata:
      labels:
        app.kubernetes.io/name: vaultwarden
    spec:
      securityContext:
        fsGroup: 1000
      containers:
        - name: vaultwarden
          image: ghcr.io/dani-garcia/vaultwarden:1.34.3
          imagePullPolicy: IfNotPresent
          env:
            - name: DATA_FOLDER
              value: /data
          ports:
            - name: http
              containerPort: 8080
              protocol: TCP
          volumeMounts:
            - name: data
              mountPath: "/data"
          securityContext:
            runAsNonRoot: true
            runAsUser: 1000
        - name: backup
          image: ghcr.io/rbnis/vaultwarden-backup-sidecar:v1.0.0
          env:
            - name: ENCRYPTION_PASSPHRASE
              value: hunter2
            - name: S3_ENDPOINT
              value: https://s3.amazonaws.com
            - name: S3_BUCKET
              value: my-vaultwarden-backups
            - name: AWS_ACCESS_KEY_ID
              value: your-access-key
            - name: AWS_SECRET_ACCESS_KEY
              value: your-secret-key
          volumeMounts:
            - mountPath: "/data"
              name: data
              readOnly: true
            - mountPath: "/backup"
              name: backup
          securityContext:
            runAsNonRoot: true
            runAsUser: 1000
      volumes:
        - name: data
          persistentVolumeClaim:
            claimName: vaultwarden-data-pvc
        - name: backup
          emptyDir: {}
```

### Docker Compose Example

```yaml
version: '3.8'
services:
  vaultwarden:
    image: vaultwarden/server:latest
    container_name: vaultwarden
    volumes:
      - vaultwarden_data:/data
    ports:
      - "8080:80"

  vaultwarden-backup:
    image: ghcr.io/rbnis/vaultwarden-backup-sidecar:v1.0.0
    container_name: vaultwarden-backup
    volumes:
      - vaultwarden_data:/data:ro  # Read-only access to Vaultwarden data
      - backup_data:/backup        # Local backup storage
    environment:
      - CRON_SCHEDULE=0 2 * * *    # Daily at 2 AM
      # Optional encryption
      - ENCRYPTION_PASSPHRASE=hunter2
      # Optional S3 configuration
      - S3_ENDPOINT=https://s3.amazonaws.com
      - S3_BUCKET=my-vaultwarden-backups
      - AWS_ACCESS_KEY_ID=your-access-key
      - AWS_SECRET_ACCESS_KEY=your-secret-key

volumes:
  vaultwarden_data:
  backup_data:
```

## Environment Variables

| Variable                | Description                                        | Mandatory | Default     | Example                       |
| ----------------------- | -------------------------------------------------- | --------- | ----------- | ----------------------------- |
| `CRON_SCHEDULE`         | Cron schedule for backups                          | No        | `0 2 * * *` | `0 */6 * * *` (every 6 hours) |
| `DATA_FOLDER`           | Path to Vaultwarden data directory                 | No        | `/data`     | `/vaultwarden/data`           |
| `BACKUP_FOLDER`         | Path to local backup storage                       | No        | `/backup`   | `/backups`                    |
| `RETENTION_DAYS`        | Days to keep local backups (0=disabled)            | No        | `7`         | `14` (keep for 14 days)       |
| `ARCHIVE_PREFIX`        | Prefix for archive filenames                       | No        | `archive`   | `vaultwarden-backup`          |
| `ENCRYPTION_PASSPHRASE` | Passphrase for GPG encryption (enables encryption) | No        | -           | `hunter2`    |

### S3 Upload Configuration (Optional)

If you want to upload backups to S3-compatible storage, configure these variables:

| Variable                | Description                  | Default | Example                                    |
| ----------------------- | ---------------------------- | ------- | ------------------------------------------ |
| `S3_ENDPOINT`           | S3 endpoint URL              | -       | `https://s3.amazonaws.com`                 |
| `S3_BUCKET`             | S3 bucket name               | -       | `my-vaultwarden-backups`                   |
| `AWS_ACCESS_KEY_ID`     | AWS access key ID            | -       | `AKIAIOSFODNN7EXAMPLE`                     |
| `AWS_SECRET_ACCESS_KEY` | AWS secret access key        | -       | `wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY` |
| `AWS_DEFAULT_REGION`    | AWS region (if using AWS S3) | -       | `us-east-1`                                |

**Note**: If `S3_BUCKET` and `S3_ENDPOINT` are not provided, backups will only be stored locally.

## Building the Image

To build the Docker image locally:

```bash
# Build for local architecture
docker build -t vaultwarden-backup-sidecar:local .

# Build for multiple architectures (requires buildx)
docker buildx build --platform linux/amd64,linux/arm64 -t vaultwarden-backup-sidecar:local .
```

## Backup Archive Format

Backups are created as compressed tar archives with the following naming convention:

**Unencrypted backups:**
```
archive-YYYYMMDD-HHMM.tar.gz
```

**Encrypted backups (when `ENCRYPTION_PASSPHRASE` is set):**
```
archive-YYYYMMDD-HHMM.tar.gz.gpg
```

Examples (with default prefix "archive"):
- `archive-20250803-0200.tar.gz` (unencrypted)
- `archive-20250803-0200.tar.gz.gpg` (encrypted)

The archive contains:
```
db.sqlite3          # SQLite database backup
attachments/        # User file attachments
sends/              # Send files
config.json         # Vaultwarden configuration
rsa_key.der         # RSA keys
rsa_key.pem
rsa_key.pub.der
```

## Retention Policy

- **Local backups**: Automatically cleaned up based on `RETENTION_DAYS` (default: 7 days, set to 0 to disable cleanup)
- **S3 backups**: No automatic cleanup (configure S3 lifecycle policies if needed)

## Encryption and Decryption

### Encryption
When `ENCRYPTION_PASSPHRASE` is set, backups are automatically encrypted using GPG with AES256 symmetric encryption. The encryption process:
1. Creates a compressed tar.gz archive
2. Encrypts it using GPG with the provided passphrase
3. Saves it as `.tar.gz.gpg`
4. Removes the temporary unencrypted archive

### Decrypting Backups
To decrypt an encrypted backup archive:

```bash
# Decrypt the backup
gpg --quiet --batch --yes --decrypt --passphrase="your-passphrase" \
    --output archive-20250803-0200.tar.gz \
    archive-20250803-0200.tar.gz.gpg

# Extract the decrypted archive
tar -xzf archive-20250803-0200.tar.gz
```

Or in one command:
```bash
gpg --quiet --batch --yes --decrypt --passphrase="your-passphrase" \
    archive-20250803-0200.tar.gz.gpg | tar -xz
```

### Logs

To view logs in Kubernetes:
```bash
kubectl logs deployment/vaultwarden -c backup
```

To view backup logs in Docker Compose:
```bash
docker-compose logs vaultwarden-backup
```

### Manual Backup

To run a backup manually instead of waiting for the cron schedule:
```bash
# Kubernetes
kubectl exec deployment/vaultwarden -c backup -- /usr/local/bin/backup.sh

# Docker Compose
docker-compose exec vaultwarden-backup /usr/local/bin/backup.sh
```

## Security Considerations

- Mount Vaultwarden data as read-only (`:ro`) to prevent accidental modifications
- Ensure backup storage has appropriate access controls
- Consider encrypting backups when uploading to S3 for additional security
- Use strong encryption passphrases when enabling encryption

## Related Projects

- [Vaultwarden](https://github.com/dani-garcia/vaultwarden) - The main Bitwarden server implementation
- [Bitwarden](https://bitwarden.com/) - The original password manager

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request. For major changes, please open an issue first to discuss what you would like to change.


## License

This project is open-source and licensed under the MIT License - see the [LICENSE.md](LICENSE.md) file for details.
