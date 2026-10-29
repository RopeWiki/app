# The wiki pages that hold the site's JavaScript and CSS, built from the commonjs and commoncss
# repositories (flake inputs). One file per page, named by the page title:
#
#   MediaWiki:Common.js, MediaWiki:Waterflow.js, MediaWiki:Common.css, MediaWiki:Common-00-original.css, ...
#
# The `ropewiki-pages` service writes them into the wiki. This replaces the repositories' own
# upload.py scripts; the build steps are theirs (commonjs/build.js, commoncss/build.py).
{
  lib,
  runCommand,
  applyPatches,
  buildNpmPackage,
  commonjs,
  commoncss,
}:

let
  # Local changes to commonjs, until they are merged there.
  #   site-pages-drainage.patch: the drainage-area badge shows tenths and takes the number from
  #   `drainage_km2`, which the service that replaced the Luca server's waterflow lookup sends
  #   (nix/docs/drainage.md). It still understands RWServer's reply.
  #   site-pages-luca-host.patch: /luca is always reached through the page's own host.
  commonjsSrc = applyPatches {
    name = "source"; # the unpacker (sourceRoot below) looks for this name
    src = commonjs;
    patches = [
      ./site-pages-drainage.patch
      ./site-pages-luca-host.patch
    ];
  };

  # commonjs/build.js and waterflowjs/build.js both need uglify-js, which only commonjs lists in
  # its package.json (waterflowjs has a lockfile but no package.json), so one npm install serves both.
  js = buildNpmPackage {
    pname = "ropewiki-site-js";
    version = "0";
    src = commonjsSrc;
    sourceRoot = "source/commonjs";
    npmDepsHash = "sha256-h7zZz2uYnRvyqXZ89kEXtt+mgTplUDFa1bYo8SODUpU=";
    # @playwright/test is a dev dependency (for the repository's tests); never download browsers.
    env.PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD = "1";
    dontNpmBuild = true;
    dontNpmInstall = true;
    buildPhase = ''
      runHook preBuild
      node build.js
      chmod -R u+w ../waterflowjs # stdenv only made the source root writable
      (cd ../waterflowjs && mkdir -p out && NODE_PATH=$PWD/../commonjs/node_modules node build.js)
      mkdir -p $out
      cp out/Common.min.js $out/Common.js
      cp ../waterflowjs/out/Waterflow.min.js $out/Waterflow.js
      runHook postBuild
    '';
  };
in
runCommand "ropewiki-site-pages" { } ''
  mkdir -p $out
  cp ${js}/Common.js "$out/MediaWiki:Common.js"
  cp ${js}/Waterflow.js "$out/MediaWiki:Waterflow.js"

  # commoncss: common.css is a list of @imports of the Common-<module>.css pages. build.py writes
  # it; fail if the committed one has fallen out of step with src/.
  cp ${commoncss}/common.css "$out/MediaWiki:Common.css"
  for f in ${commoncss}/src/*.css; do
    name=$(basename "$f" .css)
    grep -qF "MediaWiki:Common-$name.css" ${commoncss}/common.css \
      || { echo "common.css does not import src/$name.css; run build.py in commoncss" >&2; exit 1; }
    cp "$f" "$out/MediaWiki:Common-$name.css"
  done
  imports=$(grep -c '^@import url("/MediaWiki:Common-' ${commoncss}/common.css)
  modules=$(ls ${commoncss}/src/*.css | wc -l)
  [ "$imports" = "$modules" ] \
    || { echo "common.css has $imports imports, src/ has $modules files" >&2; exit 1; }
''
