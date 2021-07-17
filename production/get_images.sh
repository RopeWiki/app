#!/bin/bash

# Retrieve latest files in /images folder from remote server at ropewiki.com
# It requires SSH access to ropewiki.com.

function log(){
  echo "$(date --rfc-3339=seconds) $1"
}

BACKUP_FOLDER=$1
if [[ -z "${BACKUP_FOLDER}" ]]
then
  log "Missing BACKUP_FOLDER; usage: get_images.sh <BACKUP_FOLDER>"
  exit 1
fi

# NOTE: this requires public key authentication to the remote server
log "Copying latest /images content locally..."
LOG_FILE="${BACKUP_FOLDER}/images_backup.log"
touch ${LOG_FILE}
rsync -arv \
  root@ropewiki.com:/usr/share/nginx/html/ropewiki/images/ \
  ${BACKUP_FOLDER}/images/ \
  2>&1 > ${LOG_FILE}
log "  -> Latest /images content copied locally."
