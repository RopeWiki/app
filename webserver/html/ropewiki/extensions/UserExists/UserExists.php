<?php
if ( function_exists( 'wfLoadExtension' ) ) {
    wfLoadExtension( 'UserExists' );
    // Keep i18n files out of compiled cache
    $wgMessagesDirs['UserExists'] = __DIR__ . '/i18n';
    return;
} else {
    die( 'This version of the UserExists extension requires MediaWiki 1.25+' );
}
