<?php
 
// Take credit for your work.
$wgExtensionCredits['media'][] = array(
 
   // The full path and filename of the file. This allows MediaWiki
   // to display the Subversion revision number on Special:Version.
   'path' => __FILE__,
 
   // The name of the extension, which will appear on Special:Version.
   'name' => 'Simple Link',
 
   // A description of the extension, which will appear on Special:Version.
   'description' => 'Creates a hard html anchor link when the wiki parser will not cooperate',
 
   // Alternatively, you can specify a message key for the description.
   //'descriptionmsg' => 'exampleextension-desc',
 
   // The version of the extension, which will appear on Special:Version.
   // This can be a number or a string.
   'version' => '0.1', 
 
   // Your name, which will appear on Special:Version.
   'author' => 'Benjamin Pelletier',
 
   // The URL to a wiki page/web page with information about the extension,
   // which will appear on Special:Version.
   'url' => 'http://ropewiki.com/',
 
);


// Specify the function that will initialize the parser function.
$wgHooks['ParserFirstCallInit'][] = 'SimpleLinkSetupParserFunction';
 
// Allow translation of the parser function name
$wgExtensionMessagesFiles['SimpleLink'] = dirname( __FILE__ ) . '/SimpleLink.i18n.php';
 
// Tell MediaWiki that the parser function exists.
function SimpleLinkSetupParserFunction( &$parser ) {
 
   // Create a function hook associating the "simplelink" magic word with the
   // SimpleLinkParserFunction() function. See: the section 
   // 'setFunctionHook' below for details.
   $parser->setHook( 'simplelink', 'SimpleLinkRender' );
 
   // Return true so that MediaWiki continues to load extensions.
   return true;
}
 
// Render the output of the tag extension
function SimpleLinkRender( $input, array $args, Parser $parser, PPFrame $frame ) {
 
  // The input parameters are wikitext with templates expanded.
  // The output should be wikitext too.
  
  if (!array_key_exists('href', $args) || !array_key_exists('anchortext', $args)) return '<pre>Usage: &lt;simplelink href="" anchortext=""/></pre>';

  $href = $parser->recursiveTagParse($args['href']);
  $anchortext = $parser->recursiveTagParse($args['anchortext']);
  $linktext = '<a href="' . strip_tags($href) . '">' . strip_tags($anchortext) . '</a>';

  return array($linktext, "markerType" => 'nowiki' );
}
