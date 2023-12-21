#!/bin/bash

if test -f "/ropewiki_setup_complete"; then
  echo "*** RopeWiki reverse proxy already initialized"
else
  echo ">>> RopeWiki reverse proxy prep beginning..."

  echo "Configuring nginx services..."
  sed -i "s/{{WG_HOSTNAME}}/$WG_HOSTNAME/g" /etc/nginx/services.conf

  mkdir -p /logs/goaccess/db
  mkdir -p /logs/nginx
  touch /logs/nginx/access.log
  touch /ropewiki_setup_complete

  echo "<<< RopeWiki reverse proxy prep complete."
fi

## While we're short on CPU, disable log constant parsing
#echo "Starting up goaccess log parsing..."
#goaccess /logs/nginx/access.log \
#  -o /logs/goaccess/report.html \
#  --log-format COMBINED \
#  --real-time-html \
#  --ws-url wss://$WG_HOSTNAME:443/reportws \
#  --daemonize \
#  --db-path /logs/goaccess/db \
#  --restore \
#  --persist \
#  --html-refresh 10 \
#  --html-report-title "Ropewiki Stats"

echo "RopeWiki reverse proxy running nginx..."
nginx -g "daemon off;"
