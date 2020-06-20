#!/bin/bash

# This script is intended to be run once as preparation for the
# refresh_dev_server.sh script.  It sets up the required ropewiki_legacy_dev_db
# container.

if [ -z "${WG_DB_PASSWORD}" ] ; then
  echo "The environment variable WG_DB_PASSWORD must be set"
  exit 1
fi

# Clean up any existing container
if [ "$(docker ps -q -f name=ropewiki_legacy_dev_db)" ]; then
  echo "Killing running container ropewiki_legacy_dev_db..."
  docker container kill ropewiki_legacy_dev_db
fi
if [ "$(docker ps -aq -f status=exited -f name=ropewiki_legacy_dev_db)" ]; then
  echo ">> Removing stopped container ropewiki_legacy_dev_db..."
  docker container rm ropewiki_legacy_dev_db
fi

# Clean up any existing volume
if [ "$(docker volume ls | grep ropewiki_legacy_dev_db_storage)" ]; then
  echo ">> Deleting volume ropewiki_legacy_dev_db_storage..."
  docker volume rm ropewiki_legacy_dev_db_storage
fi


# Start running ropewiki_legacy_dev_db container
docker container run \
  -e MYSQL_ROOT_PASSWORD=${WG_DB_PASSWORD} \
  -v ropewiki_legacy_dev_db_storage:/var/lib/mysql \
  -v `pwd`/mysql/backup:/root/backup \
  --health-cmd='mysqladmin ping --silent' \
  --name ropewiki_legacy_dev_db \
  -d \
  mysql:5.5

# Wait for container to come up
echo ">> Waiting for MySQL database to initialize..."
while DB_STATUS=$(docker inspect --format "{{.State.Health.Status}}" ropewiki_legacy_dev_db); [ $DB_STATUS != "healthy" ]; do
  echo "  ${DB_STATUS}..."
  sleep 10
done

# Create an empty ropewiki database
echo ">> Creating empty ropewiki database..."
docker container exec ropewiki_legacy_dev_db \
  mysqladmin -u root -p${WG_DB_PASSWORD} create ropewiki

echo "Dev server database initialized successfully."

