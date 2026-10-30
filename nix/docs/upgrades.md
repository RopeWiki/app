# Upgrades

See [TODO](../TODO.md) for the checklist.

## What the Docker setup does

Sources: [smw_upgrade_process.md](smw_upgrade_process.md) (the SMW offline runbook), the git
history (`PHP 5.6 -> 7.1`, `MW 1.27 -> 1.31 -> 1.35 -> 1.39`, `SMW 2.1 -> 2.5.8 -> 3.0.2 -> 3.2.3 -> 4.2.0`;
each one a PR that edits the Dockerfile and patches), `playbooks/deployment.md`.

The SMW runbook is an **offline upgrade done on a copy**: freeze edits (a banner in
`MediaWiki:Common.js` and three `$wgGroupPermissions[...]['edit'] = false` lines), drain jobs, back up
production, restore on the dev server, deploy the new code there, delete `.smw.json`, run
`setupStore.php`, `populateHashField.php` (68 min), `rebuildData.php` (about 19 hours), `runJobs.php`,
then back up the *dev* database, copy it **back to production** and redeploy. Editing is frozen for
the whole window, because anything written on production meanwhile would be overwritten.

Day to day, `redeploy webserver` rebuilds the image and recreates the container. **Nothing in that
flow runs `update.php`**; it is a manual step for MediaWiki core upgrades.

## Built

- **Production updates itself from a flake reference**: `system.autoUpgrade.flake = "<flake-ref url>"`
  (for example a `production` branch or tag, so merging to `master` does not deploy by itself).
  nixpkgs runs `nixos-rebuild <operation> --refresh --flake <ref>` from `nixos-upgrade.service`.
  The unit has `restartIfChanged = false`, so an upgrade does not restart itself half way through.
- **The upgrade refuses to run without a fresh backup** (opt-in with `services.ropewiki.backup.enable`,
  see [backups.md](backups.md); tested by running the real pre-switch script).
  - `system.preSwitchChecks.ropewiki-backup-fresh` is a read-only gate: it reads
    `/var/lib/ropewiki-backup/last-success` and aborts unless that stamp is less than an hour old
    *and* names a snapshot that still exists. `switch`, `test` and `boot` are gated (a `boot` upgrade
    migrates the database on the next boot); `dry-activate` changes nothing and is not.
    `NIXOS_NO_CHECK=1` skips all pre-switch checks, the deliberate emergency bypass.
  - `nixos-upgrade.service` is ordered after `ropewiki-backup.service` and wants it, so an automatic
    upgrade starts a backup first. The gate still decides: if a slow build makes the stamp older than
    an hour, the switch is refused and the next timer run starts a backup again, with the build cached.
  - Caveat: `switch-to-configuration` of the *new* generation runs its own `preSwitchChecks`, so the
    first generation that contains the gate cannot be protected by it. Deploy that one by hand.
- **Dev shows errors, production does not** (`services.ropewiki.mode`, default `production`).
  Production sets `display_errors` off, logs to the journal, sends no `X-Powered-By` or generator tag,
  shows no "Powered by" icons, restricts `Special:Version` to logged-in users, moves the tarball's
  release notes out of the web root, answers 404 for `extension.json`/`skin.json`/`composer.*` and
  the code directories, and lets only MediaWiki's PHP entry points plus `kml_to_gpx.php` execute.
  `development` (the VM) prints errors into the page like the Docker setup. Still open: HSTS (decide
  once TLS is proven on the real domain), and the version that `api.php?action=query&meta=siteinfo` reports.
- **The change itself:** set `mediawiki.version` in `packages/mediawiki-pins.json` and run
  `nix run .#update-mediawiki-ext`, then `nix run .#update-composer`. The per-release patches are
  adapted by hand; the build fails if one no longer applies.
- **Migration:** `mediawiki-init` runs `update.php --quick` on every start. For SMW 4.x that is the
  whole job: its 4.2.0 release notes say "You need to run either update.php or setupStore.php. Apart
  from that, no other script needs to be run", and 4.0.0 says no rebuild is needed either.

## Not built yet

The goal: an upgrade is a reviewed git change that is rehearsed in CI, deployed in place, migrates
by itself, can be undone, and never needs a day of read-only time.

- **Rehearse** in CI with `nix flake check` plus the [real-data upgrade test](real-data-upgrade-tests.md);
  for a major step, also on a *clone of the latest production snapshot* to measure the time. The
  update script could print the "Upgrading" sections of the new SMW/MediaWiki release notes.
- **Keep the rollback point:** when a generation changes MediaWiki/SMW/extension versions, mark the
  stamp's snapshot `pre-upgrade-<generation>` so retention does not expire it.
- **Maintenance page:** while migrating, nginx answers `503` with a static page (`error_page` on the
  missing php-fpm socket).
- **Smoke test after migrating** (`Main_Page`, `siteinfo`, one `#ask`, one search); a failure fails the unit.
- **Job queue:** `ropewiki-jobs.service` draining `runJobs.php` in the background. Nothing configures
  a job runner yet, so MediaWiki runs jobs inside web requests.
- **Rollback is two commands:** `nixos-rebuild switch --rollback` returns the *code*, but `update.php`
  has already changed the *schema*, so also restore the `pre-upgrade-<generation>` snapshot. A
  downgrade guard (the module records the highest applied version in `stateDir`, and `mediawiki-init`
  refuses to run older code against it unless told to) would stop an old generation booting against
  a migrated database by accident.
- **Maintenance mode without redeploying:** MediaWiki's `$wgReadOnlyFile` (checked in 1.39
  `MainConfigSchema.php`) makes the wiki read-only, showing the file's contents, while the file
  exists. Point it at `stateDir/readonly` and add a `ropewiki-readonly on "message"` / `off` helper.
  That replaces the `LocalSettings.php` edit and the `Common.js` banner.
- **Long data rebuilds on the live site**, if a release ever needs them (`rebuildData.php` and
  `populateHashField.php` were needed to cross SMW 2.5.8 -> 3.0.2, not for 3.x -> 4.2): a
  low-priority systemd unit (`Nice=`, `IOSchedulingClass=idle`) beside the working wiki, never a step
  that holds the deploy.

Open questions: how long the maintenance page may be up for a major upgrade before read-only mode
is preferred; whether a failed smoke test should roll back automatically (code only is easy, the
schema needs the snapshot, so probably alert-and-stop first).
