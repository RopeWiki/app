<?php
use MediaWiki\Revision\SlotRecord;
class TopoHooks {

    public static function onBeforePageDisplay( OutputPage $out, Skin $skin ) {
        $out->addModules( 'ext.topo' );
        return true;
    }

    // Register "{{#toposvg}}"
    public static function onParserFirstCallInit( Parser $parser ) {
        $parser->setFunctionHook( 'toposvg', [ self::class, 'renderTopoSvg' ] );
        return true;
    }
    
    public static function renderTopoSvg( Parser $parser, $pageName = '' ) {
        if ( $pageName === '' ) {
            $title = $parser->getTitle();
            $pageName = $title ? $title->getText() : '';
        }
    
        $topoTitle = Title::newFromText( "Topo:$pageName" );
        if ( !$topoTitle || !$topoTitle->exists() ) {
            return "<!-- Topo page not found -->";
        }
    
        $page = WikiPage::factory( $topoTitle );
        $content = $page->getContent();
        $rawYaml = $content ? $content->getNativeData() : '';
    
        // $escaped = str_replace(
        //     ["\\", "`", "\$", "</script>"],
        //     ["\\\\", "\`", "\\$", "<\\/script>"],
        //     $rawYaml
        // );
    
        // Register the script in OutputPage (safe way to inject <script>)
        $parser->getOutput()->addHeadItem( <<<EOT
    <script>
        let raw = `$rawYaml`;

        import('/topo/lib/viewer.js').then(module => {
            console.log("[topo] quick_draw setup");
            // window.addEventListener('load', () => {
            console.log("[topo] quick_draw load");
            module.quick_draw('svg-preview', raw);
            // })
        });
    </script>
    EOT );
    
        // Return only the div
        $html = '
            <div id="svg-preview" class="topo-embed" style="width:100%; height:auto;"></div>
<div style="float:left; font-style:italic;font-size:12px;display:block"><a href="/Topo:'.$pageName.'?action=edit-topo">edit</a></div>
            ';
    
        return [ $html, 'isHTML' => true ];
    }
    
    


}