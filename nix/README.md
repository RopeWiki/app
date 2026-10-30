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
module (`webserver = "none"`: its `/w/` URLs are not RopeWiki's, so the nginx virtual host is ours),
which also names the user, group and database `mediawiki`, keeps state in `/var/lib/mediawiki` and
calls the units `mediawiki-init` and `phpfpm-mediawiki`. Restore a backup into the `mediawiki`
database (a dump from the Docker site says `USE ropewiki`; see `docs/backups.md`). The module's own
`mediawiki-*` maintenance commands do not work with MediaWiki 1.39; use `ropewiki-maintenance`.

- **Mode.** `mode = "development"` prints PHP errors into the page like the Docker setup did; the
  default, `production`, hides errors and what is running. The site's URL scheme follows the nginx
  virtual host (https with `forceSSL`, `addSSL` or `onlySSL`).
- **Commands.** `ropewiki-maintenance update.php --quick` runs a maintenance script (core or
  extension); `ropewiki-import export.xml` loads pages exported from the live site (Special:Export
  with "Include templates"); `ropewiki-help` lists every command this machine has; `ropewiki-logs
  [nginx|php|db|search|init|pages|nginx-access|all] [-f]` shows the logs. Modules add their own
  entries with `services.ropewiki.help.commands` and `services.ropewiki.help.logs`.
- **Backups** (`services.ropewiki.backup.enable`, btrfs hosts): hourly snapshots of
  `backup.subvolumes` (default `[ "/" ]`), a daily SQL export, and a check that refuses a
  `nixos-rebuild switch` (or `test`/`boot`) unless a backup finished within the last hour. Off by
  default and not used by the development VM; see `docs/backups.md`.
- **Site JavaScript and CSS** are wiki pages (`MediaWiki:Common.js`, `Common.css` and its modules,
  `Waterflow.js`) built from the [commonjs](https://github.com/RopeWiki/commonjs) and
  [commoncss](https://github.com/RopeWiki/commoncss) flake inputs. `ropewiki-pages.service` writes
  them into the wiki on every start (what those repositories' `upload.py` scripts do), so a fresh
  site is styled and a switch publishes new versions. Take new ones with
  `nix flake update commonjs commoncss`. Hand edits are overwritten; pages the build does not know
  about (`MediaWiki:Common*`) are reported in the journal and left alone.
  `services.ropewiki.sitePages = null` turns this off.
- **Drainage** (`services.ropewiki.drainage.enable`): the "~N mi²" badge on canyon pages
  (`/luca/rwr?waterflow=winfo=`, which the Luca server used to answer), from NHDPlus. The first
  start downloads 7.8 GB to build its index. See `docs/drainage.md`.
- **Tile server** (`services.ropewiki.tileserver.enable`): `maptiler/tileserver-gl` as a podman
  container on `tiles.<hostName>`, serving `<imagesDir>/tiles` (upstream RopeWiki/app#155). The tile
  data is not in this repository. See `docs/tileserver.md`.
- **Image proxy** (`services.ropewiki.imageProxy = "https://ropewiki.com"`, development): shows that
  site's uploaded files instead of this one's. Off in `nix run .#vm` until validated. See
  `docs/image-proxy.md`.

| Command | What it does |
|---|---|
| `nix build .#ropewiki` | the site tree: MediaWiki 1.39 + extensions + this repo's overlay and patches |
| `nix run .#vm` | a VM running the site: https://localhost:8443 (self-signed), http://localhost:8080; wiki login `Admin` / `admin` (sysop, bureaucrat; the VM drops MediaWiki's password policy), console login `root` / `root` |
| `nix build .#image` | the same machine as a bootable qcow2 disk image |
| `nix flake check` | every VM test: one check per file in `tests/`, each with a header saying what it covers (run one with `nix build .#checks.x86_64-linux.<name>`) |
| `nix build .#rw-drainage` | the drainage lookup program; building it runs its unit tests |
| `nix build .#site-pages` | the JavaScript and CSS pages, one file per page title |
| `nix run .#update-mediawiki-ext` | re-pin MediaWiki core and every git-cloned extension |
| `nix run .#update-composer` | regenerate `composer.json`, re-lock it and refresh the vendor hash |

## Layout

- `packages/ropewiki.nix` assembles the tree the way `webserver/Dockerfile` does, laid out as nixpkgs'
  `mediawiki` is (`share/mediawiki`) so `services.mediawiki` can run it.
- `packages/mediawiki-pins.json`, `mediawiki-ext.nix`, `update-mediawiki-ext.sh`: the pinned
  MediaWiki version, tarball hash and extension revisions, and the script that updates them.
  **To change MediaWiki versions, edit `mediawiki.version` in the JSON and run the updater**; the
  per-release `*.REL1_39.patch` files still need checking by hand.
- `packages/composer-vendor.nix` + `composer/core/composer.lock`: SMW, Maps, SRF (what the
  Dockerfile's `composer require` installs). `composer/core/composer.json` is generated
  (MediaWiki's own file plus our `composer require`s and settings). **After changing the packages
  or the MediaWiki or PHP version in `mediawiki-pins.json`, run `nix run .#update-composer`**: it
  regenerates `composer.json`, re-locks it and fixes the `outputHash`.
- `packages/site-pages.nix`: builds the `MediaWiki:` JavaScript and CSS pages from the `commonjs`
  and `commoncss` flake inputs.
- `packages/rw-drainage.nix` + `packages/rw-drainage/`: the drainage lookup (Python, GDAL to build),
  its tests and fixtures; `packages/site-pages-drainage.patch` and `site-pages-luca-host.patch` are the
  changes to commonjs it needs.
- `modules/ropewiki.nix`: the NixOS module, a layer over `services.mediawiki`. `modules/drainage.nix`: the opt-in drainage service.
  `modules/tileserver.nix`: the opt-in tile server container.
  `modules/backup.nix`: the opt-in backup service and
  upgrade gate (its scripts are plain `.sh` files in `modules/backup/`). `php/production.php`: what `mode = "production"` adds.
- `vm/`, `tests/`: the VM definition, `dev-site.nix` (MediaWiki's installer on first start + self-signed cert for VMs
  and tests; deliberately not part of the module) and the VM tests.
- `docs/`: design notes (backups, upgrades, real-data upgrade tests, the old Docker process, the
  Luca server and its drainage replacement, the tile server, image proxy mode, the SMW upgrade
  runbook). `TODO.md` is the checklist.

Flakes only see git-tracked files, so `git add` new files before building.
