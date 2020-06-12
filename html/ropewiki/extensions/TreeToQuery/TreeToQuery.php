<?php
 
// Take credit for your work.
$wgExtensionCredits['parserhook'][] = array(
 
   // The full path and filename of the file. This allows MediaWiki
   // to display the Subversion revision number on Special:Version.
   'path' => __FILE__,
 
   // The name of the extension, which will appear on Special:Version.
   'name' => 'Tree to Query',
 
   // A description of the extension, which will appear on Special:Version.
   'description' => 'A processor that converts the output of an #ask command using format=tree into || delineated results for use in a query',
 
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
$wgHooks['ParserFirstCallInit'][] = 'TreeToQuerySetupParserFunction';
 
// Allow translation of the parser function name
$wgExtensionMessagesFiles['TreeToQuery'] = dirname( __FILE__ ) . '/TreeToQuery.i18n.php';
 
// Tell MediaWiki that the parser function exists.
function TreeToQuerySetupParserFunction( &$parser ) {
 
   // Create a function hook associating the "kmltowiki" magic word with the
   // TreeToQueryParserFunction() function. See: the section 
   // 'setFunctionHook' below for details.
   $parser->setFunctionHook( 'treetoquery', 'TreeToQueryRenderParserFunction' );
 
   // Return true so that MediaWiki continues to load extensions.
   return true;
}
 
// Render the output of the parser function.
function TreeToQueryRenderParserFunction( $parser, $treetext = '' ) {
 
  // The input parameters are wikitext with templates expanded.
  // The output should be wikitext too.
  
  $n = strlen($treetext);
  if ($n == 0) return "<nowiki>Usage: {{#treetoquery: {{#ask: ... |format=tree}}}}</nowiki>";

  $mode = 2; //0: content, 1: divider, 2: ignore
  
  $dividerchars = ",*";
  $ignorechars = "[]:\n\r";
  
  $output = "";
  
  for ($i = 0; $i < $n; $i++) {
    if ($mode == 0) { //Content
      if (strpos($dividerchars, $treetext[$i]) === FALSE) {
        if (strpos($ignorechars, $treetext[$i]) === FALSE) {
          if ($treetext[$i] == "|")
            $mode = 2;
          else
            $output .= $treetext[$i];
        } else {
          //Do nothing; ignoring these characters
        }
      } else {
        $output .= "||";
        $mode = 1;
      }
    } elseif ($mode == 1) { //Divider
      if (strpos($dividerchars, $treetext[$i]) === FALSE)
        $mode = 0;
    } elseif ($mode == 2) { //Ignore
      if (strpos($dividerchars, $treetext[$i]) === FALSE)
        $mode = 2;
      else
        $mode = 0;
    }
  }
  
  return $output;
}
