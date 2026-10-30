# Backups

See [TODO](../TODO.md) for the checklist.

## Status

**Built, opt-in** (`services.ropewiki.backup.enable`; off by default and not used by the development
VM; code in `modules/backup.nix`, tested by `tests/backup.nix` on a real btrfs disk):

- an hourly `ropewiki-backup.service`: a read-only snapshot of each subvolume in
  `services.ropewiki.backup.subvolumes` (default `[ "/" ]`) into `<subvolume>/.snapshots/`;
- retention: every snapshot for 24 hours, then the first of each UTC day for 30 days. It only ever
  deletes entries named exactly `ropewiki-<timestamp>`;
- one SQL export per UTC day (`mariadb-dump --single-transaction`, zstd, root-readable only) in
  `exportDir`, kept 30 days;
- the `last-success` stamp, written last, and `ropewiki-backup-fresh`, which reads it;
- `ropewiki-backup-monitor`, a unit that fails when the stamp is more than 2 hours old;
- the gate in front of upgrades: see [upgrades.md](upgrades.md).

The export is taken from the live database right after the snapshot, so it does not also prove that
the snapshot opens as a database. btrbk is not used: its retention can't be tested without time
travel, and ours is 15 lines of shell that the test exercises with a frozen clock.
`services.mysqlBackup` is no use either: it overwrites one file per run and keeps no history.

## What the Docker setup does (and why it is not good enough)

Sources: `backup_manager/`, `deploy_tool.py` (`load_sql`, `restore_db`, `get_*_legacy`),
`playbooks/deployment.md`.

- A `backup_manager` container runs, daily at 10:00,
  `mysqldump --all-databases --add-drop-database --single-transaction | zstd -10` into
  `all-backup-<timestamp>.sql.zst`.
- **No retention**, **no monitoring** beyond a `last_success` file nobody reads, and the dump is
  **never test-restored**.
- The **uploads are not backed up at all**; people `rsync` them by hand over SSH. The database and
  the files are therefore never from the same moment. The database is 1.2+ GB, the images 18.3+ GB.
- Restore is `deploy_tool.py <site> restore_db`: a confirmation prompt, then
  `unzstd | mysql -uroot ... ropewiki`. Because the dump is `--all-databases`, a plain restore
  replays the `mysql` system schema and `CREATE DATABASE/USE` lines too; that is harmless into the
  same MySQL 5.7 but wrong into MariaDB. **To verify against a real backup.** Restoring with
  `--one-database` avoids it. The Nix module's database is called `mediawiki` (the name
  `services.mediawiki` gives it), so a dump that says ``USE `ropewiki` `` has to be rewritten on the
  way in (`sed 's/`ropewiki`/`mediawiki`/'`, then `--one-database mediawiki`).

## Decisions

- **Off-machine copies are the cloud provider's job**: volume snapshots (EBS via Data Lifecycle
  Manager / AWS Backup, or the equivalent) of the disk that holds the btrfs filesystem, so every
  provider snapshot also contains all the btrfs ones. The module does not ship snapshots anywhere.
  Requirements to put on that setup: cross-region (or at least cross-account) copy and a vault
  lock the instance cannot delete, since a compromised host must not be able to erase its backups.
- **Schedule:** hourly snapshots kept 24 hours; a daily SQL export plus one snapshot a day, kept 30 days.
- **The backup is a timer-driven service, never part of the upgrade.** The upgrade only checks that
  one recently succeeded.

## Not built yet

**One subvolume for all the data.** Database files, uploads and wiki state (secret key, SMW setup
file) should live in one btrfs subvolume, so a single atomic snapshot captures them at the same
instant with no downtime. It is crash-consistent: restoring it looks like a power loss, which
InnoDB recovers from. Exclude or regenerate the Sphinx indexes (rebuilt in about a minute) and the
cache directory. The one MyISAM table, `searchindex`, is unused and rebuildable.

**Export from a clone of the snapshot.** Daily: make a writable clone of the snapshot, start a
throwaway `mariadbd` on it (socket only) and dump from that, so the export matches the uploads
exactly and every run proves the snapshot opens as a database.

**Weekly restore drill** (`ropewiki-restore-test.service`): load the newest export into a scratch
MariaDB, run `update.php --quick` on it (proves the current code can still upgrade it) and check a
few invariants: page and revision counts near production, `Main_Page` renders, an SMW `#ask`
returns rows.

**Restore helper** (`ropewiki-restore`, keeping today's "Restore X? (y/n)" confirmation):
- *Roll back this machine:* stop the site, replace the data subvolume with a writable snapshot of
  the chosen one, start. Seconds. This is also the rollback for a failed upgrade.
- *New machine or different database version:* create the empty database, load the export (see the
  rename above), restore the uploads, start (the module runs `update.php`).
- *Lost disk:* create a volume from the provider's snapshot; the btrfs snapshots are inside it.

**Failure notifications** (`OnFailure=` on the backup service, and for a stale stamp). Needs a mail relay.

**A sanitized export for developers.** Developers get full production dumps today, which contain
user e-mail addresses, password hashes, tokens and the CheckUser IP tables. A
`ropewiki-export-sanitized` step (scrubbing `user`, `cu_*`, `recentchanges.rc_ip`, `ipblocks`,
e-mail fields and tokens) would be the artefact for dev VMs and CI fixtures, and the input to the
[real-data upgrade tests](real-data-upgrade-tests.md). Needs a decision from whoever owns the data.

Open questions: backup encryption and key holders (provider-side volume encryption may be enough);
whether the daily export should also go to an object store so a database can be recovered without
a volume restore.
