<?php
 
// Take credit for your work.
$wgExtensionCredits['media'][] = array(
 
   // The full path and filename of the file. This allows MediaWiki
   // to display the Subversion revision number on Special:Version.
   'path' => __FILE__,
 
   // The name of the extension, which will appear on Special:Version.
   'name' => 'KML View',
 
   // A description of the extension, which will appear on Special:Version.
   'description' => 'Creates a Google Maps map and populates it with KML data from a specified URL',
 
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
$wgHooks['ParserFirstCallInit'][] = 'KmlViewSetupParserFunction';
 
// Allow translation of the parser function name
$wgExtensionMessagesFiles['KmlView'] = dirname( __FILE__ ) . '/KmlView.i18n.php';
 
// Tell MediaWiki that the parser function exists.
function KmlViewSetupParserFunction( &$parser ) {
 
   // Create a function hook associating the "kmltowiki" magic word with the
   // KmlViewParserFunction() function. See: the section 
   // 'setFunctionHook' below for details.
   $parser->setHook( 'kmlview', 'KmlViewRender' );
 
   // Return true so that MediaWiki continues to load extensions.
   return true;
}
 
// Render the output of the tag extension
function KmlViewRender( $input, array $args, Parser $parser, PPFrame $frame ) {
 
  // The input parameters are wikitext with templates expanded.
  // The output should be wikitext too.
  
  if (!array_key_exists('filename', $args)) return '<pre>filename argument not specified for kmlview</pre>' . usage();
  
  $url = $parser->recursiveTagParse('{{filepath:' . strip_tags($args['filename']) . '|nowiki}}');
  
  if (strlen($url) == 0) return '<pre>Invalid filename specified for kmlview; should be "FileName.ext", not "File:FileName.ext" or "FileName"</pre>' . usage();
  
  if (array_key_exists('width', $args)) $width = strip_tags($args['width']); else $width = '640px';
  if (array_key_exists('height', $args)) $height = strip_tags($args['height']); else $height = '480px';
  if (array_key_exists('maptype', $args)) $maptype = strip_tags($args['maptype']); else $maptype = 'TERRAIN';
  
  $url = str_replace('&#58;', ':', $url);
  
  $map = file_get_contents(dirname( __FILE__ ) . '/MapFragment.html');
  
  $map = str_replace('//PARAM_KMLURL//', $url, $map);
  $map = str_replace('//PARAM_WIDTH//', $width, $map);
  $map = str_replace('//PARAM_HEIGHT//', $height, $map);
  $map = str_replace('//PARAM_MAPTYPE//', $maptype, $map);
  
  return array( $map, "markerType" => 'nowiki' );
}

function usage() {
  return file_get_contents(dirname( __FILE__ ) . '/Usage.wiki');
}
