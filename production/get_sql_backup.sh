#!/bin/bash

# This script acquires the latest .sql backup available at db01.ropewiki.com and places it in the specified folder
# It requires SSH access to db01.ropewiki.com.

function log(){
  echo "$(date --rfc-3339=seconds) $1"
}

BACKUP_FOLDER=$1
if [[ -z "${BACKUP_FOLDER}" ]]
then
  log "Missing BACKUP_FOLDER; usage: get_sql_backup.sh <BACKUP_FOLDER>"
  exit 1
fi

log "Finding latest database backup..."
LATEST_BACKUP_ZIP=$(ssh root@db01.ropewiki.com "cd /root/backups ; ls -1 -t | head -1")
log "  -> Found ${LATEST_BACKUP_ZIP}."
LATEST_BACKUP=${LATEST_BACKUP_ZIP%.gz}
LOCAL_TARGET="${BACKUP_FOLDER}/${LATEST_BACKUP}"
if [ -f "${LOCAL_TARGET}" ]; then
  log "${LATEST_BACKUP} is already present locally at ${LOCAL_TARGET}."
  LATEST_BACKUP=$(./print_latest_sql_backup.sh ${BACKUP_FOLDER})
  log "  -> Using pre-existing ${LATEST_BACKUP}."
else
  log "Copying latest database backup locally..."
  mkdir -p ${BACKUP_FOLDER}
  LOG_FILE="${BACKUP_FOLDER}/get_sql.log"
  touch ${LOG_FILE}
  rsync -arv \
    root@db01.ropewiki.com:/root/backups/${LATEST_BACKUP_ZIP} \
    ${BACKUP_FOLDER}/${LATEST_BACKUP_ZIP} \
    2>&1 | tee ${LOG_FILE}
  log "  -> Copied."
  log "Unzipping ${LATEST_BACKUP_ZIP}..."
  gunzip -f ${BACKUP_FOLDER}/${LATEST_BACKUP_ZIP}
  LATEST_BACKUP=$(./print_latest_sql_backup.sh ${BACKUP_FOLDER})
  log "  -> Unzipped ${LATEST_BACKUP}."
fi
