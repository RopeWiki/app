<?php

class TopoEditAction extends Action {

    public function getName() {
        // Return the name of this action
        return 'edit-topo';
    }

    public function show() {
        $output = $this->getOutput();
        $title = $this->getTitle();
        $page = WikiPage::factory( $title );
        $content = $page->getContent();
        $text = $content ? $content->getNativeData() : '';
        
        $output->setPageTitle( $title );

        // Add custom HTML or JavaScript for your custom edit page
        $output->addHTML( '

        <script>
          let raw = `'.$text.'`;
        </script>
        <script src="https://cdn.jsdelivr.net/npm/interactjs/dist/interact.min.js"></script>
        <link rel="stylesheet" href="/topo/style.css" />
        
        <div id="topocontainer">
        <div id="leftcol">
          <h2>Feature List</h2>
          <div id="feature-list-container">
            <ul id="feature-list"></ul>
          </div>
          <br /><br />
          <textarea id="yaml-textbox" cols="100" rows="30" >'.$text.'</textarea><br />
          <button id="save-btn">Save</button>
          <input type="checkbox" id="highlight-checkbox" />Highlight Mode
        </div>

        <div id="rightcol">
          <h2>Preview</h2>
          <div id="svg-preview"></div>
        </div>
      </div>
  ' );

    }
}
