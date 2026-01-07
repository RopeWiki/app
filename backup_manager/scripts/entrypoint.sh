#!/bin/bash

echo ">>> RopeWiki setup beginning..."

chown backupreader /home/backupreader/backups

if [ -z "${RW_ROOT_DB_PASSWORD}" ]; then
  echo "Disabling backups because RW_ROOT_DB_PASSWORD wasn't set"
  touch /do_not_backup_db
else
  echo "Configuring periodic backup script..."
  sed -i "s/{{RW_ROOT_DB_PASSWORD}}/$RW_ROOT_DB_PASSWORD/g" /backup_mysql.sh
fi

service ssh start
service cron start

echo "<<< RopeWiki setup complete."

trap : TERM INT; sleep infinity & wait
