#!/bin/bash

# This script starts production services, assuming the folder paths declared
# at the top of this file.

SQL_BACKUP_FOLDER=/rw/mount/sqlbackup
IMAGES_FOLDER=/rw/mount/images
PROXY_CONFIG_FOLDER=/rw/mount/proxy_config

if [[ -z "${WG_DB_PASSWORD}" ]]
then
  echo Warning: environment variable WG_DB_PASSWORD not set; a restored database will probably not work.
fi

if [[ -z "${WG_HOSTNAME}" ]]
then
  echo Warning: environment variable WG_HOSTNAME not set; default hostname will be used.
fi

mkdir -p PROXY_CONFIG_FOLDER

docker-compose up -d
