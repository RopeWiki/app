
let pageCanyonName = mw.config.get('wgPageName').replace(/_/g, ' ').replace(/^Topo:/, '');
let pageFullName = mw.config.get('wgPageName');
console.log("[topo] Loading ext.topo.js", pageCanyonName, pageFullName);

const action = mw.config.get('wgAction');

if (action === 'view') {
    console.log("[topo] Viewing a page");

    import('/topo/lib/viewer.js').then(module => {
        console.log("[topo] quick_draw setup");
        // window.addEventListener('load', () => {
        console.log("[topo] quick_draw load");
        module.quick_draw('svg-preview', raw);
        // })
    });


} else if (action === 'edit' || action === 'submit') {
    console.log("[topo] Editing a page");
} else if (action === 'edit-topo') {
    console.log("[topo] Using custom topo edit action");

    window.topo = window.topo || {
        config: null,
        highlight_mode: false,
        selectedItemIndex: null,
        RW_DOMAIN: "https://ropewiki.attack-kitten.com",
        pageCanyonName: mw.config.get('wgPageName').replace(/_/g, ' ').replace(/^Topo:/,''),
        pageFullName: mw.config.get('wgPageName'),
    };

    import('/topo/lib/editor.js').then((module) => {
        module.setup(); // Call setup() after import finishes
    });

}


