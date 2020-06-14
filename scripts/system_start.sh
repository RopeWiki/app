#!/bin/sh

echo RopeWiki webserver starting...

# Configure site-specific settings from template
cd /rw
cp SiteSpecificSettings.php.template SiteSpecificSettings.php
sed -i "s/{{WG_DB_SERVER}}/$WG_DB_SERVER/g" SiteSpecificSettings.php
sed -i "s/{{WG_DB_USER}}/$WG_DB_USER/g" SiteSpecificSettings.php
sed -i "s/{{WG_DB_PASSWORD}}/$WG_DB_PASSWORD/g" SiteSpecificSettings.php
sed -i "s/{{WG_HOSTNAME}}/$WG_HOSTNAME/g" SiteSpecificSettings.php
sed -i "s/{{WG_PROTOCOL}}/$WG_PROTOCOL/g" SiteSpecificSettings.php
sed -i "s/{{WG_SECRET_KEY}}/$WG_SECRET_KEY/g" SiteSpecificSettings.php
sed -i "s/{{WG_UPGRADE_KEY}}/$WG_UPGRADE_KEY/g" SiteSpecificSettings.php

# Start up services
service php5-fpm start
service nginx start

echo RopeWiki webserver ready to go!

# Let the services run in the background indefinitely
while true; do sleep 86400; done
