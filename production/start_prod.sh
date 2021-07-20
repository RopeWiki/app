#!/bin/bash

# This script starts production services, assuming the folder paths declared
# at the top of this file.

SQL_BACKUP_FOLDER=/rw/mount/sqlbackup
IMAGES_FOLDER=/rw/mount/images

docker-compose -d up
