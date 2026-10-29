# Backups

Part of the Nix migration; see [TODO](../TODO.md) for the checklist.

## Status

**Built, opt-in** (`services.ropewiki.backup.enable`, off by default and not used by the development
VM; code in `nix/modules/backup.nix`, tested by `nix/tests/backup.nix` on a real btrfs disk):

- an hourly `ropewiki-backup.service`: a read-only snapshot of each subvolume in
  `services.ropewiki.backup.subvolumes` (default `[ "/" ]`) into `<subvolume>/.snapshots/`;
- retention: every snapshot for 24 hours, then the first of each UTC day for 30 days. It only ever
  deletes entries named exactly `ropewiki-<timestamp>`;
- one SQL export per UTC day (`mariadb-dump --single-transaction`, zstd, root-readable only) in
  `exportDir`, kept 30 days;
- the `last-success` stamp, written last, and `ropewiki-backup-fresh`, which reads it;
- `ropewiki-backup-monitor`, a unit that fails when the stamp is more than 2 hours old;
- the gate in front of upgrades: see [upgrades.md](upgrades.md).

**Differences from the ideal below:** the export is taken from the live database right after the
snapshot, not from a throwaway MariaDB on a clone of the snapshot, so it does not also prove that the
snapshot opens as a database. btrbk is not used (its retention can't be tested without time travel;
ours is 15 lines of shell that the test exercises with a frozen clock). Still to do: the restore
helper, the weekly restore drill, the sanitized export, notifications (needs a mail relay), and
`chattr +C`/layout measurements.

## What exists today (and why it is not good enough)

Sources: `backup_manager/` (Dockerfile, `backup.cron`, `scripts/backup_mysql.sh`, README),
`deploy_tool.py` (`load_sql`, `restore_db`, `get_*_legacy`), `playbooks/deployment.md`.

- A `backup_manager` container with cron and an SSH daemon runs, daily at 10:00,
  `mysqldump --all-databases --add-drop-database --single-transaction | zstd -10` into
  `all-backup-<timestamp>.sql.zst`. The root DB password is `sed`-ed into the script at start.
- **No retention** (nothing ever deletes old dumps), **no monitoring** beyond a `last_success`
  file nobody reads, and the dump is **not tested** by restoring it.
- The **uploads are not backed up at all**; the folder is only mounted read-only for people who
  `rsync` it by hand over SSH (port 22001, keys listed in `backup_manager/pubkeys/authorized_keys`).
  The database and the files are therefore never from the same moment: a page can reference a
  file that is not in the copy, or the other way round.
- Off-site copies exist only because someone with a key pulls them. Size, from the old wiki:
  the database is 1.2+ GB and the images 18.3+ GB.
- Restore is `deploy_tool.py <site> restore_db`: a confirmation prompt, then
  `unzstd | mysql -uroot ... ropewiki` inside the container. Because the dump is
  `--all-databases`, it also contains the `mysql` system schema (accounts and grants) and
  `CREATE DATABASE/USE` lines for every database. A plain `mysql ropewiki < dump` replays all of
  it. **To verify against a real backup**; it is harmless into the same MySQL 5.7 but wrong into
  MariaDB. The fix is `--one-database ropewiki` on restore (and dumping only that database).

## Decisions so far

- **Off-machine copies are the cloud provider's job**: volume snapshots (AWS EBS snapshots via
  Data Lifecycle Manager / AWS Backup, or the equivalent elsewhere) of the disk that holds the
  btrfs filesystem. The module therefore does *not* ship snapshots to a second host or to restic.
  Because the btrfs snapshots live on that same disk, every provider snapshot also contains all
  of them. Requirements to put on that setup: cross-region (or at least cross-account) copy and a
  vault-lock/retention the instance cannot delete, since a compromised host must not be able to
  erase its own backups.
- **Schedule and retention**
  - **Hourly** btrfs snapshots, kept **24 hours**.
  - **Daily** full database export (SQL, compressed), plus one daily snapshot, kept **30 days**.
- **What nixpkgs provides** (checked against the pinned nixpkgs):
  - `services.btrbk`: snapshot-only configs and retention policies. Retention maps directly onto the
    decision above: `snapshot_preserve_min = "24h"` (keep everything for a day) and
    `snapshot_preserve = "30d"` (then one per day for 30 days). Same shape as the module's own
    example (`"2d"` / `"14d"`). Confirm with `btrbk -n run`, a dry run, before relying on it.
  - `services.snapper`: also btrfs, "timeline" snapshots with hourly/daily limits. Works, but
    btrbk's retention syntax matches our policy more directly.
  - `services.sanoid`: ZFS only, so no use here.
  - `services.mysqlBackup`: **does not do retention.** It writes one `<database>.gz` (or `.zst`)
    and overwrites it every run, so it keeps no history. Not usable on its own for "30 days of
    exports". We write a small unit instead (below) and expire exports with
    `systemd-tmpfiles` (`e /srv/backups - - - 30d`).
- The backup is **a timer-driven service, never part of the upgrade**. The upgrade only *checks*
  that it recently succeeded (see [Upgrades](upgrades.md)).

## Ideal implementation

**Goal:** a backup that is (1) one consistent instant across database, uploads and wiki state,
(2) cheap enough to take hourly, (3) captured off the machine by the provider, (4) proven
restorable by an automatic test, and (5) needs no hand-run steps. Declared in the module
(`services.ropewiki.backup.*`) so a dev VM and production run the same code.

