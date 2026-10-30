# shellcheck shell=bash
# Recreate nix/composer/core/composer.json: MediaWiki core's own composer.json for the pinned
# version (nix/packages/mediawiki-pins.json), plus the changes RopeWiki makes to it. These are
# the Composer steps of webserver/Dockerfile and the platform settings Nix needs.
# The first step of `nix run .#update-composer` (see update-composer.sh), which then re-locks
# and refreshes composer-vendor.nix's outputHash; run that, not this. This step alone leaves
# composer.lock stale. The platform PHP is `mediawiki.php` in the pins.
root=${ROPEWIKI_ROOT:-$(git rev-parse --show-toplevel)}
pins=$root/nix/packages/mediawiki-pins.json
dest=${ROPEWIKI_COMPOSER_JSON:-$root/nix/composer/core/composer.json}

version=$(jq -r .mediawiki.version "$pins")
url=https://raw.githubusercontent.com/wikimedia/mediawiki/$version/composer.json

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
cd "$work"
export COMPOSER_HOME=$work/home COMPOSER_CACHE_DIR=$work/cache

echo "downloading MediaWiki $version composer.json..." >&2
curl --fail --silent --show-error --location "$url" --output composer.json

composer() { command composer --no-plugins --no-interaction --quiet "$@"; }

# Resolve against the PHP the site runs (mediawiki.php in the pins), whatever PHP runs this script.
composer config platform.php "$(jq -r .mediawiki.php "$pins")"
composer config --json platform-check false
# See https://github.com/RopeWiki/app/issues/162
composer config --json policy.advisories.block false

composer require --no-update mediawiki/semantic-media-wiki 4.2.0
# We don't use mediawiki/maps for maps! We use it for data types.
#   See https://github.com/RopeWiki/app/issues/141
# Maps 10.x-11.x required for MW 1.39 (fixes RepoGroup::singleton() and wfGetCache(), but <12.0 which needs MW 1.40+)
composer require --no-update mediawiki/maps "^10.0.4"
composer require --no-update mediawiki/semantic-result-formats "^4.2.1"
# The SphinxSearch extension's own composer.json requires this; it is installed here, with
# everything else, rather than by a second `composer install` inside the extension.
composer require --no-update neutron/sphinxsearch-api "*"

mkdir -p "$(dirname "$dest")"
if cmp -s composer.json "$dest"; then
  echo "$dest unchanged"
else
  cp composer.json "$dest"
  echo "$dest updated; composer.lock is now stale (see the top of this script)"
fi
