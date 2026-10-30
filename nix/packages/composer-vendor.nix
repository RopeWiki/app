# The PHP dependencies that webserver/Dockerfile installs with `composer require`:
# MediaWiki's own library set plus Semantic MediaWiki, Maps, Semantic Result
# Formats and the Sphinx client API.
#
# composer/installers (a Composer plugin) drops the `mediawiki-extension`
# packages into ./extensions/<Name>, so the output has two interesting parts:
#   $out/vendor       the autoloader + libraries
#   $out/extensions   SemanticMediaWiki, Maps, SemanticResultFormats, Validator
#
# This is a fixed-output derivation (Composer needs the network and plugins),
# pinned by nix/composer/core/composer.lock.
#
# composer.json is generated (update-composer-json.sh): MediaWiki's own for the pinned version
# plus our packages and settings. Change the packages there, not in the file.
#
# To change versions, run `nix run .#update-composer` (passthru.updateAll). It regenerates
# composer.json, re-locks it (composer.lock) and refreshes `outputHash`.
{
  lib,
  stdenvNoCC,
  php83,
  php83Packages,
  cacert,
  writeShellApplication,
  git,
  gnused,
  jq,
  curl,
  nix,
}:

let
  updater = writeShellApplication {
    name = "update-composer-vendor";
    runtimeInputs = [
      git
      gnused
      nix
    ];
    text = builtins.readFile ./update-composer-vendor.sh;
  };

  # Recreates composer/core/composer.json from MediaWiki's own plus our additions.
  jsonUpdater = writeShellApplication {
    name = "update-composer-json";
    runtimeInputs = [
      git
      jq
      curl
      cacert
      php83
      php83Packages.composer
    ];
    text = builtins.readFile ./update-composer-json.sh;
  };

  # All of the above in order: composer.json, then composer.lock, then outputHash.
  updateAll = writeShellApplication {
    name = "update-composer";
    runtimeInputs = [
      git
      php83
      php83Packages.composer
      jsonUpdater
      updater
    ];
    text = builtins.readFile ./update-composer.sh;
  };
in
stdenvNoCC.mkDerivation {
  pname = "ropewiki-composer-vendor";
  version = "1.39.17";

  src = lib.fileset.toSource {
    root = ../composer/core;
    fileset = lib.fileset.unions [
      ../composer/core/composer.json
      ../composer/core/composer.lock
    ];
  };

  nativeBuildInputs = [
    php83
    php83Packages.composer
    cacert
  ];

  dontConfigure = true;
  # A fixed-output derivation may not reference store paths (patched shebangs).
  dontFixup = true;

  buildPhase = ''
    runHook preBuild

    export HOME=$TMPDIR
    export COMPOSER_HOME=$TMPDIR/composer
    export COMPOSER_CACHE_DIR=$TMPDIR/composer-cache
    export COMPOSER_ROOT_VERSION=1.39.17
    export SSL_CERT_FILE=${cacert}/etc/ssl/certs/ca-bundle.crt

    composer install \
      --no-dev --no-scripts --no-interaction --no-progress \
      --prefer-dist --optimize-autoloader --ignore-platform-reqs

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out
    cp -r vendor extensions $out/
    runHook postInstall
  '';

  # Keep the output byte-for-byte reproducible.
  postInstall = ''
    find $out -name ".git" -type d -prune -exec rm -rf {} +
  '';

  passthru = { inherit updater jsonUpdater updateAll; };

  outputHashMode = "recursive";
  outputHashAlgo = "sha256";
  outputHash = "sha256-gc8XBfcYUuUUCJel9CFzqAcmb+sTbBRmnoAgNr3tRcQ=";
}
