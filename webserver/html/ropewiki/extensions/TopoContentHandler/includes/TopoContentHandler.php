<?php
/**
 * Class XmlContentHandler represents the set of operations for XMLContent that can be
 * performed without the actual content. Most importantly, it acts as a factory
 * and serialization/unserialization service for XmlContent objects.
 *
 * This extends TextContentHandler because XmlContent extends TextContent.
 * Content and ContentHandler implementations are generally paired like this.
 * See the documentation of XmlContent for more information.
 *
 * @package DataPages
 */
class TopoContentHandler extends \TextContentHandler {
	public function __construct(
		$modelId = 'TOPO_DATA',
		$formats = array( 'application/yaml' )
	) {
		parent::__construct( $modelId, $formats );
	}
	public function serializeContent( Content $content, $format = null ) {
		// No special logic needed; XmlContent just wraps the raw text.
		// If XmlContent were DOM-based, we'd serialize the XML DOM here.
		return parent::serializeContent( $content, $format );
	}
	public function unserializeContent( $text, $format = null ) {
		// No special logic needed; XmlContent just wraps the raw text.
		// If XmlContent were DOM-based, we'd parse the XML here.
		return new TopoContent( $text );
	}
	public function makeEmptyContent() {
		return new TopoContent( '' );
	}
	public function createDifferenceEngine( IContextSource $context,
		$old = 0, $new = 0, $rcid = 0,
		$refreshCache = false, $unhide = false
	) {
		// We could provide a custom difference engine for creating and
		// rendering diffs between XML structures.
		// The default implementation is line-based, which isn't too great for XML.
		return parent::createDifferenceEngine( $context, $old, $new, $rcid, $refreshCache, $unhide );
	}
	public function supportsSections() {
		// return true if XmlContent implements section-handling
		return parent::supportsSections();
	}
	public function supportsRedirects() {
		// return true if XmlContent supports representing redirects
		return parent::supportsRedirects();
	}
	public function merge3( Content $oldContent, Content $myContent, Content $yourContent ) {
		// You could implement smart DOM-based diff/merge here.
		// The default implementation is line-based, which isn't too great for XML.
		return parent::merge3( $oldContent, $myContent, $yourContent );
	}
}