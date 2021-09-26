#!/bin/bash

DATE=`date -I`
BACKUP=/home/backupreader/backups/all-backup-${DATE}.sql.gz

mysqldump --all-databases \
          --add-drop-database \
          --single-transaction \
          --user=root --password="{{RW_ROOT_DB_PASSWORD}}" \
          | gzip > ${BACKUP}

# Owner: rwx, Group: r--, Others: r--
chmod 744 ${BACKUP}
