# Database Backup Strategy

## Overview

Tilawah AI uses PostgreSQL as its primary datastore. Regular backups are critical for disaster recovery. This document outlines the backup strategy, retention policies, and restoration procedures.

## Strategy

1. **Daily Logical Backups (pg_dump)**
   - A full logical backup is taken every night at 02:00 UTC using `pg_dump`.
   - The backup is compressed and securely transferred to an off-site object storage bucket (e.g., AWS S3, Google Cloud Storage) with versioning enabled.

2. **Continuous Archiving (WAL - Write-Ahead Logging)**
   - For point-in-time recovery (PITR), PostgreSQL WAL files are continuously archived to the same object storage bucket. This allows us to restore the database to any specific second before a catastrophic failure.

## Retention Policy

- **Daily Backups**: Retained for 30 days.
- **Weekly Backups**: 1 per week retained for 12 weeks (3 months).
- **Monthly Backups**: 1 per month retained for 1 year.
- **WAL Archives**: Retained for 30 days to match the daily backups.

## Automation

Backups should be automated using a combination of `cron` (or equivalent orchestrator like GitHub Actions / Kubernetes CronJobs) and tools such as `pgBackRest` or `wal-g`.

### Example `pg_dump` Script:
```bash
#!/bin/bash
DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_NAME="tilawah_db_$DATE.sql.gz"
pg_dump -U $POSTGRES_USER -h $POSTGRES_HOST $POSTGRES_DB | gzip > /tmp/$BACKUP_NAME
aws s3 cp /tmp/$BACKUP_NAME s3://$BACKUP_BUCKET/daily/$BACKUP_NAME
rm /tmp/$BACKUP_NAME
```

## Restoration Procedure

### Restoring from a Logical Backup (`pg_dump`)
1. Download the latest backup from the off-site storage.
2. Drop the existing corrupted database (ensure applications are disconnected).
3. Recreate the database.
4. Restore using `gunzip -c backup.sql.gz | psql -U $POSTGRES_USER -h $POSTGRES_HOST $POSTGRES_DB`

### Restoring with PITR (Point-in-Time Recovery)
To recover to a specific timestamp using `pgBackRest` or `wal-g`, follow the specific tool's recovery protocol, specifying the target `--target-action=pause` and the `--target="YYYY-MM-DD HH:MM:SS"`.

## Security

- All backups MUST be encrypted at rest in the object storage.
- Access to the backup bucket must be strictly restricted via IAM policies (least privilege).
- Do NOT include backup credentials in application source code.
