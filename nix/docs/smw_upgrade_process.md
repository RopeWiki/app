SMW offline upgrade process

Create https://ropewiki.com/UpgradeTest (used for confirming correct DB snapshot).
Confirm ropewiki.com checked out on master
Enable maintenance banner in: https://ropewiki.com/MediaWiki:Common.js
Disable edits in LocalSettings.php:

$wgGroupPermissions['*']['edit'] = false;
$wgGroupPermissions['user']['edit'] = false;
$wgGroupPermissions['sysop']['edit'] = false;

Run outstanding maintenance jobs before backing up db:

php /rw/maintenance/runJobs.php --nothrottle --procs 2

Take production backup (/backup_mysql.sh in backup container)
Copy backup locally
Confirm dev server checked out on master & restore db backup
Confirm UpgradeTest page exists.
Checkout smw-258-302 & redeploy webserver
Delete `.smw.json` in container
Start upgrade!

php extensions/SemanticMediaWiki/maintenance/setupStore.php (couple of mins)

php extensions/SemanticMediaWiki/maintenance/populateHashField.php -v (68m)

php extensions/SemanticMediaWiki/maintenance/rebuildData.php -v --with-maintenance-log (~19h)  ←- Update: This can be deferred until afterwards, and run in the background of production.

php /rw/maintenance/runJobs.php --nothrottle --procs 8 (TBD)

Create https://ropewiki.attack-kitten.com/UpgradeComplete
Take db backup and copy to production server.
Stop webserver, restore database
Checkout smw-258-302
redeploy webserver
Confirm UpgradeComplete page exists!

Notes:
Check: https://www.semantic-mediawiki.org/wiki/Help:Outdated_entities
php extensions/SemanticMediaWiki/maintenance/rebuildData.php --skip-properties -s 1 -e 1

