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

# Configure robots.txt
cp "robots/$RW_ROBOTS" robots.txt

# Enable php opcache
php_ini="/etc/php/current/fpm/php.ini"
sed -i '/opcache.enable=/c\opcache.enable=1' $php_ini
sed -i '/opcache.enable_cli/c\opcache.enable_cli=1' $php_ini
sed -i '/opcache.memory_consumption/c\opcache.memory_consumption=128' $php_ini
sed -i '/opcache.interned_strings_buffer/c\opcache.interned_strings_buffer=8' $php_ini
sed -i '/opcache.max_accelerated_files/c\opcache.max_accelerated_files=10000' $php_ini
sed -i '/opcache.fast_shutdown/c\opcache.fast_shutdown=1' $php_ini

# Start up services
service php-fpm start
service nginx start
service cron start
service ssh start

# Start Sphinx indexer
cd /etc/sphinxsearch
sed -i "s/{{WG_DB_SERVER}}/$WG_DB_SERVER/g" sphinx.conf
sed -i "s/{{WG_DB_USER}}/$WG_DB_USER/g" sphinx.conf
sed -i "s/{{WG_DB_PASSWORD}}/$WG_DB_PASSWORD/g" sphinx.conf
echo Sphinx indexer started -- can take up to a minute
indexer --config /etc/sphinxsearch/sphinx.conf --all
sleep 2
echo Sphinx indexer finished -- starting service
# Restart searchd if it crashes: https://github.com/RopeWiki/app/issues/154
nohup bash -c "while true; do searchd --nodetach --config /etc/sphinxsearch/sphinx.conf >> /var/log/sphinxsearch/sphinx-startup.log 2>&1; sleep 2; done" &

echo RopeWiki webserver ready to go!

# Let the services run in the background indefinitely
while true; do sleep 86400; done
