#!/bin/bash

if test -f "/ropewiki_setup_complete"; then
  echo "*** RopeWiki reverse proxy already initialized"
else
  echo ">>> RopeWiki reverse proxy prep beginning..."

  echo "Configuring nginx services..."
  sed -i "s/{{WG_HOSTNAME}}/$WG_HOSTNAME/g" /etc/nginx/services.conf

  touch /ropewiki_setup_complete

  echo "<<< RopeWiki reverse proxy prep complete."
fi

echo "RopeWiki reverse proxy running nginx..."
cron &
nginx -g "daemon off;"
