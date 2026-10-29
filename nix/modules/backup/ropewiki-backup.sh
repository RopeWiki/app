# shellcheck shell=bash
# Hourly: read-only btrfs snapshot of each configured subvolume, a SQL export once a day, expiry of
# old snapshots and exports, and finally the "last-success" stamp that the upgrade gate trusts.
# Settings arrive in the environment (see backup.nix).
#
# Retention: every snapshot for 24 hours, then the first snapshot of each UTC day for 30 days.
# Only entries named exactly ropewiki-YYYYMMDDTHHMMSSZ in <subvolume>/.snapshots are ever deleted.

shopt -s nullglob

stamp=${ROPEWIKI_BACKUP_STAMP:-/var/lib/ropewiki-backup/last-success}
export_dir=$ROPEWIKI_BACKUP_EXPORT_DIR
ts=$(date -u +%Y%m%dT%H%M%SZ)
now=$(date -u +%s)
snapshots=()

# 1. Snapshots. One subvolume is atomic; several are taken back to back.
for sub in $ROPEWIKI_BACKUP_SUBVOLUMES; do
  if ! btrfs subvolume show "$sub" >/dev/null 2>&1; then
    echo "ropewiki-backup: $sub is not a btrfs subvolume" >&2
    exit 1
  fi
  dir="${sub%/}/.snapshots"
  mkdir -p "$dir"
  if [[ -e $dir/ropewiki-$ts ]]; then
    # btrfs would silently nest the new snapshot inside the old one
    echo "ropewiki-backup: $dir/ropewiki-$ts exists (two backups in the same second?)" >&2
    exit 1
  fi
  btrfs subvolume snapshot -r "$sub" "$dir/ropewiki-$ts" >/dev/null
  snapshots+=("$dir/ropewiki-$ts")
  echo "snapshot $dir/ropewiki-$ts"
done

# 2. One SQL export per UTC day (the first run of the day makes it, later runs retry if it failed).
# The export is the portable copy: it loads into any MariaDB/MySQL version, the snapshot does not.
mkdir -p "$export_dir"
todays=("$export_dir/ropewiki-${ts%%T*}T"*.sql.zst)
if ((${#todays[@]} == 0)); then
  tmp=$(mktemp -p "$export_dir" .export.XXXXXX)
  if runuser -u ropewiki -- mariadb-dump --socket=/run/mysqld/mysqld.sock \
       --single-transaction --routines --events ropewiki | zstd -q -10 >"$tmp"; then
    mv "$tmp" "$export_dir/ropewiki-$ts.sql.zst"
    echo "export $export_dir/ropewiki-$ts.sql.zst"
  else
    rm -f "$tmp"
    echo "ropewiki-backup: SQL export failed" >&2
    exit 1
  fi
fi
find "$export_dir" -maxdepth 1 -name 'ropewiki-*.sql.zst' -mtime +30 -delete

# 3. Expire snapshots. Oldest first, so the first one seen for a day is that day's first.
for sub in $ROPEWIKI_BACKUP_SUBVOLUMES; do
  declare -A seen=()
  for path in "${sub%/}"/.snapshots/ropewiki-*; do
    name=${path##*/}
    [[ $name =~ ^ropewiki-([0-9]{8})T([0-9]{2})([0-9]{2})([0-9]{2})Z$ ]] || continue
    day=${BASH_REMATCH[1]}
    taken=$(date -u -d "${day:0:4}-${day:4:2}-${day:6:2} ${BASH_REMATCH[2]}:${BASH_REMATCH[3]}:${BASH_REMATCH[4]}" +%s)
    age=$((now - taken))
    if ((age < 86400)); then
      seen[$day]=1
    elif ((age > 30 * 86400)) || [[ -n ${seen[$day]:-} ]]; then
      btrfs subvolume delete "$path" >/dev/null
      echo "expired $path"
    else
      seen[$day]=1
    fi
  done
  unset seen
done

# 4. Only now, with everything done, record the success: time, then the snapshots it made.
mkdir -p "$(dirname "$stamp")"
{
  date -u +%s
  printf '%s\n' "${snapshots[@]}"
} >"$stamp.tmp"
mv "$stamp.tmp" "$stamp"
