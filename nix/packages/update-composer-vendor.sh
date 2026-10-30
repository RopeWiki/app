# shellcheck shell=bash
# Recompute `outputHash` in nix/packages/composer-vendor.nix after composer.json/composer.lock
# changed. The last step of `nix run .#update-composer` (see update-composer.sh).
# The file is only written once the build reported the real hash.
root=${ROPEWIKI_ROOT:-$(git rev-parse --show-toplevel)}
file=$root/nix/packages/composer-vendor.nix

old=$(sed -n 's/^  outputHash = "\(.*\)";$/\1/p' "$file")
[ -n "$old" ] || { echo "no outputHash line found in $file" >&2; exit 1; }

log=$(mktemp)
trap 'rm -f "$log"' EXIT

# Build with a placeholder hash: Nix fails the fixed-output check and prints the real one.
echo "building composerVendor to learn its hash (needs the network)..." >&2
# shellcheck disable=SC2016 # `${...}` is Nix, not shell
nix build --no-link --impure --argstr root "$root" --expr '
  { root }:
  (builtins.getFlake root).packages.${builtins.currentSystem}.composerVendor.overrideAttrs (_: {
    outputHash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
  })
' 2>"$log" || true

new=$(sed -n 's/^ *got: *\(sha256-[A-Za-z0-9+\/]*=*\)$/\1/p' "$log" | head -n1)
if [ -z "$new" ]; then
  cat "$log" >&2
  echo "composerVendor failed to build, or did not report a hash" >&2
  exit 1
fi

if [ "$new" = "$old" ]; then
  echo "composer-vendor outputHash unchanged ($old)"
else
  sed -i "s|^\(  outputHash = \"\).*\(\";\)\$|\1$new\2|" "$file"
  echo "composer-vendor outputHash updated:"
  echo "  $old"
  echo "  $new"
fi
