# Upgrades

Part of the Nix migration; see [TODO](../TODO.md) for the checklist.

## What exists today

Sources: `smw_upgrade_process.md` (the SMW offline runbook), the git history
(`PHP 5.6 -> 7.1`, `MW 1.27 -> 1.31 -> 1.35 -> 1.39`, `SMW 2.1 -> 2.5.8 -> 3.0.2 -> 3.2.3 -> 4.2.0`;
each one a PR that edits the Dockerfile and patches), `playbooks/deployment.md`, and the GitHub wiki
pages Maintenance/Troubleshooting (being migrated into the repo; issues #200 and #201).

The SMW runbook is an **offline upgrade done on a copy**: freeze edits (a maintenance banner in
`MediaWiki:Common.js` and three `$wgGroupPermissions[...]['edit'] = false` lines in
`LocalSettings.php`), drain jobs, back up production, restore on the dev server, deploy the new
code there, delete `.smw.json`, run `setupStore.php` (minutes), `populateHashField.php` (68 min),
`rebuildData.php` (about 19 hours; the runbook itself notes it "can be deferred ... run in the
background of production"), `runJobs.php`, then back up the *dev* database, copy it **back to
production**, restore, redeploy. Canary pages (`UpgradeTest`, `UpgradeComplete`) prove which
database snapshot is which. Editing was frozen for the whole window, because anything written
on production meanwhile would be overwritten by the restore.

Day to day, `redeploy webserver` rebuilds the image and recreates the container. **Nothing in
that flow runs `update.php`**; it is a manual step for MediaWiki core upgrades.

## Decisions so far

- **Production updates itself from a flake reference**: `system.autoUpgrade.flake = "<flake-ref url>"`
  (for example a `production` branch or tag, so merging to `master` does not deploy by itself).
  nixpkgs runs `nixos-rebuild <operation> --refresh --flake <ref>` from `nixos-upgrade.service`, on
  `system.autoUpgrade.dates`, with `randomizedDelaySec`, `persistent`, `operation = "switch"` and
  `allowReboot = false`. The unit has `restartIfChanged = false`, so an upgrade does not restart
  itself half way through.
- **The upgrade never takes the backup; it refuses to run without a fresh one.** *Built* (opt-in
  with `services.ropewiki.backup.enable`, see [backups.md](backups.md)); the gate is tested by
  running the real pre-switch script. `NIXOS_NO_CHECK=1` skips all pre-switch checks, which is the
  deliberate emergency bypass. `switch`, `test` and `boot` are all gated (a `boot` upgrade
  migrates the database on the next boot); `dry-activate` changes nothing and is not.
  - `nixos-upgrade.service` gets `wants`/`after = [ "ropewiki-backup.service" ]` so a backup is
    started first.
  - `system.preSwitchChecks.ropewiki-backup-fresh` is a **read-only gate**, not an action: it
    reads `/var/lib/ropewiki-backup/last-success` and aborts the switch unless that stamp is less
    than one hour old *and* names a snapshot that still exists. No snapshots, no exports, no
    network in there. nixpkgs documents the contract: the script gets the new system path and the
    action as `$1`/`$2`, and a non-zero exit stops the switch before anything changes.
  - A slow build can make the stamp older than an hour by the time the switch is reached. That is
    fine and self-healing: the switch is refused, the next run of the timer starts the backup again,
    and the second build is already cached.
  - Caveat: `switch-to-configuration` of the *new* generation runs its own `preSwitchChecks`, so
    the first generation that contains the gate cannot be protected by it. Deploy that one by hand.
- **Dev shows errors, production does not.** Done: `services.ropewiki.mode` (default `production`).
  Production sets `display_errors` off and logs to the journal, no exception or SQL details, no
  `X-Powered-By`, no MediaWiki generator tag, no "Powered by" footer icons, `Special:Version` only
  for logged-in users, the tarball's release notes/README/FAQ moved out of the web root,
  `extension.json`/`skin.json`/`composer.*` and the code directories answer 404, and only
  MediaWiki's own PHP entry points plus `kml_to_gpx.php` can execute. `development` (used by the VM
  from `nix run .#vm`) prints errors and deprecations into the page like the Docker setup.
  Still open: HSTS (decide once TLS is proven on the real domain), `codebase_version.html`
  (it shows the git commit, log and status to everyone, as the Docker setup does), and the version
  that `api.php?action=query&meta=siteinfo` reports.

## Ideal implementation

**Goal:** an upgrade is a reviewed git change that is rehearsed in CI, deployed in place, migrates by
itself, can be undone, and never requires a day of read-only time.

**1. Make the change (offline, in git).** `nix run .#update-mediawiki-ext` after setting the
MediaWiki version (already built). The same pass should print the "Upgrading" section of the new
SMW/MediaWiki release notes, so a human reads exactly what the project says is required. Adapt the
per-release patches by hand; the build fails if one no longer applies. Merge to `master`, then
promote the tested revision to the branch/tag production follows.

**2. Rehearse before production.** CI runs `nix flake check`: the VM tests in `nix/tests/`,
plus the [real-data upgrade test](real-data-upgrade-tests.md). For a major step (new
MediaWiki or SMW generation) also run that on a *clone of the latest production snapshot* to
measure how long it takes. Cloning a snapshot is instant, so this replaces "back up, copy,
restore on dev".

**3. Deploy in place (`system.autoUpgrade`, or `nixos-rebuild switch` by hand).**
1. *Gate:* `preSwitchChecks` confirms a backup finished within the last hour (above). If the new
   generation changes MediaWiki/SMW/extension versions, the module additionally marks the stamp's
   snapshot as `pre-upgrade-<generation>` so retention does not expire the rollback point.
2. *While migrating*, nginx answers `503` with a static maintenance page (`error_page` on the
   missing php-fpm socket). Today's init already runs before php-fpm starts; only the page is new.
3. `ropewiki-init` runs `update.php --quick` (already in the module). For SMW 4.x this is the whole
   job: its own 4.2.0 release notes say "You need to run either update.php or setupStore.php. Apart from
   that, no other script needs to be run", and 4.0.0 says no rebuild is needed either.
4. A smoke test runs (`Main_Page`, `api.php?action=query&meta=siteinfo`, one `#ask`, one search). If it
   fails the unit fails and alerts.
5. *Job queue*: `ropewiki-jobs.service` drains `runJobs.php` in the background; the old
   `runJobs --nothrottle --procs 8` step stops being a blocker.

**4. Rollback is two commands, and it matters that it is both.** `nixos-rebuild switch --rollback`
returns the *code*, but `update.php` has already changed the *schema*, which a generation rollback
does not undo. So rolling back = switch to the old generation **and** restore the
`pre-upgrade-<generation>` snapshot (seconds). To stop someone booting an old generation against a
migrated database by accident, the module records the highest applied version in `stateDir`, and
`ropewiki-init` refuses to run older code against it unless told to (a downgrade guard).

**5. Maintenance mode without redeploying.** MediaWiki has a built-in `$wgReadOnlyFile` (verified
in 1.39 `MainConfigSchema.php`): when that file exists the wiki is read-only and shows the file's
contents as the message. The module should point it at `stateDir/readonly` and ship a
`ropewiki-readonly on "message"` / `off` helper. That replaces both the `LocalSettings.php` edit
and the `Common.js` banner, with no deploy and nothing to forget to revert.

**6. Long data rebuilds run on the live site, if a release ever needs them.** `rebuildData.php`
(19 h) and `populateHashField.php` (68 min) were needed to cross SMW 2.5.8 -> 3.0.2, not for
3.x -> 4.2. If a future release requires one, it runs as a low-priority systemd unit
(`Nice=`, `IOSchedulingClass=idle`, progress in the journal) beside the working wiki; SMW serves
stale-but-valid data until entities are refreshed (see SMW's "Outdated entities" help). Never as a
step that holds the deploy.

Open questions: how long the maintenance page may be up for a major upgrade before we prefer
read-only mode instead; whether a failed smoke test should roll back automatically (code only is
easy, the schema needs the snapshot, so probably alert-and-stop first).
