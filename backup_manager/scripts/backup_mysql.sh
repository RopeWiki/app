#!/bin/bash
set -euo pipefail

# Verbose output is sent to STDERR. The successfully generated
# filename is sent to STDOUT for programatic use.

echo "=== $(date) ===" >&2

# Backups can be disabled by touching `/do_not_backup_db`.
if test -f "/do_not_backup_db"; then
    echo "Backups disabled - found /do_not_backup_db" >&2
    exit
fi

BASE_PATH="/home/backupreader/backups"
DATE=$(date +'%Y-%m-%d-%H%M%S')  # e.g. 2023-05-13-181803
TMP_BACKUP="${BASE_PATH}/tmp_all-backup-${DATE}.sql.zst"
FINAL_BACKUP="${BASE_PATH}/all-backup-${DATE}.sql.zst"

echo "Starting backup to $FINAL_BACKUP" >&2

{ time mysqldump --host ropewiki_db \
          --all-databases \
          --add-drop-database \
          --single-transaction \
          --user=root --password="{{RW_ROOT_DB_PASSWORD}}" \
          | zstd -10 > ${TMP_BACKUP}; } 2>&2

mv ${TMP_BACKUP} ${FINAL_BACKUP}

# Owner: rw-, Group: r--, Others: r--
chmod 644 ${FINAL_BACKUP}

ls -lah ${FINAL_BACKUP} >&2

touch $BASE_PATH/last_success

echo "===============" >&2

echo -n "${FINAL_BACKUP}"
