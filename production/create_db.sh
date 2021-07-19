#!/bin/bash

# This script is intended to be run once to create an empty database while
# deploying a production system. It sets up the ropewiki_legacy_db service
# defined in docker-compose.yaml

function log(){
  echo "$(date --rfc-3339=seconds) $1"
}

DB_CONTAINER=production_ropewiki_legacy_db_1
WG_DB_PASSWORD=thispasswordonlyworksuntildbisrestored

log >> Deleting/cleaning up any existing database...

# Ensure the database is down
docker-compose stop ropewiki_legacy_db

# Clean up any existing volume
docker-compose rm -v ropewiki_legacy_db
docker volume rm ropewiki_database_storage

# Bring the database up
docker-compose up -d ropewiki_legacy_db

# Wait for container to come up
log ">> Waiting for MySQL database to initialize..."
sleep 10
while DB_STATUS=$(docker inspect --format "{{.State.Status}}" ${DB_CONTAINER}); [ $DB_STATUS != "running" ]; do
  echo "  ${DB_STATUS}..."
  sleep 10
done

# Create an empty ropewiki database
log ">> Creating empty ropewiki database..."
docker container exec ${DB_CONTAINER} \
  mysqladmin -u root -p${WG_DB_PASSWORD} create ropewiki

# Create the ropewiki user
log ">> Creating ropewiki user..."
docker container exec ${DB_CONTAINER} \
  bash -c "mysql -u root -p${WG_DB_PASSWORD} -e \"CREATE USER 'ropewiki'@'localhost' IDENTIFIED BY '${WG_DB_PASSWORD}'; GRANT ALL PRIVILEGES ON * . * TO 'ropewiki'@'localhost';\""

log "RopeWiki database initialized successfully."
