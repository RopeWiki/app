#!/bin/bash

# Restore content from a .sql backup file into the ropewiki_legacy_db database
# described in docker-compose.yaml.

function log(){
  echo "$(date --rfc-3339=seconds) $1"
}

DB_CONTAINER=production_ropewiki_legacy_db_1
WG_DB_PASSWORD=thispasswordonlyworksuntildbisrestored

BACKUP_FOLDER=$1
if [[ -z "${BACKUP_FOLDER}" ]]
then
  log "Missing BACKUP_FOLDER; usage: restore_db.sh <BACKUP_FOLDER>"
  exit 1
fi

LATEST_BACKUP=$(./print_latest_sql_backup.sh ${BACKUP_FOLDER})
if [[ -z "${BACKUP_FOLDER}" ]]
then
  log "Could not find latest backup in ${BACKUP_FOLDER}"
  exit 1
fi

log "Restoring backup ${LATEST_BACKUP}..."
cat ${LATEST_BACKUP} | docker container exec -i ${DB_CONTAINER} mysql --user=ropewiki --password=${WG_DB_PASSWORD} ropewiki
log "  -> Backup restored."
