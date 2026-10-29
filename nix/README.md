# Nix packaging

`flake.nix` packages the site and provides a NixOS module, `services.ropewiki`, to run it.
Docker (`docker-compose.yaml`, `deploy_tool.py`) keeps working; nothing here changes it.

```nix
# in a NixOS configuration
{
  imports = [ ropewiki.nixosModules.default ];

  services.ropewiki = {
    enable = true;
    hostName = "ropewiki.com";
    robots = "prod";
    openFirewall = true;
  };

  # TLS, firewall, mail, ... are ordinary NixOS settings:
  services.nginx.virtualHosts."ropewiki.com" = {
    enableACME = true;
    forceSSL = true;
  };
  security.acme = { acceptTerms = true; defaults.email = "admin@ropewiki.com"; };
}
```

That gives nginx + php-fpm 8.3, MariaDB (unix-socket auth, no passwords), Sphinx search and a
database migration (`update.php`) on every start. MediaWiki is run by nixpkgs' `services.mediawiki`
module (`webserver = "none"`: its `/w/` URLs are not RopeWiki's, so the nginx virtual host is
ours), which also names the user, group and database `mediawiki`, keeps state in
`/var/lib/mediawiki` and calls the units `mediawiki-init` and `phpfpm-mediawiki`. Restore a backup
into the `mediawiki` database (a dump from the Docker site says `USE ropewiki`; see `docs/backups.md`).
The module's own `mediawiki-*` maintenance commands do not work with MediaWiki 1.39; use
`ropewiki-maintenance` below.
The scheme of the site's URLs follows the nginx virtual host (https when it has `forceSSL`,
`addSSL` or `onlySSL`). `mode = "development"` prints PHP errors into the page like the Docker
setup did; the default, `production`, hides errors and what is running. Maintenance scripts, core and extensions:
`ropewiki-maintenance update.php --quick`, `ropewiki-maintenance rebuildData.php`. To load pages
exported from the live site (Special:Export with "Include templates"): `ropewiki-import export.xml`
(runs `importDump.php`, `rebuildData.php`, `runJobs.php`).

On a real host with btrfs, `services.ropewiki.backup.enable = true` adds hourly snapshots of
`services.ropewiki.backup.subvolumes` (default `[ "/" ]`), a daily SQL export, and a check that
refuses a `nixos-rebuild switch` (or `test`/`boot`) unless a backup finished within the last hour. It is off by
default and the development VM does not use it; see `docs/backups.md`.

The site's JavaScript and CSS are wiki pages (`MediaWiki:Common.js`, `Common.css` and its
`Common-NN-*.css` modules, `Waterflow.js`), built from the
[commonjs](https://github.com/RopeWiki/commonjs) and [commoncss](https://github.com/RopeWiki/commoncss)
repositories, which are flake inputs. `ropewiki-pages.service` writes them into the wiki on every
start (what those repositories' `upload.py` scripts do over the API), so a fresh site is styled and
a switch to a new version publishes it. Take new versions with
`nix flake update commonjs commoncss`. Pages edited by hand are overwritten; pages the build does
not know about (`MediaWiki:Common*`) are reported in the journal and left alone.
`services.ropewiki.sitePages = null` turns this off.

`services.ropewiki.drainage.enable = true` serves the "~N mi²" drainage area on canyon pages
(`/luca/rwr?waterflow=winfo=`, which the Luca server used to answer) from NHDPlus; the first start
downloads 7.8 GB to build its index. See `docs/drainage.md`.

`services.ropewiki.imageProxy = "https://ropewiki.com"` (development) shows that site's uploaded
files instead of this one's, which has none. It is off in `nix run .#vm` until validated. See `docs/image-proxy.md`.

| Command | What it does |
|---|---|
| `nix build .#ropewiki` | the site tree: MediaWiki 1.39 + extensions + this repo's overlay and patches |
| `nix run .#vm` | boots a VM running the site: https://localhost:8443 (self-signed), http://localhost:8080; wiki login `Admin` / `admin` (sysop, bureaucrat; the VM drops MediaWiki's password policy), console login `root` / `root` |
| `nix build .#image` | the same machine as a bootable qcow2 disk image |
| `nix build .#checks.x86_64-linux.ropewiki` | VM test: empty site renders, extensions load, HTTPS, production hardening, Sphinx stays up, the JavaScript and CSS pages are published |
| `nix build .#checks.x86_64-linux.import` | VM test: `ropewiki-import` loads Special:Export files; a made-up fixture and a real page (Lytle Creek) render with their templates and properties |
| `nix build .#checks.x86_64-linux.backup` | VM test on a real btrfs disk: snapshots, retention, export, upgrade gate |
| `nix build .#checks.x86_64-linux.nocow` | VM test: on btrfs, MariaDB's data directory and files are NOCOW |
| `nix build .#checks.x86_64-linux.image-proxy` | VM test (two VMs): `imageProxy` links files and thumbnails to another site and fetches hard-coded `/images/` paths from it, read-only, with the name looked up at start or per request |
| `nix build .#checks.x86_64-linux.drainage` | VM test: the drainage-area lookup behind nginx (`/luca/rwr?waterflow=winfo=`), loopback only, starts when its index appears |
| `nix build .#checks.x86_64-linux.drainage-index` | VM test: downloads, extracts and indexes a made-up NHDPlus archive, rebuilds on demand |
| `nix build .#rw-drainage` | the drainage lookup program; building it runs its unit tests |
| `nix build .#site-pages` | the JavaScript and CSS pages, one file per page title |
| `nix run .#update-mediawiki-ext` | re-pin MediaWiki core and every git-cloned extension |

Every file in `tests/` is a NixOS VM test and becomes a check automatically.

## Layout

- `packages/ropewiki.nix` assembles the tree the way `webserver/Dockerfile` does, laid out as nixpkgs'
  `mediawiki` is (`share/mediawiki`) so `services.mediawiki` can run it.
- `packages/mediawiki-pins.json`, `mediawiki-ext.nix`, `update-mediawiki-ext.sh`: the pinned
  MediaWiki version, tarball hash and extension revisions, and the script that updates them.
  **To change MediaWiki versions, edit `mediawiki.version` in the JSON and run the updater**; the
  per-release `*.REL1_39.patch` files still need checking by hand.
- `packages/composer-vendor.nix` + `composer/core/composer.lock`: SMW, Maps, SRF (what the
  Dockerfile's `composer require` installs). Regenerate the lock with `nix develop`, then fix
  the `outputHash`.
- `packages/site-pages.nix`: builds the `MediaWiki:` JavaScript and CSS pages from the `commonjs`
  and `commoncss` flake inputs.
- `packages/rw-drainage.nix` + `packages/rw-drainage/`: the drainage lookup (Python, GDAL to build),
  its tests and fixtures; `packages/site-pages-drainage.patch` and `site-pages-luca-host.patch` are the
  changes to commonjs it needs.
- `modules/ropewiki.nix`: the NixOS module, a layer over `services.mediawiki`. `modules/drainage.nix`: the opt-in drainage service.
  `modules/backup.nix`: the opt-in backup service and
  upgrade gate (its scripts are plain `.sh` files in `modules/backup/`). `php/production.php`: what `mode = "production"` adds.
- `vm/`, `tests/`: the VM definition, `dev-site.nix` (MediaWiki's installer on first start + self-signed cert for VMs
  and tests; deliberately not part of the module) and the VM tests.
- `docs/`: design notes (backups, upgrades, real-data upgrade tests, the old Docker process, the
  Luca server). `TODO.md` is the checklist.

Flakes only see git-tracked files, so `git add` new files before building.
