#!/bin/bash

# This script starts production services, assuming the folder paths declared
# at the top of this file.

SQL_BACKUP_FOLDER=/rw/mount/sqlbackup
IMAGES_FOLDER=/rw/mount/images

if [[ -z "${WG_DB_PASSWORD}" ]]
then
  echo Warning: environment variable WG_DB_PASSWORD not set; a restored database will probably not work.
fi

docker-compose up -d
