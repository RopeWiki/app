#!/bin/bash

# This script is intended to be run as a nightly cron job to refresh a
# development server to mirror a production server.

# Prerequisites:
# * ropewiki/legacy_webserver image must be built (see Dockerfile_legacy)
# * ropewiki_legacy_mirror_db container must be running (run init_dev_server.sh to create)
# * You must have public key authentication to the remote production server.
# * You must have logged into the remote production server before (and accepted its fingerprint)
# * You must have created the folder ./mysql/backup/prod

DB_CONTAINER=ropewiki_legacy_mirror_db
WEBSERVER_CONTAINER=ropewiki_legacy_mirror_webserver
BRIDGE_NETWORK=ropewiki_mirror_net
PLACEHOLDER_CONTAINER=ropewiki_legacy_mirror_placeholder

function log(){
  echo "$(date --rfc-3339=seconds) $1"
}

if [ $# -ne 3 ]; then
  log "Usage: $0 WG_DB_PASSWORD PROTOCOL HOSTNAME"
  exit 1
fi

WG_DB_PASSWORD=$1
WG_PROTOCOL=$2
WG_HOSTNAME=$3

APP_FOLDER="`dirname \"$0\"`"
APP_FOLDER="`( cd \"$APP_FOLDER\" && pwd )`"
if [ -z "$APP_FOLDER" ] ; then
  log "Unable to determine path containing refresh_mirror_server.sh"
  exit 1
fi

cd $APP_FOLDER

# Retrieve latest backup
# NOTE: this requires public key authentication to the remote server
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

# Bring down webserver to update database and /images
if [ "$(docker ps -q -f name=${WEBSERVER_CONTAINER})" ]; then
  log "Stopping ${WEBSERVER_CONTAINER}..."
  docker container stop ${WEBSERVER_CONTAINER}
  log "  -> Stopped."
fi
if [ "$(docker ps -aq -f status=exited -f name=${WEBSERVER_CONTAINER})" ]; then
  echo ">> Removing stopped container ${WEBSERVER_CONTAINER}..."
  docker container rm ${WEBSERVER_CONTAINER}
fi

# Clean up any existing placeholder container
if [ "$(docker ps -q -f name=${PLACEHOLDER_CONTAINER})" ]; then
  echo ">> Killing running container ${PLACEHOLDER_CONTAINER}..."
  docker container kill ${PLACEHOLDER_CONTAINER}
fi
if [ "$(docker ps -aq -f status=exited -f name=${PLACEHOLDER_CONTAINER})" ]; then
  echo ">> Removing stopped container ${PLACEHOLDER_CONTAINER}..."
  docker container rm ${PLACEHOLDER_CONTAINER}
fi

# Bring up a placeholder saying we're down for upgrades
log "Bringing up maintenance notification..."
docker container run \
  --name ${PLACEHOLDER_CONTAINER} \
  -v `pwd`/mirror_resources/mirroring.html:/usr/share/nginx/html/index.html \
  -v `pwd`/mirror_resources/mirroring.conf:/etc/nginx/conf.d/default.conf \
  -p 9010:80 \
  -d \
  nginx

# Restore backup
# NOTE: this is insecure (displays password on process list); only use on a system with complete trust
log "Restoring backup..."
cat ${LATEST_BACKUP} | docker container exec -i ${DB_CONTAINER} mysql --user=ropewiki --password=${WG_DB_PASSWORD} ropewiki
log "  -> Backup restored."

# Restart database to recognize certain new changes
docker container restart ${DB_CONTAINER}
# Wait for container to come up
log "Waiting for database to restart..."
while DB_STATUS=$(docker inspect --format "{{.State.Health.Status}}" ${DB_CONTAINER}); [ $DB_STATUS != "healthy" ]; do
  echo "  ${DB_STATUS}..."
  sleep 10
done

# Retrieve latest files in /images folder
# NOTE: this requires public key authentication to the remote server
log "Copying latest /images content locally..."
touch ./html/ropewiki/images_backup.log
rsync -arv \
  root@ropewiki.com:/usr/share/nginx/html/ropewiki/images/ \
  ./html/ropewiki/images/ \
  2>&1 > ./html/ropewiki/images_backup.log
log "  -> Latest /images content copied locally."

# Bring down the placeholder
log "Bringing down maintenance notification..."
docker container kill ${PLACEHOLDER_CONTAINER}
docker container rm ${PLACEHOLDER_CONTAINER}

# Bring webserver back up
log "Bringing webserver back up..."
docker container run \
  --name ${WEBSERVER_CONTAINER} \
  -p 9010:80 \
  -e WG_DB_SERVER=${DB_CONTAINER} \
  -e WG_DB_USER=ropewiki \
  -e WG_DB_PASSWORD=$WG_DB_PASSWORD \
  -e WG_PROTOCOL=$WG_PROTOCOL \
  -e WG_HOSTNAME=$WG_HOSTNAME \
  -v `pwd`/html/ropewiki/images:/usr/share/nginx/html/ropewiki/images \
  --network ${BRIDGE_NETWORK} \
  -d \
  ropewiki/legacy_webserver

log "Refresh complete."

