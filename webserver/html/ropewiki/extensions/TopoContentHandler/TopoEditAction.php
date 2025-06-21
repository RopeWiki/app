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
          <script src="/topo/deps/js-yaml.min.js"></script>
  <script src="/topo/deps/Sortable.min.js"></script>
  <script src="/topo/lib/draw.js"></script>
  <script src="/topo/lib/dragging.js"></script>
  <script src="/topo/lib/io.js"></script>
  <script src="/topo/lib/highlight.js"></script>
  <script src="/topo/lib/wiki.js"></script>
  <script src="/topo/lib/buttons.js"></script>
  <script src="/topo/lib/ui.js"></script>
  <link rel="stylesheet" href="/topo/style.css" />
        
        <div id="topocontainer">
    <div id="leftcol">
      <h2>Feature List</h2>
      <div id="feature-list-container">
        <ul id="feature-list"></ul>
      </div>
      <br /><br />
      <textarea id="yaml-textbox" cols="100" rows="30" >'.$text.'</textarea><br />
      <button id="load-yaml-button">Load YAML</button>
      <button id="save-btn">Save to RW</button>
      <button id="update-button">Force Update SVG</button>
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
