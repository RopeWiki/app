# The old process reviewed, step by step

Part of the Nix migration; see [TODO](../TODO.md) for the checklist.

"Needed?" = whether the *goal* of the step still exists once the data lives on btrfs, secrets are
files, and deploys are `nixos-rebuild`. Where the answer is no, the step is dropped, not ported.

## `smw_upgrade_process.md` (SMW 2.5.8 -> 3.0.2, offline)

| Old step | Needed? | Becomes |
|---|---|---|
| Create `UpgradeTest` page, to tell snapshots apart | Goal yes | Snapshot names carry the generation and time; the restore drill and smoke test check real invariants |
| Confirm `ropewiki.com` is on `master` | Goal yes | The running system *is* a git revision (`codebase_version.html` shows `self.rev`) |
| Maintenance banner in `Common.js` | No | `$wgReadOnlyFile` message (above) |
| Disable edits via 3 lines in `LocalSettings.php` | No | Same; no code edit and redeploy to freeze the wiki |
| `runJobs.php` before backing up | Partly | Job service keeps the queue short; draining before the pre-upgrade snapshot is optional |
| Production backup, copy locally, restore on dev | No | Instant snapshot, rehearsal on a clone |
| Check out branch, redeploy | Yes | `nixos-rebuild switch` |
| Delete `.smw.json` | No | Was for the 2.5 -> 3.0 file format change. State file lives in `stateDir/smw`; SMW rewrites it from `update.php` |
| `setupStore.php` | No | `update.php` does it (SMW hooks into it; release notes say either one) |
| `populateHashField.php` (68 min) | No | Only the 2.x -> 3.x jump; check each new release's "Upgrading" notes |
| `rebuildData.php` (19 h) | Only if release notes say so | Background unit on the live site |
| `runJobs.php --procs 8` | Yes | Background job service |
| `UpgradeComplete` page, back up dev, **copy the DB to production**, restore, redeploy | No | Upgrade production in place; the pre-upgrade snapshot is the undo |

## The Docker/manual deployment, `deploy_tool.py` and `playbooks/deployment.md`

| Old step | Becomes |
|---|---|
| `ufw` rules, SSH to containers on 22001/22002, debug port 8080 | `networking.firewall` (`openFirewall`); the container SSH ports have no equivalent and are not needed |
| Install Docker, git; clone the repo into `/rw` | None: the flake is the deployment |
| `site_configs/*.json` (hostname, protocol, folders, robots) | A NixOS host configuration per site (`hostName`, `robots`, and the TLS settings of `services.nginx.virtualHosts.<hostName>`) |
| `~/rw_passwords.sh` exports (`WG_DB_PASSWORD`, `RW_ROOT_DB_PASSWORD`, SMTP) | Secret files (agenix/sops-nix). A local DB needs no password at all: unix-socket auth, which also removes the whole "password in the restored DB does not match `WG_DB_PASSWORD`" class of failures from the Troubleshooting wiki page |
| `create_db` (stop, `docker volume rm`, create DB and user, grants) | `services.mysql.ensureDatabases/ensureUsers` |
| `restore_db`, `restore_empty_db` | `ropewiki-restore` (Backups, step 5) and `database.loadEmptySchema` (exists) |
| `get_sql_backup_legacy`, `get_images_legacy` (rsync from `db01.ropewiki.com`, `ropewiki.com`) | One-time cutover only (below), then deleted |
| `start_site`, `redeploy <service>`, `dc ...`, "tear down with `down -v`" recovery | `nixos-rebuild`; `systemctl restart`. Nothing to reset |
| `enable_tls`, `renew_certs`, `add_cert_cronjob` (certbot in the proxy container) | `services.nginx.virtualHosts.<hostName>.{enableACME,forceSSL}` with NixOS' `security.acme` (plain NixOS, no module code) |
| `publish.sh`: tag and push five images, then create a git tag by hand | The flake revision and NixOS generations; tag releases in git only |
| `.github/workflows/test-empty-site.yml` (build five images, restore empty schema, `curl`, push to ghcr) | `nix flake check` in CI, plus a binary cache so VM tests are not rebuilt every time |
| `rw_helpers.sh` (`denter`, `dexec`, `dbquery`, `rwusers`, `findinpage`) | Their goals port to a small `ropewiki-sql` wrapper (`sudo -u mediawiki mariadb mediawiki`) plus the existing `ropewiki-maintenance`; `docker exec` plumbing is gone |
| "Exploring the system", docker logs, dangling volumes | `journalctl -u ...`, `/var/log/nginx`; no dangling volumes |

# One-time cutover from Docker

Not an ongoing process, but it needs a checklist, and parts of it can be rehearsed with the VM today:

1. Provision the host: btrfs subvolume layout, NixOS config with `services.ropewiki`, DNS pointing at it (ACME needs it).
2. Restore the latest SQL backup with `--one-database ropewiki`, into a database called `mediawiki`
   (see docs/backups.md for the rename). **Verify first** that a real
   MySQL 5.7 dump loads cleanly into MariaDB 11.4 (charset `utf8`, `varbinary` columns, `_binary`
   literals); if it does not, MySQL 8.4 (`mysql84` is in nixpkgs) is the fallback.
3. `rsync` the images (18+ GB) into `imagesDir`; for a short freeze use `$wgReadOnlyFile` on the old
   site while the final incremental rsync and dump are taken.
4. First start runs `update.php`. Sessions are already in the database (#196), so users stay logged in.
5. `secretKeyFile`: the Dockerfile bakes a **default `WG_SECRET_KEY` and `WG_UPGRADE_KEY` into the
   public repo**. Check what production actually runs with; if it is the default, generate a new one
   (this invalidates password-reset links only) rather than carrying it over.
6. Compare old and new (a few hundred URLs, an `#ask` result, search, a PDF export through the Luca
   path) before switching DNS. Keep the old stack warm for a rollback window.
