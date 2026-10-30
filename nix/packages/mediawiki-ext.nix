# Everything that is fetched from upstream and pinned for the site, from ./mediawiki-pins.json:
#
#   mediawiki      the MediaWiki core tarball: `version` (edit this by hand) and its `hash`
#   extensions     the extensions webserver/Dockerfile `git clone`s: url, resolved `rev` and `hash`,
#                  plus an optional `ref`
#
# Without a `ref` an extension tracks the release branch of the MediaWiki version
# (REL1_39 for 1.39.x), or a tag of that name when upstream only has a tag (UserMerge).
# `"ref": "HEAD"` is the exception and must carry a `note` saying why (Variables, SemanticRating).
#
#   pkgs.mediawikiExtensions.mediawiki.src         the core tarball (fetchurl)
#   pkgs.mediawikiExtensions.sources.PageForms     one extension (fetchgit)
#   pkgs.mediawikiExtensions                       all extensions, as a directory of symlinks
#
# To move to another MediaWiki release: set `mediawiki.version` in the JSON, then
#
#   nix run .#update-mediawiki-ext               # core hash + every extension rev/hash
#   nix run .#update-mediawiki-ext -- PageForms  # only some (`mediawiki` selects the core)
#
# which is the `passthru.updateScript` of this package. Nothing is written unless everything
# selected resolved and prefetched, so the pins never end up half-updated. The patches under
# webserver/html/ropewiki/extensions/*/*.REL1_39.patch are per release and still have to be
# checked by hand (the build fails when one no longer applies).
{
  lib,
  fetchurl,
  fetchgit,
  linkFarm,
  writeShellApplication,
  coreutils,
  git,
  jq,
  nix,
  nix-prefetch-git,
}:

let
  pins = builtins.fromJSON (builtins.readFile ./mediawiki-pins.json);

  mediawiki = {
    inherit (pins.mediawiki) version;
    src =
      assert lib.assertMsg (
        pins.mediawiki.hash != ""
      ) "mediawiki-pins.json: mediawiki has no hash yet; run `nix run .#update-mediawiki-ext`.";
      fetchurl {
        url = "https://releases.wikimedia.org/mediawiki/${lib.versions.majorMinor pins.mediawiki.version}/mediawiki-${pins.mediawiki.version}.tar.gz";
        inherit (pins.mediawiki) hash;
      };
  };

  sources = lib.mapAttrs (
    name: pin:
    assert lib.assertMsg (
      pin.hash != ""
    ) ''mediawiki-pins.json: "${name}" has no hash yet; run `nix run .#update-mediawiki-ext`.'';
    fetchgit {
      name = "mediawiki-extension-${name}";
      inherit (pin) url rev hash;
    }
  ) pins.extensions;

  updateScript = writeShellApplication {
    name = "update-mediawiki-ext";
    runtimeInputs = [
      coreutils
      git
      jq
      nix
      nix-prefetch-git
    ];
    text = builtins.readFile ./update-mediawiki-ext.sh;
  };
in
(linkFarm "mediawiki-extensions" (lib.mapAttrsToList (name: path: { inherit name path; }) sources))
.overrideAttrs
  (old: {
    passthru = (old.passthru or { }) // {
      inherit
        mediawiki
        sources
        pins
        updateScript
        ;
    };
  })
