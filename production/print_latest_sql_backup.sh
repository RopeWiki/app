#!/bin/bash

BACKUP_FOLDER=$1
if [[ -z "${BACKUP_FOLDER}" ]]
then
  log "Missing BACKUP_FOLDER; usage: print_latest_sql_backup.sh <BACKUP_FOLDER>"
  exit 1
fi

ls -t ${BACKUP_FOLDER}/*.sql | head -1
