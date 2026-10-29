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
database migration (`update.php`) on every start. Restore a backup into the `ropewiki` database.
The scheme of the site's URLs follows the nginx virtual host (https when it has `forceSSL`,
`addSSL` or `onlySSL`). `mode = "development"` prints PHP errors into the page like the Docker
setup did; the default, `production`, hides errors and what is running. Maintenance scripts:
`ropewiki-maintenance update.php --quick`.

On a real host with btrfs, `services.ropewiki.backup.enable = true` adds hourly snapshots of
`services.ropewiki.backup.subvolumes` (default `[ "/" ]`), a daily SQL export, and a check that
refuses a `nixos-rebuild switch` (or `test`/`boot`) unless a backup finished within the last hour. It is off by
default and the development VM does not use it; see `docs/backups.md`.

| Command | What it does |
|---|---|
| `nix build .#ropewiki` | the site tree: MediaWiki 1.39 + extensions + this repo's overlay and patches |
| `nix run .#vm` | boots a VM running the site: https://localhost:8443 (self-signed), http://localhost:8080 |
| `nix build .#image` | the same machine as a bootable qcow2 disk image |
| `nix build .#checks.x86_64-linux.ropewiki` | VM test: empty site renders, extensions load, HTTPS, production hardening, Sphinx stays up |
| `nix build .#checks.x86_64-linux.backup` | VM test on a real btrfs disk: snapshots, retention, export, upgrade gate |
| `nix build .#checks.x86_64-linux.nocow` | VM test: on btrfs, MariaDB's data directory and files are NOCOW |
| `nix run .#update-mediawiki-ext` | re-pin MediaWiki core and every git-cloned extension |

Every file in `tests/` is a NixOS VM test and becomes a check automatically.

## Layout

- `packages/ropewiki.nix` assembles the tree the way `webserver/Dockerfile` does.
- `packages/mediawiki-pins.json`, `mediawiki-ext.nix`, `update-mediawiki-ext.sh`: the pinned
  MediaWiki version, tarball hash and extension revisions, and the script that updates them.
  **To change MediaWiki versions, edit `mediawiki.version` in the JSON and run the updater**; the
  per-release `*.REL1_39.patch` files still need checking by hand.
- `packages/composer-vendor.nix` + `composer/core/composer.lock`: SMW, Maps, SRF (what the
  Dockerfile's `composer require` installs). Regenerate the lock with `nix develop`, then fix
  the `outputHash`.
- `modules/ropewiki.nix`: the NixOS module. `modules/backup.nix`: the opt-in backup service and
  upgrade gate (its scripts are plain `.sh` files in `modules/backup/`). `php/production.php`: what `mode = "production"` adds.
- `vm/`, `tests/`: the VM definition, `dev-site.nix` (empty schema + self-signed cert for VMs
  and tests; deliberately not part of the module) and the VM tests.
- `docs/`: design notes (backups, upgrades, real-data upgrade tests, the old Docker process, the
  Luca server). `TODO.md` is the checklist.

Flakes only see git-tracked files, so `git add` new files before building.
