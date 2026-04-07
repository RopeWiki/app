<?php

if ( function_exists( 'wfLoadExtension' ) ) {
	wfLoadExtension( 'SemanticDependency' );
	$wgMessagesDirs['SemanticDependency'] = __DIR__ . '/i18n';
	$wgExtensionMessagesFiles['SemanticDependencyMagic'] = __DIR__ . '/SemanticDependency.i18n.php';
	wfWarn(
		'Deprecated PHP entry point used for SemanticDependency extension. ' .
		'Please use wfLoadExtension instead, ' .
		'see https://www.mediawiki.org/wiki/Extension_registration for more details.'
	);
	return;
} else {
	die( 'This version of the SemanticDependency extension requires MediaWiki 1.25+' );
}
