#!/bin/bash

# This script is intended to be run once as preparation for the
# refresh_mirror_server.sh script.  It sets up the required ropewiki_legacy_mirror_db
# container.

DB_CONTAINER=ropewiki_legacy_mirror_db
BRIDGE_NETWORK=ropewiki_mirror_net

if [ -z "${WG_DB_PASSWORD}" ] ; then
  echo "The environment variable WG_DB_PASSWORD must be set"
  exit 1
fi

# Create bridge network
if [ ! "$(docker network ls | grep ${BRIDGE_NETWORK})" ]; then
  echo ">> Creating bridge network ${BRIDGE_NETWORK}..."
  docker network create --driver bridge ${BRIDGE_NETWORK}
fi

# Clean up any existing container
if [ "$(docker ps -q -f name=${DB_CONTAINER})" ]; then
  echo ">> Killing running container ${DB_CONTAINER}..."
  docker container kill ${DB_CONTAINER}
fi
if [ "$(docker ps -aq -f status=exited -f name=${DB_CONTAINER})" ]; then
  echo ">> Removing stopped container ${DB_CONTAINER}..."
  docker container rm ${DB_CONTAINER}
fi

# Clean up any existing volume
if [ "$(docker volume ls | grep ${DB_CONTAINER}_storage)" ]; then
  echo ">> Deleting volume ${DB_CONTAINER}_storage..."
  docker volume rm ${DB_CONTAINER}_storage
fi


# Start running ${DB_CONTAINER} container
echo ">> Starting database container..."
docker container run \
  --name ${DB_CONTAINER} \
  -e MYSQL_ROOT_PASSWORD=${WG_DB_PASSWORD} \
  -v ${DB_CONTAINER}_storage:/var/lib/mysql \
  -v `pwd`/mysql/backup:/root/backup \
  --health-cmd='mysqladmin ping --silent' \
  --network ${BRIDGE_NETWORK} \
  -d \
  mysql:5.5

# Wait for container to come up
echo ">> Waiting for MySQL database to initialize..."
while DB_STATUS=$(docker inspect --format "{{.State.Health.Status}}" ${DB_CONTAINER}); [ $DB_STATUS != "healthy" ]; do
  echo "  ${DB_STATUS}..."
  sleep 10
done

# Create an empty ropewiki database
echo ">> Creating empty ropewiki database..."
docker container exec ${DB_CONTAINER} \
  mysqladmin -u root -p${WG_DB_PASSWORD} create ropewiki

# Create the ropewiki user
echo ">> Creating ropewiki user..."
docker container exec ${DB_CONTAINER} \
  bash -c "mysql -u root -p${WG_DB_PASSWORD} -e \"CREATE USER 'ropewiki'@'localhost' IDENTIFIED BY '${WG_DB_PASSWORD}'; GRANT ALL PRIVILEGES ON * . * TO 'ropewiki'@'localhost';\""

echo "Mirror server database initialized successfully."

