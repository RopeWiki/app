<?php
# services.ropewiki.mode = "production": no errors on the page, nothing that names the software.
# Loaded after the repo's LocalSettings.php, which turns display_errors on and shows exception
# details. (Development mode adds nothing: the repo file already is the verbose configuration.)

ini_set( 'display_errors', '0' );
error_reporting( E_ALL & ~E_DEPRECATED & ~E_USER_DEPRECATED & ~E_STRICT );
$wgShowExceptionDetails = false;
$wgShowDBErrorBacktrace = false;
$wgShowSQLErrors = false;
$wgDevelopmentWarnings = false;

# Footer "Powered by MediaWiki" / "Semantic MediaWiki" icons. Both MediaWiki's Setup.php and SMW
# add theirs after LocalSettings.php has run, so remove them once everything is loaded.
$wgExtensionFunctions[] = static function () {
	global $wgFooterIcons;
	unset( $wgFooterIcons['poweredby'] );
};

# <meta name="generator" content="MediaWiki 1.39.x">
$wgHooks['OutputPageAfterGetHeadLinksArray'][] = static function ( &$tags ) {
	unset( $tags['meta-generator'] );
};

# Special:Version lists every extension with its version.
$wgHooks['SpecialPageBeforeExecute'][] = static function ( $special, $subPage ) {
	if ( $special->getName() === 'Version' && !$special->getUser()->isRegistered() ) {
		$special->getOutput()->redirect( SpecialPage::getTitleFor( 'Userlogin' )->getFullURL() );
		return false;
	}
	return true;
};
