# shellcheck shell=bash
# Everything to do after changing MediaWiki's version or the packages we add: regenerate
# nix/composer/core/composer.json, re-lock it, and refresh composerVendor's outputHash.
# Run as `nix run .#update-composer` (see composer-vendor.nix); needs the network.
root=${ROPEWIKI_ROOT:-$(git rev-parse --show-toplevel)}
export ROPEWIKI_ROOT=$root

update-composer-json

echo "locking..." >&2
# --no-install: only resolve. The scripts and plugins are MediaWiki's, which is not here.
(cd "$root/nix/composer/core" &&
  composer update --no-install --no-scripts --no-plugins --no-interaction \
    --ignore-platform-reqs --no-dev)

update-composer-vendor
