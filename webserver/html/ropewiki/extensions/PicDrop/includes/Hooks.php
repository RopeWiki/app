<?php

namespace PicDrop;

use EditPage;
use MediaWiki\MediaWikiServices;
use OutputPage;

class Hooks {
	/**
	 * Hook into EditPage to add PicDrop functionality
	 *
	 * @param EditPage $editPage
	 * @param OutputPage $out
	 * @return bool
	 */
	public static function onEditPageShowEditFormInitial( EditPage $editPage, OutputPage $out ) {
		// Get the title being edited
		$title = $out->getTitle();

		// Don't load on special pages
		if ( $title->isSpecialPage() ) {
			return true;
		}

		// Only load on wikitext pages
		if ( method_exists( MediaWikiServices::getInstance(), 'getWikiPageFactory' ) ) {
			// MW >= 1.36
			$wikiPage = MediaWikiServices::getInstance()->getWikiPageFactory()->newFromTitle( $title );
		} else {
			// MW < 1.36
			$wikiPage = $out->getWikiPage();
		}

		if ( $wikiPage->getContentModel() !== CONTENT_MODEL_WIKITEXT ) {
			return true;
		}

		// Pass configuration to JavaScript
		$picDropConfig = [
			'pageName' => $title->getText(),
			'pageNamespace' => $title->getNamespace(),
			'editToken' => $out->getUser()->getEditToken(),
		];

		$out->addJsConfigVars( 'picDropConfig', $picDropConfig );
		$out->addModules( 'ext.PicDrop' );

		return true;
	}
}
