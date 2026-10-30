# shellcheck shell=bash
# ropewiki-backup-fresh [MAX_AGE_SECONDS]   (default 3600)
# Succeeds only if ropewiki-backup finished within MAX_AGE_SECONDS and the snapshots it recorded
# still exist. Read-only: it takes no snapshot and changes nothing. Used as the gate in front of
# NixOS upgrades and by the freshness monitor.

stamp=${ROPEWIKI_BACKUP_STAMP:-/var/lib/ropewiki-backup/last-success}
max_age=${1:-3600}

fail() {
  echo "ropewiki-backup-fresh: $1" >&2
  echo "  run: systemctl start ropewiki-backup.service" >&2
  exit 1
}

[[ -r $stamp ]] || fail "no successful backup recorded ($stamp)"
mapfile -t lines <"$stamp"
written=${lines[0]}
[[ $written =~ ^[0-9]+$ ]] || fail "unreadable stamp $stamp"

age=$(($(date -u +%s) - written))
((age <= max_age)) || fail "the last successful backup finished $((age / 60)) minutes ago (limit $((max_age / 60)))"

for snapshot in "${lines[@]:1}"; do
  [[ -d $snapshot ]] || fail "the snapshot $snapshot named by the last backup no longer exists"
done
