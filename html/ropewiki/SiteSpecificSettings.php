<?php
$wgSitename      = "ropewiki";
$wgMetaNamespace = "Ropewiki";

## The protocol and server name to use in fully-qualified URLs
$wgServer           = "http://ropewiki.com";

$wgLogo = "http://ropewiki.com/Ropewiki.png";

$semanticServer = 'ropewiki.com';

## Database settings
$wgDBtype           = "mysql";
$wgDBserver         = "ropewiki_legacy_db";
$wgDBname           = "ropewiki";
$wgDBuser           = "ropewiki";
$wgDBpassword       = "ropewikilegacydatabasepassword";

# Note: this is not the value for the real site
$wgSecretKey = "04f44118ad1899762bc60ed90d778aa72f92e9dc0d298c8f327755e503ceb84a";

# Site upgrade key. Must be set to a string (default provided) to turn on the
# web installer while LocalSettings.php is in place
# Note: this is not the value for the real site
$wgUpgradeKey = "1ce9e4e2a0a3bf63";
