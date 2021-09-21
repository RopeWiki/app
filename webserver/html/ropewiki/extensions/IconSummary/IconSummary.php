<?php
 
// Take credit for your work.
$wgExtensionCredits['media'][] = array(
 
   // The full path and filename of the file. This allows MediaWiki
   // to display the Subversion revision number on Special:Version.
   'path' => __FILE__,
 
   // The name of the extension, which will appear on Special:Version.
   'name' => 'Icon Summary',
 
   // A description of the extension, which will appear on Special:Version.
   'description' => 'Summarizes the difficulty of a trip with icons containing pop-up explanations',
 
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
$wgHooks['ParserFirstCallInit'][] = 'IconSummarySetupParserFunction';
 
// Allow translation of the parser function name
$wgExtensionMessagesFiles['IconSummary'] = dirname( __FILE__ ) . '/IconSummary.i18n.php';
 
// Tell MediaWiki that the parser function exists.
function IconSummarySetupParserFunction( &$parser ) {
 
   // Create a function hook associating the "kmltowiki" magic word with the
   // IconSummaryParserFunction() function. See: the section 
   // 'setFunctionHook' below for details.
   $parser->setFunctionHook( 'iconsummary', 'IconSummaryRenderParserFunction' );
 
   // Return true so that MediaWiki continues to load extensions.
   return true;
}
 
// Render the output of the tag extension
function IconSummaryRenderParserFunction( $parser ) {
 
  // The input parameters are wikitext with templates expanded.
  // The output should be wikitext too.
  
  if (func_num_args() == 0)
    return IconSummary_usage();
  
  $icons = array("time", "drive", "hike", "tech", "water", "cold", "hot", "gear", "cost");
  $titles = array(
    "time" => "Time",
    "drive" => "Drive",
    "hike" => "Level of physical activity",
    "tech" => "Technical difficulty",
    "water" => "Water",
    "cold" => "Cold",
    "hot" => "Heat",
    "gear" => "Special gear",
    "cost" => "Cost"
  );
  $summary = array();
  foreach ($icons as $icon)
    $summary[$icon] = array("rating" => 0, "description" => "not specified");
  
  $optmode = 0;
  for ($i = 1; $i < func_num_args(); $i++) {
    $v = func_get_arg($i);
    if ($optmode == 0) {
      $idx = array_search($v, $icons);
      if ($idx === false)
        return '<pre>Input parameter ' . $i . ' was an invalid icon type</pre>' . IconSummary_usage();
      $currenticon = $v;
      $optmode = 1;
    } else if ($optmode == 1) {
      $summary[$currenticon]["rating"] = strip_tags($v);
      $optmode = 2;
    } else {
      $summary[$currenticon]["description"] = strip_tags($v);
      $optmode = 0;
    }
	}
  
  if ($optmode != 0)
    return '<pre>Inputs must be specified in sets of 3: icon|rating|description</pre>' . IconSummary_usage();
  
  global $wgScriptPath;
  $path = $wgScriptPath . '/extensions/IconSummary/';
  
  $output = '<link rel="stylesheet" type="text/css" href="' . $path . 'IconSummary.css" />';
  $output .= '<div class="Trip">';
  foreach ($summary as $icon => $content) {
    $output .= '  <div class="ContextDetails">';
    $output .= '    <img src="' . $path . 'img/' . $icon . $content["rating"] . '.png" class="RatingIcon" />';
		$output .= '    <div><b>' . $titles[$icon] . '</b><br />' . $content["description"] . '</div>';
    $output .= '  </div>';
  }
  $output .= '</div>';
  $output .= '<script type="text/javascript" src="' . $path . 'IconSummary.js"></script>';
  
  return array( $output, 'noparse' => true, 'isHTML' => true );
}

function IconSummary_usage() {
  return file_get_contents(dirname( __FILE__ ) . '/Usage.wiki');
}
