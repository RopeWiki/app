# Upgrades

## Changing versions

Set `mediawiki.version` in `packages/mediawiki-pins.json` and run `nix run .#update-mediawiki-ext`
(re-pins core and the git-cloned extensions), then `nix run .#update-composer` (see the README).
The per-release patches are adapted by hand; the build fails if one no longer applies.

## Migration

`mediawiki-init` runs `update.php --quick` on every start. For SMW 4.x that is the whole job: its
4.2.0 release notes say "You need to run either update.php or setupStore.php. Apart from that, no
other script needs to be run", and 4.0.0 says no rebuild is needed either.

## Updating from a flake reference

Production can update itself with `system.autoUpgrade.flake = "<flake-ref url>"` (for example a
`production` branch or tag, so merging to `master` does not deploy by itself). nixpkgs runs
`nixos-rebuild <operation> --refresh --flake <ref>` from `nixos-upgrade.service`, which has
`restartIfChanged = false`, so an upgrade does not restart itself half way through.

## The backup gate

With `services.ropewiki.backup.enable` (see [backups.md](backups.md)) an upgrade refuses to run
without a fresh backup; this is tested by running the real pre-switch script.

- `system.preSwitchChecks.ropewiki-backup-fresh` is a read-only gate: it reads
  `/var/lib/ropewiki-backup/last-success` and aborts unless that stamp is less than an hour old
  *and* names a snapshot that still exists. `switch`, `test` and `boot` are gated (a `boot` upgrade
  migrates the database on the next boot); `dry-activate` changes nothing and is not.
  `NIXOS_NO_CHECK=1` skips all pre-switch checks, the deliberate emergency bypass.
- `nixos-upgrade.service` is ordered after `ropewiki-backup.service` and wants it, so an automatic
  upgrade starts a backup first. The gate still decides: if a slow build makes the stamp older than
  an hour, the switch is refused and the next timer run starts a backup again, with the build cached.
- `switch-to-configuration` of the *new* generation runs its own `preSwitchChecks`, so the first
  generation that contains the gate cannot be protected by it. Deploy that one by hand.

## Dev and production mode

`services.ropewiki.mode` defaults to `production`: `display_errors` off and logs in the journal, no
`X-Powered-By` or generator tag, no "Powered by" icons, `Special:Version` only for logged-in users,
the tarball's release notes moved out of the web root, 404 for `extension.json`/`skin.json`/
`composer.*` and the code directories, and only MediaWiki's PHP entry points plus `kml_to_gpx.php`
can execute. `development` (the VM) prints errors into the page like the Docker setup. Neither mode
sends HSTS, and `api.php?action=query&meta=siteinfo` still reports the MediaWiki version.
