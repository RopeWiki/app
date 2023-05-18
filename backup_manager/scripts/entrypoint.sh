#!/bin/bash

if test -f "/ropewiki_setup_complete"; then
  echo "*** RopeWiki restarting..."

  service cron start
  service ssh start

  echo "*** RopeWiki restart complete."
else
  echo ">>> RopeWiki initial setup beginning..."

  if [ -z "${RW_ROOT_DB_PASSWORD}" ]; then
    echo "Disabling backups because RW_ROOT_DB_PASSWORD wasn't set"
    touch /do_not_backup_db
  else
    echo "Configuring periodic backup script..."
    sed -i "s/{{RW_ROOT_DB_PASSWORD}}/$RW_ROOT_DB_PASSWORD/g" /backup_mysql.sh
  fi

  service ssh start
  service cron start

  touch /ropewiki_setup_complete

  echo "<<< RopeWiki initial setup complete."
fi

trap : TERM INT; sleep infinity & wait
