# shellcheck shell=bash
# Re-pin MediaWiki core and every git-cloned extension in nix/packages/mediawiki-pins.json.
# Run as `nix run .#update-mediawiki-ext [-- NAME...]` (see mediawiki-ext.nix for the rules).
# Nothing is written unless everything selected resolved and prefetched.
pins=${ROPEWIKI_PINS:-$(git rev-parse --show-toplevel)/nix/packages/mediawiki-pins.json}

if [ $# -gt 0 ]; then
  names=("$@")
else
  names=(mediawiki); mapfile -t -O 1 names < <(jq -r '.extensions | keys[]' "$pins")
fi

# The branch every extension follows unless it says otherwise: 1.39.17 -> REL1_39.
version=$(jq -r .mediawiki.version "$pins")
release=REL$(cut -d. -f1,2 <<<"$version" | tr . _)

# Print the commit of the first of the given refs that exists upstream. An annotated tag
# lists both the tag object and, as "<tag>^{}", the commit it points at; we want the latter.
resolve() {
  local url=$1 ref listing
  shift
  for ref in "$@"; do
    if [ "$ref" = HEAD ]; then
      listing=$(git ls-remote "$url" HEAD)
    else
      listing=$(git ls-remote "$url" "$ref" "$ref^{}")
    fi
    if [ -n "$listing" ]; then
      { grep -F '^{}' <<<"$listing" || head -n1 <<<"$listing"; } | head -n1 | cut -f1
      return 0
    fi
  done
  return 1
}

new=$(mktemp)
trap 'rm -f "$new" "$new.tmp"' EXIT
cp "$pins" "$new"

for name in "${names[@]}"; do
  if [ "$name" = mediawiki ]; then
    oldhash=$(jq -r .mediawiki.hash "$pins")
    url="https://releases.wikimedia.org/mediawiki/$(cut -d. -f1,2 <<<"$version")/mediawiki-$version.tar.gz"
    # The hash belongs to the version: refetch when the tarball behind it may have changed.
    base32=$(nix-prefetch-url --type sha256 "$url" 2>/dev/null) || base32=
    [ -n "$base32" ] || { echo "mediawiki: cannot download $url (is $version a real release?)" >&2; exit 1; }
    hash=$(nix-hash --type sha256 --to-sri "$base32")
    if [ "$hash" = "$oldhash" ]; then
      printf '%-18s %-10s (unchanged)\n' mediawiki "$version"
    else
      printf '%-18s %-10s hash updated\n' mediawiki "$version"
      jq --arg hash "$hash" '.mediawiki.hash = $hash' "$new" > "$new.tmp"
      mv "$new.tmp" "$new"
    fi
    continue
  fi

  entry=$(jq -ce --arg n "$name" '.extensions[$n] // empty' "$pins") || true
  [ -n "$entry" ] || { echo "unknown extension: $name" >&2; exit 1; }
  url=$(jq -r .url <<<"$entry")
  oldrev=$(jq -r .rev <<<"$entry"); oldhash=$(jq -r .hash <<<"$entry")
  pinned=$(jq -r '.ref // empty' <<<"$entry")

  if [ -n "$pinned" ]; then
    follows=$pinned
    if [ "$pinned" = HEAD ] && [ -z "$(jq -r '.note // empty' <<<"$entry")" ]; then
      echo "$name: following HEAD needs a \"note\" in $pins explaining why" >&2; exit 1
    fi
    rev=$(resolve "$url" "$pinned") || rev=
  else
    follows=$release
    rev=$(resolve "$url" "refs/heads/$release" "refs/tags/$release") || rev=
  fi
  [ -n "$rev" ] || { echo "$name: no $follows in $url" >&2; exit 1; }

  if [ "$rev" = "$oldrev" ] && [ -n "$oldhash" ]; then
    printf '%-18s %.10s  (unchanged, %s)\n' "$name" "$rev" "$follows"
    continue
  fi

  hash=$(nix-prefetch-git --quiet --url "$url" --rev "$rev" | jq -r .hash)
  printf '%-18s %.10s -> %.10s  (%s)\n' "$name" "$oldrev" "$rev" "$follows"
  jq --arg n "$name" --arg rev "$rev" --arg hash "$hash" \
    '.extensions[$n].rev = $rev | .extensions[$n].hash = $hash' "$new" > "$new.tmp"
  mv "$new.tmp" "$new"
done

cp "$new" "$pins"
