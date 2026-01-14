#!/bin/bash
set -euo pipefail

echo "=== $(date) ==="

# Backups can be disabled by touching `/do_not_backup_db`.
if test -f "/do_not_backup_db"; then
    echo "Backups disabled - found /do_not_backup_db"
    exit
fi

BASE_PATH="/home/backupreader/backups"
DATE=$(date +'%Y-%m-%d-%H%M%S')  # e.g. 2023-05-13-181803
BACKUP="${BASE_PATH}/all-backup-${DATE}.sql.zst"

echo "Starting backup to $BACKUP"

time mysqldump --host ropewiki_db \
          --all-databases \
          --add-drop-database \
          --single-transaction \
          --user=root --password="{{RW_ROOT_DB_PASSWORD}}" \
          | zstd -10 > ${BACKUP}

# Owner: rw-, Group: r--, Others: r--
chmod 644 ${BACKUP}

ls -lah ${BACKUP}

touch "$BASE_PATH/last_success_${USER}"

echo "==============="
