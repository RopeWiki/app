<?php

namespace MediaWiki\Extension\SemanticDependency;

use MediaWiki\MediaWikiServices;
use MediaWiki\Revision\RevisionRecord;
use MediaWiki\Storage\EditResult;
use MediaWiki\User\UserIdentity;
use Parser;
use SMWUpdateJob;
use Title;
use WikiPage;

class Hooks {

	private static $pagesToRefresh = [];

	public static function onParserFirstCallInit( Parser $parser ): void {
		$parser->setFunctionHook( 'semanticdependent', [ self::class, 'renderParserFunction' ] );
	}

	public static function renderParserFunction( Parser $parser, string $pageName = '' ): string {
		if ( $pageName === '' ) {
			self::log( 'ERROR: #semanticdependent called with no arguments' );
			return '<div class="error">Error: #semanticdependent requires a page name argument</div>';
		}

		$pageName = trim( $pageName );
		self::log( "Parser function called with page name: {$pageName}" );

		$title = Title::newFromText( $pageName );

		if ( $title === null ) {
			self::log( "ERROR: Could not create Title object for: {$pageName}" );
			return '<div class="error">Error: Invalid page title "' . htmlspecialchars( $pageName ) . '"</div>';
		}

		if ( !$title->exists() ) {
			self::log( "WARNING: Page does not exist: {$pageName}" );
		}

		self::$pagesToRefresh[] = $title;
		self::log( "Queued page for refresh: {$pageName} (total queued: " . count( self::$pagesToRefresh ) . ")" );

		return '';
	}

	public static function onPageSaveComplete(
		$wikiPage,
		$user,
		$summary,
		$flags,
		$revisionRecord,
		$editResult
	): void {
		$articleTitle = $wikiPage->getTitle()->getText();
		self::log( "PageSaveComplete hook called for page: {$articleTitle}" );
		self::log( "Number of pages queued for refresh: " . count( self::$pagesToRefresh ) );

		if ( count( self::$pagesToRefresh ) === 0 ) {
			self::log( "No pages to refresh, returning early" );
			return;
		}

		foreach ( self::$pagesToRefresh as $title ) {
			if ( !$title->exists() ) {
				self::log( "Skipping non-existent page: " . $title->getText() );
				continue;
			}

			$targetTitle = $title->getText();
			self::log( "Starting update job for dependent page: {$targetTitle}" );

			try {
				$updateJob = new SMWUpdateJob( $title );
				$result = $updateJob->run();

				if ( $result ) {
					self::log( "Successfully completed update job for: {$targetTitle}" );
				} else {
					self::log( "WARNING: Update job returned false for: {$targetTitle}" );
				}
			} catch ( \Exception $e ) {
				self::log( "ERROR updating {$targetTitle}: " . $e->getMessage() );
			}
		}

		self::log( "PageSaveComplete hook completed for: {$articleTitle}" );
		self::$pagesToRefresh = [];
	}

	private static function log( string $message ): void {
		$config = MediaWikiServices::getInstance()->getMainConfig();
		$loggingEnabled = $config->get( 'SemanticDependencyEnableLogging' );

		if ( !$loggingEnabled ) {
			return;
		}

		wfDebugLog( 'SemanticDependency', $message );
		error_log( "[SemanticDependency] {$message}" );
	}
}
