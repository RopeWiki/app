#!/bin/bash

# This script acquires the latest .sql backup available at db01.ropewiki.com and places it in ./mysql/backup/prod
# It requires SSH access to db01.ropewiki.com.

if [[ $(pwd) == *app ]]
then
  echo "Working from $(pwd)"
else
  echo "Script working directory must be /app repo root; if you are running from the production folder, then: cd .."
  exit 1
fi

log "Finding latest database backup..."
LATEST_BACKUP_ZIP=$(ssh root@db01.ropewiki.com "cd /root/backups ; ls -1 -t | head -1")
log "  -> Found ${LATEST_BACKUP_ZIP}."
LATEST_BACKUP=${LATEST_BACKUP_ZIP%.gz}
if [ -f "./mysql/backup/prod/${LATEST_BACKUP}" ]; then
  log "${LATEST_BACKUP} is already present locally."
  LATEST_BACKUP=$(ls -t ./mysql/backup/prod/*.sql | head -1)
  log "  -> Using pre-existing ${LATEST_BACKUP}."
else
  log "Copying latest database backup locally..."
  touch ./mysql/backup/prod_backup.log
  rsync -arv \
    root@db01.ropewiki.com:/root/backups/${LATEST_BACKUP_ZIP} \
    ./mysql/backup/prod/${LATEST_BACKUP_ZIP} \
    2>&1 | tee ./mysql/backup/prod_backup.log
  log "  -> Copied."
  log "Unzipping ${LATEST_BACKUP_ZIP}..."
  gunzip -f ./mysql/backup/prod/${LATEST_BACKUP_ZIP}
  LATEST_BACKUP=$(ls -t ./mysql/backup/prod/*.sql | head -1)
  log "  -> Unzipped ${LATEST_BACKUP}."
fi
