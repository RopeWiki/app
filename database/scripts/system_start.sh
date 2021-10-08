#!/bin/bash

if test -f "/ropewiki_setup_complete"; then
  echo "*** RopeWiki restarting..."

  service cron start
  service ssh start

  echo "*** RopeWiki restart complete."
else
  echo ">>> RopeWiki entry prep beginning..."

  if [ -z "${RW_ROOT_DB_PASSWORD}" ]; then
    echo "Disabling backups because RW_ROOT_DB_PASSWORD wasn't set"
    cp /home/root/do_not_backup.sh /home/root/backup_mysql.sh
  else
    echo "Configuring periodic backup script..."
    sed -i "s/{{RW_ROOT_DB_PASSWORD}}/$RW_ROOT_DB_PASSWORD/g" /home/root/backup_mysql.sh
  fi

  # Enable SSH
  service ssh start

  touch /ropewiki_setup_complete

  echo "<<< RopeWiki entrypoint prep complete."
fi
