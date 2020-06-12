<?php
 
// Take credit for your work.
$wgExtensionCredits['media'][] = array(
 
   // The full path and filename of the file. This allows MediaWiki
   // to display the Subversion revision number on Special:Version.
   'path' => __FILE__,
 
   // The name of the extension, which will appear on Special:Version.
   'name' => 'Semantic Dependency',
 
   // A description of the extension, which will appear on Special:Version.
   'description' => 'Allows pages to specify that other pages should have their semantic data updated in response to an update of the current page',
 
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
$wgHooks['ParserFirstCallInit'][] = 'SemanticDependencySetupParserFunction';

// Hook the page save completion event as well
$wgHooks['PageContentSaveComplete'][] = 'SemanticDependencyPageContentSaveComplete';
 
// Allow translation of the parser function name
$wgExtensionMessagesFiles['SemanticDependency'] = dirname( __FILE__ ) . '/SemanticDependency.i18n.php';
 
// Tell MediaWiki that the parser function exists.
function SemanticDependencySetupParserFunction( &$parser ) {
 
   // Create a function hook associating the "semanticdependent" magic word with the
   // SemanticDependencyParserFunction() function. See: the section 
   // 'setFunctionHook' below for details.
   $parser->setFunctionHook( 'semanticdependent', 'SemanticDependencyRenderParserFunction' );
 
   // Return true so that MediaWiki continues to load extensions.
   return true;
}

// Actually perform the refreshes after the page is saved
$sdpfPagesToRefresh = array();
function SemanticDependencyPageContentSaveComplete( $article, $user, $content, $summary, $isMinor, $isWatch, $section, $flags, $revision, $status, $baseRevId ) {
  global $sdpfPagesToRefresh;
  foreach ($sdpfPagesToRefresh as $t) {
    $updatejob = new SMWUpdateJob( $t );
    $updatejob->run();

    //$refreshcmd = "php " . getcwd() . "/extensions/SemanticMediaWiki/maintenance/SMW_refreshData.php -s " . $t->getArticleID() . " -n 0";
    //exec($refreshcmd);
  }
  return true;
}

// Render the output of the tag extension
function SemanticDependencyRenderParserFunction( $parser ) {
 
  // The input parameters are wikitext with templates expanded.
  // The output should be wikitext too.
  
  if (func_num_args() == 0)
    return SemanticDependency_usage();
  
  $titletoupdate = Title::newFromText( func_get_arg(1) );

  if ( is_null( $titletoupdate ) )
    return "<pre>semanticdependent error: couldn't instantiate a Title</pre>";
  if ( !$titletoupdate->exists() )
    return "<pre>semanticdependent error: no page named " . func_get_arg(1) . "</pre>";

  global $sdpfPagesToRefresh;
  $sdpfPagesToRefresh[] = $titletoupdate;
  return "";
  //return "semanticdependent has " . count($sdpfPagesToRefresh) . " refreshes queued";
}

function SemanticDependency_usage() {
  return "<pre>semanticdependent usage error; expected: #semanticdependent:PageTitle</pre>";
}
