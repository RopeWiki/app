<?php

namespace MediaWiki\Extension\SemanticDependency;

use MediaWiki\MediaWikiServices;
use Parser;
use SMWUpdateJob;
use Title;

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

		// Capture the pages to refresh and clear the static array immediately
		$pagesToRefresh = self::$pagesToRefresh;
		self::$pagesToRefresh = [];

		// Push SMWUpdateJobs to the job queue instead of running them immediately
		// This allows SMW to process the current page's semantic data first
		// (via its own queued jobs) before dependent pages query for it
		$jobQueueGroup = MediaWikiServices::getInstance()->getJobQueueGroup();

		foreach ( $pagesToRefresh as $title ) {
			if ( !$title->exists() ) {
				self::log( "Skipping non-existent page: " . $title->getText() );
				continue;
			}

			$targetTitle = $title->getText();
			self::log( "Pushing SMWUpdateJob to queue for dependent page: {$targetTitle}" );

			try {
				$updateJob = new SMWUpdateJob( $title );
				// Add a release timestamp to delay job execution by 5 seconds
				// This ensures SMW's own jobs for the current page run first
				$updateJob->setDelay( 5 );
				$jobQueueGroup->push( $updateJob );
				self::log( "Successfully queued update job with 5s delay for: {$targetTitle}" );
			} catch ( \Exception $e ) {
				self::log( "ERROR queueing job for {$targetTitle}: " . $e->getMessage() );
			}
		}

		self::log( "PageSaveComplete hook completed for: {$articleTitle}" );
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
