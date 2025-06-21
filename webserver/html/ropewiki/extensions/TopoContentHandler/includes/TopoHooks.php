<?php

use MediaWiki\Revision\SlotRecord;

class TopoHooks {

    public static function onBeforePageDisplay( $out, $skin ) {
        $out->addModules( 'ext.topo' );
        return true;
    }

    // Register "{{#toposvg:}}" so other pages can embed a topo inline.
    public static function onParserFirstCallInit( $parser ) {
        $parser->setFunctionHook( 'toposvg', [ self::class, 'renderTopoSvg' ] );
        return true;
    }


      public static function onSkinTemplateNavigation( &$skin, &$links ) {
          $title = $skin->getTitle();

          // Only customize tabs for Topo pages
          if ( $title->getContentModel() === 'TOPO_DATA' ) {
              // Rename existing tabs
              if ( isset( $links['views']['view'] ) ) {
                  $links['views']['view']['text'] = 'View Topo';
              }
              if ( isset( $links['views']['edit'] ) ) {
                  $links['views']['edit']['text'] = 'Edit Raw';
              }

              // Insert "Edit topo" tab right after "view" tab
              $editTopoTab = [
                  'class' => false,
                  'text' => 'Edit Topo',
                  'href' => $title->getLocalURL( 'action=edit-topo' ),
                  'primary' => true,
              ];

              // Find position of 'view' tab and insert after it
              $newViews = [];
              foreach ( $links['views'] as $key => $tab ) {
                  $newViews[$key] = $tab;
                  if ( $key === 'view' ) {
                      $newViews['edit-topo'] = $editTopoTab;
                  }
              }
              $links['views'] = $newViews;
          }

          return true;
      }



    public static function renderTopoSvg( $parser, $pageName = '' ) {
        // Trim so "{{#toposvg: Name}}" (with a space) resolves correctly.
        $pageName = trim( $pageName );
        if ( $pageName === '' ) {
            $title = $parser->getTitle();
            $pageName = $title ? $title->getText() : '';
        }

        $topoTitle = Title::newFromText( "Topo:$pageName" );
        if ( !$topoTitle || !$topoTitle->exists() ) {
            return [
                '<span class="error">Topo page not found: Topo:' . htmlspecialchars( $pageName ) . '</span>',
                'isHTML' => true,
            ];
        }

        $page = WikiPage::factory( $topoTitle );
        $content = $page->getContent();
        $rawYaml = $content ? $content->getNativeData() : '';

        // Load viewer scripts/styles once per page (key prevents duplicate injection).
        $parser->getOutput()->addHeadItem(
            '<script src="/topo/redux/deps/js-yaml.min.js"></script>' . "\n" .
            '<script src="/topo/redux/lib/renderer.js"></script>' . "\n" .
            '<script src="/topo/redux/lib/viewer.js"></script>' . "\n" .
            '<link rel="stylesheet" href="/topo/redux/style.css" />',
            'topo-viewer-scripts'
        );
        // raw_yaml is read by viewer.js on DOMContentLoaded.
        // Note: only one topo embed per page is supported — a second {{#toposvg:}} would
        // reuse the first page's YAML because this head item is keyed.
        $parser->getOutput()->addHeadItem(
            '<script>let raw_yaml = ' . json_encode( $rawYaml ) . ';</script>',
            'topo-raw-yaml'
        );

        // getLocalURL() handles URL-encoding of spaces and special characters.
        $editUrl = htmlspecialchars( $topoTitle->getLocalURL( [ 'action' => 'edit-topo' ] ) );

        $html =
            '<div id="topo-container"></div>' .
            '<div style="font-style:italic;font-size:12px;">' .
                '<a href="' . $editUrl . '">edit topo</a>' .
            '</div>';

        return [ $html, 'isHTML' => true ];
    }
}