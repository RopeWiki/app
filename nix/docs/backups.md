# Backups

`services.ropewiki.backup.enable` (opt-in; off by default and not used by the development VM; code
in `modules/backup.nix`, tested by `tests/backup.nix` on a real btrfs disk) runs:

- an hourly `ropewiki-backup.service`: a read-only snapshot of each subvolume in
  `services.ropewiki.backup.subvolumes` (default `[ "/" ]`) into `<subvolume>/.snapshots/`;
- retention: every snapshot for 24 hours, then the first of each UTC day for 30 days. It only ever
  deletes entries named exactly `ropewiki-<timestamp>`;
- one SQL export per UTC day (`mariadb-dump --single-transaction`, zstd, root-readable only) in
  `exportDir`, kept 30 days;
- the `last-success` stamp, written last, and `ropewiki-backup-fresh`, which reads it;
- `ropewiki-backup-monitor`, a unit that fails when the stamp is more than 2 hours old;
- the gate in front of upgrades: see [upgrades.md](upgrades.md).

The backup is a timer-driven service, never part of an upgrade; the upgrade only checks that one
recently succeeded.

The snapshots live on the same disk, so getting them off the machine is the cloud provider's job
(volume snapshots of the disk that holds the btrfs filesystem, which contain the btrfs snapshots
too). That setup needs a cross-region or cross-account copy and a vault lock the instance cannot
delete, since a compromised host must not be able to erase its backups.

The export is taken from the live database right after the snapshot, so it does not also prove that
the snapshot opens as a database. btrbk is not used: its retention can't be tested without time
travel, and ours is 15 lines of shell that the test exercises with a frozen clock.
`services.mysqlBackup` keeps no history (it overwrites one file per run).

## Loading a dump from the Docker site

The module's database is called `mediawiki` (the name `services.mediawiki` gives it). The Docker
site's dumps are `--all-databases` dumps of a database called `ropewiki`, so a plain restore would
replay the `mysql` system schema and the ``USE `ropewiki` `` lines. Rewrite the name on the way in
(``sed 's/`ropewiki`/`mediawiki`/'``) and load only that database (`mariadb --one-database mediawiki
mediawiki`). This has not been tried against a real production dump.
