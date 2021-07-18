#!/bin/bash

# This script is intended to be run once to create an empty database while
# deploying a production system. It sets up the ropewiki_legacy_db service
# defined in docker-compose.yaml

DB_CONTAINER=ropewiki_legacy_db
BRIDGE_NETWORK=ropewiki_legacy_net

if [ -z "${WG_DB_PASSWORD}" ] ; then
  echo "The environment variable WG_DB_PASSWORD must be set"
  exit 1
fi

# Ensure the database is down
docker compose stop ropewiki_legacy_db

# Clean up any existing volume
docker compose rm ropewiki_legacy_db

# Ensure the database is up
docker compose start ropewiki_legacy_db

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

