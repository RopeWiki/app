# The RopeWiki web application tree, assembled the same way webserver/Dockerfile does:
#
#   MediaWiki 1.39 core
#   + Composer-installed SMW / Maps / SRF / Sphinx client   (./composer-vendor.nix)
#   + the extensions the Dockerfile `git clone`s            (pinned by mediawiki-pins.json)
#   + leaflet & friends from npm                            (what fetch-npm-assets.sh does)
#   + the repo's own overlay, webserver/html/ropewiki
#   + the Dockerfile's patches
#
# The result is immutable and configuration free. Everything site specific
# (hostname, database, secrets, tool paths) is injected at runtime by the
# NixOS module through two PHP files named in environment variables, see the
# LocalSettings.php / SiteSpecificSettings.php set up below.
{
  lib,
  stdenvNoCC,
  fetchurl,
  callPackage,
  gnupatch,
  gpsbabel,
  # the git-cloned extensions, see ./mediawiki-ext.nix
  mediawikiExtensions,
  # path to this repository
  repoRoot,
  codebaseVersion ? "unknown",
}:

let
  mwVersion = mediawikiExtensions.mediawiki.version;

  mediawiki = mediawikiExtensions.mediawiki.src;

  composerVendor = callPackage ./composer-vendor.nix { };

  # The parts of this repository the build needs. Limiting the fileset means
  # editing nix/ or docs does not rebuild the site.
  repoSrc = lib.fileset.toSource {
    root = repoRoot;
    fileset = repoRoot + "/webserver";
  };
  overlay = "${repoSrc}/webserver/html/ropewiki";

  # webserver/scripts/fetch-npm-assets.sh, without npm.
  npmTarball =
    {
      name,
      version,
      hash,
    }:
    stdenvNoCC.mkDerivation {
      pname = "npm-${name}";
      inherit version;
      src = fetchurl {
        url = "https://registry.npmjs.org/${name}/-/${name}-${version}.tgz";
        inherit hash;
      };
      installPhase = "cp -r dist $out";
    };

  leaflet = npmTarball {
    name = "leaflet";
    version = "1.9.4";
    hash = "sha256-hMZaJW5QZXiW9UwzvYV7aEnr6UyBeAO+gYvzKj3eC3c=";
  };
  leafletDraw = npmTarball {
    name = "leaflet-draw";
    version = "1.0.4";
    hash = "sha256-s+wWGpMa2Is/AIKDuCTOrFr5i17GA4d/KUg00e3MOqY=";
  };
  leafletFullscreen = npmTarball {
    name = "leaflet-fullscreen";
    version = "1.0.1";
    hash = "sha256-P69Fx5Q6VexvHqagWAoExrfLWwA1TQGl3zIaV3oNu14=";
  };
  leafletVectorgrid = npmTarball {
    name = "leaflet.vectorgrid";
    version = "1.3.0";
    hash = "sha256-Tq8AucPIDlPVmoSp01I/G5rjFJ5wnbb6KT6cKSc57X4=";
  };
