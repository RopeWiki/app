#!/bin/bash

# This script is intended to be run as a nightly cron job to refresh a
# development server to mirror a production server.

# Prerequisites:
# * ropewiki_legacy_dev_db container must be running; run init_dev_server.sh to create
# * You must have public key authentication to the remote production server.
# * You must have logged into the remote production server before (and accepted its fingerprint)
# * You must have created the folder $APP_FOLDER/mysql/backup/prod

function log(){
  echo "$(date --rfc-3339=seconds) $1"
}

if [ $# -ne 2 ]; then
  log "Usage: $0 WG_DB_PASSWORD HOSTNAME"
  exit 1
fi

WG_DB_PASSWORD=$1
WG_DB_HOSTNAME=$2

APP_FOLDER="`dirname \"$0\"`"
APP_FOLDER="`( cd \"$APP_FOLDER\" && pwd )`"
if [ -z "$APP_FOLDER" ] ; then
  log "Unable to determine path containing refresh_dev_server.sh"
  exit 1
fi

cd $APP_FOLDER

# Retrieve latest backup
# NOTE: this requires public key authentication to the remote server
log "Finding latest database backup..."
LATEST_BACKUP_ZIP=$(ssh root@db01.ropewiki.com "cd /root/backups ; ls -1 -t | head -1")
log "  -> Found ${LATEST_BACKUP_ZIP}."
log "Copying latest database backup locally..."
rsync -arv --delete \
  root@db01.ropewiki.com:/root/backups/${LATEST_BACKUP_ZIP} \
  ./mysql/backup/prod \
  2>&1 | tee ./mysql/backup/prod_backup.log
log "  -> Copied."
log "Unzipping ${LATEST_BACKUP_ZIP}..."
gunzip -y ./mysql/backup/prod/${LATEST_BACKUP_ZIP}
LATEST_BACKUP=$(ls ./mysql/backup/prod/*.sql | head -1)
log "  -> Unzipped ${LATEST_BACKUP}."

# Bring down webserver to update database and /images
if [ "$(docker ps -q -f name=ropewiki_legacy_dev_webserver)" ]; then
  log "Stopping ropewiki_legacy_dev_webserver..."
  docker container stop ropewiki_legacy_dev_webserver
  log "  -> Stopped."
fi

# Restore backup
# NOTE: this is insecure (displays password on process list); only use on a system with complete trust
log "Restoring backup..."
cat ${LATEST_BACKUP} | docker container exec -i ropewiki_legacy_dev_db mysql --user=root --password=${WG_DB_PASSWORD} ropewiki
log "  -> Backup restored."

# Retrieve latest files in /images folder
# NOTE: this requires public key authentication to the remote server
log "Copying latest /images content locally..."
rsync -arv --delete \
  root@ropewiki.com:/usr/share/nginx/html/ropewiki/images \
  ./html/ropewiki/images/ \
  2>&1 | ./html/ropewiki/images_backup.log
log "  -> Latest /images content copied locally."

# Bring webserver back up
docker container run \
  --name ropewiki_legacy_dev_webserver \
  -p 9010:80 \
  -e WG_DB_SERVER=ropewiki_legacy_dev_db \
  -e WG_DB_USER=ropewiki \
  -e WG_DB_PASSWORD=$WG_DB_PASSWORD \
  -e WG_HOSTNAME=$WG_HOSTNAME \
  -v `pwd`/html/ropewiki/images:/usr/share/nginx/html/ropewiki/images \
  ropewiki/legacy_webserver


