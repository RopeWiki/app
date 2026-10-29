# services.ropewiki.backup: hourly btrfs snapshots + a daily SQL export, and the gate that keeps
# NixOS from switching to a new system unless a backup has just succeeded.
#
# For real hosts only: it is off by default and the development VM does not use it. Design and
# reasoning: nix/docs/backups.md and nix/docs/upgrades.md.
#
# The snapshots are kept on the same disk; getting them off the machine is the cloud provider's
# volume snapshots' job. btrbk was considered and not used: its retention can't be tested without
# time travel, and ours is 15 lines of shell that nix/tests/backup.nix does test.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.ropewiki.backup;

  stamp = "/var/lib/ropewiki-backup/last-success";

  backup = pkgs.writeShellApplication {
    name = "ropewiki-backup";
    runtimeInputs = [
      pkgs.btrfs-progs
      pkgs.coreutils
      pkgs.findutils
      pkgs.util-linux
      pkgs.zstd
      config.services.mysql.package
    ];
    text = builtins.readFile ./backup/ropewiki-backup.sh;
  };

  fresh = pkgs.writeShellApplication {
    name = "ropewiki-backup-fresh";
    runtimeInputs = [ pkgs.coreutils ];
    text = builtins.readFile ./backup/ropewiki-backup-fresh.sh;
  };
in
{
  options.services.ropewiki.backup = {
    enable = lib.mkEnableOption "hourly btrfs snapshots, a daily SQL export, and the pre-upgrade backup gate";

    subvolumes = lib.mkOption {
      type = lib.types.listOf lib.types.path;
      default = [ "/" ];
      example = [ "/srv/ropewiki" ];
      description = ''
        btrfs subvolumes to snapshot. A snapshot of one subvolume is atomic, so put the database
        (`/var/lib/mysql`), the uploads and `/var/lib/ropewiki` on the same one, which is what the
        default `/` does. Several subvolumes are snapshotted back to back, not atomically.
        Snapshots go to `<subvolume>/.snapshots/ropewiki-<UTC timestamp>`.
      '';
    };

    exportDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/backups/ropewiki";
      description = "Where the daily SQL exports (`ropewiki-<timestamp>.sql.zst`, readable by root only) go.";
    };
  };

  config = lib.mkIf (config.services.ropewiki.enable && cfg.enable) {
    environment.systemPackages = [
      backup
      fresh
    ];

    systemd.services.ropewiki-backup = {
      description = "RopeWiki backup: btrfs snapshots and daily SQL export";
      wants = [ "mysql.service" ];
      after = [ "mysql.service" ];
      environment = {
        ROPEWIKI_BACKUP_SUBVOLUMES = lib.concatStringsSep " " cfg.subvolumes;
        ROPEWIKI_BACKUP_EXPORT_DIR = cfg.exportDir;
        ROPEWIKI_BACKUP_STAMP = stamp;
      };
      serviceConfig = {
        Type = "oneshot";
        ExecStart = lib.getExe backup;
        StateDirectory = "ropewiki-backup";
        Nice = 10;
        IOSchedulingClass = "idle";
      };
    };
    systemd.timers.ropewiki-backup = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "hourly";
        Persistent = true;
      };
    };

    # A failed unit is the alarm until there is a mail relay: this one fails when the timer above
    # has stopped producing backups (or the machine has been off for a long time).
    systemd.services.ropewiki-backup-monitor = {
      description = "Fail if the last successful RopeWiki backup is more than two hours old";
      environment.ROPEWIKI_BACKUP_STAMP = stamp;
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${lib.getExe fresh} 7200";
      };
    };
    systemd.timers.ropewiki-backup-monitor = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "3h";
        OnUnitActiveSec = "30min";
      };
    };

    # The gate. A read-only check, never an action: `switch-to-configuration` refuses to `switch`,
    # `test` or `boot` into a new system unless a backup finished within the last hour. (`boot` is
    # gated too: the database migration runs on that next boot. `dry-activate` changes nothing.)
    system.preSwitchChecks.ropewiki-backup-fresh = ''
      case "''${2:-}" in
        switch|test|boot) ROPEWIKI_BACKUP_STAMP=${stamp} ${lib.getExe fresh} 3600 ;;
      esac
    '';

    # Start a backup whenever an automatic upgrade starts; the gate above still decides.
    systemd.services.nixos-upgrade = lib.mkIf config.system.autoUpgrade.enable {
      wants = [ "ropewiki-backup.service" ];
      after = [ "ropewiki-backup.service" ];
    };
  };
}