**1. One btrfs subvolume holds all the data.**

```
/srv/ropewiki            btrfs subvolume (the thing that is backed up)
  mysql/                 services.mysql.dataDir
  images/                services.ropewiki.imagesDir  (the uploads)
  state/                 services.ropewiki.stateDir   (secret key, SMW setup file)
/srv/.snapshots/         read-only snapshots of the above (btrbk)
/srv/backups/            daily SQL exports (outside the subvolume, own retention)
```

A single `btrfs subvolume snapshot -r /srv/ropewiki ...` is atomic, so the database files and
the uploads are captured at the *same instant* with no downtime and no global lock. The
snapshot is crash-consistent: restoring it looks like the machine lost power, which InnoDB (104
of the 105 tables in the empty schema) recovers from by design. *Exclude or regenerate*: the
Sphinx indexes (rebuilt in about a minute; move them out of `stateDir`) and the cache directory.
The one MyISAM table, `searchindex`, is unused (search is Sphinx) and rebuildable. **The MariaDB data directory is NOCOW** (done, in the module: a `systemd-tmpfiles` `h … +C` rule
on `services.mysql.dataDir`, tested on a real btrfs disk by `nix/tests/nocow.nix`; other
filesystems ignore it). On btrfs, copy-on-write makes database files slow, since every page write
allocates a new extent. The costs: NOCOW files have no btrfs checksums (so `btrfs scrub` can't catch
corruption in them; InnoDB's own page checksums still do) and no compression, and after each
snapshot the first write to a block is copied once, so very frequent snapshots eat part of the gain.
Still worth measuring on the real database.

The flag only applies to files created after it is set. **A database that already exists keeps its
COW files**, e.g. when moving a populated `/var/lib/mysql` onto btrfs. Convert it once, with MariaDB
stopped: `mv /var/lib/mysql /var/lib/mysql.cow`, recreate the directory (the tmpfiles rule flags
it on the next `systemd-tmpfiles --create`, or `chattr +C` by hand), then
`cp -a --reflink=never /var/lib/mysql.cow/. /var/lib/mysql/`, check with `lsattr`, start MariaDB,
and delete the old copy. A restore from an SQL export into a fresh database needs none of this.

**2. `ropewiki-backup.service` (hourly timer; the daily run also exports).**
1. `btrfs subvolume snapshot -r /srv/ropewiki /srv/.snapshots/ropewiki.$ts` (btrbk, so retention is
   handled in one place).
2. Once a day only: writable copy-on-write clone of that snapshot (instant, no extra space), a
   throwaway `mariadbd` on the clone's `mysql/` (socket only, no network) lets InnoDB recover, then
   `mariadb-dump --single-transaction --routines --events ropewiki | zstd` into
   `/srv/backups/ropewiki-$ts.sql.zst`; stop it and delete the clone.
3. Only after *all* of that succeeded, write `/var/lib/ropewiki-backup/last-success`
   (timestamp and the snapshot name). This stamp, not systemd's in-memory unit state, is what
   everything else trusts: it survives reboots.

The export comes from the snapshot, not the live database, so it matches the uploads exactly, and
because the snapshot has to open as a database for step 2 to work, every daily run also proves the
snapshot is restorable. The SQL export is the portable artefact (what makes a MySQL 5.7 -> MariaDB
or MariaDB 11 -> 12 move possible, and what developers can read); the snapshot is the fast, exact one.

**3. Alerts and freshness.** `OnFailure=` on the backup service triggers a notification unit (mail
once the relay exists). A separate timer fails (and alerts) if `last-success` is older than 2 hours,
which also catches the timer itself having stopped. This replaces `last_success`.

**4. Automatic restore drill (weekly).** `ropewiki-restore-test.service`: take the newest SQL export
(or restore the provider's latest volume snapshot into a scratch volume now and then), load it into
a scratch MariaDB, run `update.php --quick` against it (proving the current code can still upgrade
it), and check a few invariants: page and revision counts within a tolerance of production,
`Main_Page` renders, an SMW `#ask` returns rows. This is the generalisation of the manual
`UpgradeTest`/`UpgradeComplete` canary pages in the old runbook.

**5. Restore, as documented commands** (and a `ropewiki-restore` helper that keeps today's
"Restore X? (y/n)" confirmation, which is a good idea worth keeping):
- *Roll back this machine to a snapshot:* stop the site, replace `/srv/ropewiki` with a writable
  snapshot of the chosen one, start. Seconds. This is also the rollback for a failed upgrade.
- *New machine, or different database version:* create the empty database, load the SQL export with
  `--one-database ropewiki`, restore the uploads, start (the module runs `update.php`).
- *Lost disk:* create a volume from the provider's snapshot; the btrfs snapshots are inside it.

**6. Developer data.** Today developers get full production dumps ("distributed to developers
separately"), which contain user e-mail addresses, password hashes, session/token fields and the
CheckUser IP tables. Add a `ropewiki-export-sanitized` step (scrubs `user`, `cu_*`,
`recentchanges.rc_ip`, `ipblocks`, e-mail fields, tokens) and make *that* the artefact for dev VMs
and CI fixtures. It is also the input to [Real-data upgrade tests](real-data-upgrade-tests.md).
Needs a decision from whoever owns the data.

Open questions: backup encryption and who holds the keys (provider-side encryption of the volume
may be enough); whether the daily export should additionally be copied to an object store so a
database can be recovered without a volume restore.
