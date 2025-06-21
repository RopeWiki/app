<?php

class TopoEditAction extends Action {

    public function getName() {
        // Return the name of this action
        return 'edit-topo';
    }

    public function show() {
        $output = $this->getOutput();
        $title = $this->getTitle();
        $request = $this->getRequest();

        // Support MediaWiki undo URLs (?undo=X&undoafter=Y).
        // For YAML topo content a 3-way text merge is fragile, so we simply
        // restore the undoafter revision's content into the editor — the user
        // can then save it as a new revision that reverts the unwanted change.
        $undoAfterParam = $request->getInt( 'undoafter' );
        $undoParam      = $request->getInt( 'undo' );

        $text = '';
        if ( $undoParam && $undoAfterParam ) {
            $undoAfterRev = Revision::newFromId( $undoAfterParam );
            if ( $undoAfterRev && $undoAfterRev->getTitle()->equals( $title ) ) {
                $undoContent = $undoAfterRev->getContent();
                $text = $undoContent ? $undoContent->getNativeData() : '';
            }
        }

        if ( $text === '' ) {
            $page = WikiPage::factory( $title );
            $content = $page->getContent();
            $text = $content ? $content->getNativeData() : '';
        }

        $output->setPageTitle( $title );

        $output->addHTML(
            '<script>let raw_yaml = ' . json_encode( $text ) . ';</script>' .
            '<script src="/topo/redux/deps/js-yaml.min.js"></script>' .
            '<script src="/topo/redux/lib/renderer.js"></script>' .
            '<script src="/topo/redux/lib/editor.js"></script>' .
            '<script src="/topo/redux/lib/editor-features.js"></script>' .
            '<script src="/topo/redux/lib/editor-ui.js"></script>' .
            '<script src="/topo/redux/lib/editor-feature-list.js"></script>' .
            '<script src="/topo/redux/lib/editor-io.js"></script>' .
            '<link rel="stylesheet" href="/topo/redux/style.css" />' .
            '<div id="topo-container"></div>'
        );
    }
}