in
stdenvNoCC.mkDerivation {
  pname = "ropewiki";
  version = mwVersion;

  src = mediawiki;

  nativeBuildInputs = [ gnupatch ];

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    root=$out/share/ropewiki
    mkdir -p $root
    cp -r . $root
    chmod -R u+w $root
    cd $root

    # --- Composer: replace the tarball's vendor/ with our locked one -------------
    rm -rf vendor
    cp -r ${composerVendor}/vendor vendor
    cp -r ${composerVendor}/extensions/* extensions/
    # update.php insists on a composer.lock matching vendor/ (and the extensions' requirements).
    install -m644 ${composerVendor.src}/composer.json ${composerVendor.src}/composer.lock .
    chmod -R u+w vendor extensions

    # --- git-cloned extensions ---------------------------------------------------
    ${lib.concatStringsSep "\n" (
      lib.mapAttrsToList (n: src: "cp -r ${src} extensions/${n}") mediawikiExtensions.sources
    )}
    chmod -R u+w extensions

    # --- npm assets --------------------------------------------------------------
    mkdir -p leaflet leaflet-draw leaflet-fullscreen
    cp -r ${leaflet} leaflet/${leaflet.version}
    cp -r ${leafletDraw} leaflet-draw/${leafletDraw.version}
    cp -r ${leafletFullscreen} leaflet-fullscreen/${leafletFullscreen.version}
    cp -r ${leafletVectorgrid} leaflet-vectorgrid
    chmod -R u+w .

    # --- the repo's own files (custom extensions, skins, favicon, ...) -------------
    cp -rT --no-preserve=mode ${overlay} .
    # The patches are applied below from the store; the rest of what sits next to the code is
    # editor leftovers, per-site templates (replaced below) and Docker-only config.
    find extensions -name '*.patch' -delete
    find . -name '*.save' -delete
    rm -f .gitignore SiteSpecificSettings.php.template extensions/SemanticMediaWiki/.smw.json \
          extensions/SphinxSearch/sphinx.conf extensions/SphinxSearch/sphinx.cron

    # --- Dockerfile: SRF slideshow needs the consolidated jquery.ui module (MW >= 1.35)
    ( cd extensions/SemanticResultFormats/formats/slideshow
      sed -i 's/jquery.ui.slider/jquery.ui/' SRF_SlideShow.php resources/ext.srf.slideshow.js )

    # --- Dockerfile: patches. Invocations mirror webserver/Dockerfile exactly. -----
    ext=${overlay}/extensions
    ( cd extensions/SphinxSearch
      patch -l < $ext/SphinxSearch/SphinxMWSearch.REL1_39.patch
      patch -l -p0 < $ext/SphinxSearch/SphinxMWSearchResultSet.php.REL1_39.patch )
    ( cd extensions/Arrays
      patch -l < $ext/Arrays/ExtArrays.php.REL1_39.patch )
    ( cd extensions/PageForms
      patch -l -p0 < $ext/PageForms/PF_AutoEdit.php.REL1_39.patch
      patch -l -p0 < $ext/PageForms/PF_TemplateField.php.REL1_39.patch
      patch -l -p0 < $ext/PageForms/PF_FormPrinter.php.REL1_39.patch
      patch -l -p0 < $ext/PageForms/PF_upload.js.REL1_39.patch
      patch -l -p0 < $ext/PageForms/extension.json.REL1_39.patch )

    # --- Paths that only make sense inside the Docker image ------------------------
    substituteInPlace kml_to_gpx.php \
      --replace-fail "realpath('/rw' . \$path)" \
                     "realpath(getenv('ROPEWIKI_IMAGES_DIR') . preg_replace('#^/images#', ''', \$path))" \
      --replace-fail "'/usr/share/nginx/html/ropewiki/images/'" \
                     "rtrim(getenv('ROPEWIKI_IMAGES_DIR'), '/') . '/'" \
      --replace-fail "/usr/bin/gpsbabel" "${gpsbabel}/bin/gpsbabel"

    # --- Entry points ----------------------------------------------------------------
    # The repo's LocalSettings.php does `require_once SiteSpecificSettings.php` first and then
    # hardcodes a few Docker paths. Both files come from the NixOS module (see its comments):
    # site values go in before, overrides are appended after.
    cat > SiteSpecificSettings.php <<'EOF'
    <?php
    require getenv( 'ROPEWIKI_SITE_SETTINGS' );
    EOF
    printf '\nrequire getenv( %s );\n' "'ROPEWIKI_OVERRIDES'" >> LocalSettings.php

    # Served as /codebase_version.html, see the codebaseversion build arg.
    echo "<html><body>${codebaseVersion}</body></html>" > codebase_version.html

    # The tarball's release notes, README, FAQ, ... sit in the web root. They are not needed at
    # runtime, they tell visitors exactly which version this is, and files like FAQ shadow wiki
    # pages of the same name. Keep them as documentation instead.
    mkdir -p $out/share/doc/ropewiki
    for f in RELEASE-NOTES-* HISTORY UPGRADE FAQ INSTALL CREDITS README.md CODE_OF_CONDUCT.md \
             SECURITY COPYING jsduck.json docker-compose.yml composer.local.json-sample; do
      if test -e "$f"; then mv "$f" $out/share/doc/ropewiki/; fi
    done

    # Nothing in here is ever written to; state lives in /var/lib/ropewiki.
    rm -rf images cache

    runHook postInstall
  '';

  passthru = {
    inherit
      composerVendor
      mediawiki
      repoSrc
      mwVersion
      ;
    # Files the NixOS module consumes straight from the repository.
    sphinxConfTemplate = "${overlay}/extensions/SphinxSearch/sphinx.conf";
    robotsDir = "${repoSrc}/webserver/robots";
  };

  meta = {
    description = "RopeWiki: MediaWiki ${mwVersion} with Semantic MediaWiki and site customisations";
    homepage = "https://github.com/RopeWiki/app";
    license = lib.licenses.gpl2Plus;
    platforms = lib.platforms.linux;
  };
}
