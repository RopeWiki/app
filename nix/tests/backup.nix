# services.ropewiki.backup: snapshots, retention, the SQL export, and the pre-upgrade gate.
#
#   nix build .#checks.x86_64-linux.backup
#
# A real btrfs disk is mounted at /srv/data and the clock is set to a fixed time, so that the
# retention rules can be checked against snapshots with made-up ages.
{
  name = "ropewiki-backup";

  nodes.machine =
    { pkgs, ... }:
    {
      imports = [ ../vm/dev-site.nix ];
      services.ropewiki = {
        enable = true;
        search.enable = false;
        backup = {
          enable = true;
          subvolumes = [ "/srv/data" ];
          exportDir = "/srv/data/exports";
        };
      };
      boot.supportedFilesystems = [ "btrfs" ];
      environment.systemPackages = [ pkgs.btrfs-progs ];
      virtualisation.emptyDiskImages = [ 1024 ];
      virtualisation.memorySize = 2048;
    };

  testScript =
    { nodes, ... }:
    ''
      snaps = "/srv/data/.snapshots"
      # switch-to-configuration runs this as `<script> <new system> <action>`, before it changes anything.
      gate = "${nodes.machine.system.preSwitchChecksScript} /nix/store/new-system"

      def backup():
          status, _ = machine.execute("systemctl start ropewiki-backup.service")
          if status != 0:
              raise Exception(machine.succeed("journalctl -u ropewiki-backup.service --no-pager -n 30"))

      def refused(command, message):
          # exit status 1 *and* the right message, so that "command not found" can't pass as a refusal
          status, output = machine.execute(f"{command} 2>&1")
          assert status == 1 and message in output, f"{command}: status {status}, output: {output!r}"

      def gate_refuses(action):
          refused(f"{gate} {action}", "Pre-switch check 'ropewiki-backup-fresh' failed")

      machine.wait_for_unit("multi-user.target")
      machine.wait_for_unit("mediawiki-init.service")
      machine.succeed("mkfs.btrfs -q /dev/vdb && mkdir -p /srv/data && mount /dev/vdb /srv/data")

      # Nothing else may run a backup (or a catch-up run after the clock change) during the test.
      machine.succeed("systemctl stop ropewiki-backup.timer ropewiki-backup-monitor.timer")
      machine.succeed("date -s '2030-06-15 12:00:00'")

      with subtest("before any backup the gate refuses to switch"):
          refused("ropewiki-backup-fresh", "no successful backup recorded")
          gate_refuses("switch")
          machine.succeed(f"{gate} dry-activate")  # nothing changes on a dry run

      with subtest("snapshots: 24 h of everything, then the first of each day for 30 days"):
          # name -> kept?, with "now" = 2030-06-15 12:00 UTC
          fake = {
              "20300615T110000Z": True,   # 1 h old
              "20300615T000000Z": True,   # 12 h
              "20300614T200000Z": True,   # 16 h
              "20300614T130000Z": True,   # 23 h
              "20300614T110000Z": False,  # 25 h, not the first of its day
              "20300614T000000Z": True,   # 36 h, the first of its day
              "20300613T180000Z": False,  # second of its day
              "20300613T060000Z": True,   # first of its day
              "20300517T080000Z": False,  # 29 d, second of its day
              "20300517T000000Z": True,   # 29 d 12 h, first of its day
              "20300515T120000Z": False,  # 31 d: too old
              "20300401T000000Z": False,  # 75 d
          }
          machine.succeed(f"mkdir -p {snaps}")
          for name in fake:
              machine.succeed(f"btrfs subvolume create {snaps}/ropewiki-{name}")
          # things that are not ours must never be touched
          machine.succeed(f"btrfs subvolume create {snaps}/manual-keep-me && mkdir {snaps}/ropewiki-notatimestamp")

          backup()

          left = machine.succeed(f"ls {snaps}").split()
          new = [n for n in left if n.startswith("ropewiki-20300615T12")]
          assert len(new) == 1, left
          kept = sorted(f"ropewiki-{n}" for n, keep in fake.items() if keep) + ["manual-keep-me", "ropewiki-notatimestamp"] + new
          assert sorted(left) == sorted(kept), f"\nleft:     {sorted(left)}\nexpected: {sorted(kept)}"
          assert "ro=true" in machine.succeed(f"btrfs property get -ts {snaps}/{new[0]} ro")

      with subtest("a SQL export is made once a day, readable by root only"):
          exports = machine.succeed("ls /srv/data/exports").split()
          assert len(exports) == 1 and exports[0].startswith("ropewiki-20300615T"), exports
          assert machine.succeed(f"stat -c %a /srv/data/exports/{exports[0]}").strip() == "600"
          dump = machine.succeed(f"zstd -dc /srv/data/exports/{exports[0]}")
          assert "CREATE TABLE `page`" in dump and "CREATE DATABASE" not in dump
          machine.sleep(2)
          backup()  # the same day again
          assert len(machine.succeed("ls /srv/data/exports").split()) == 1

      with subtest("old exports expire"):
          machine.succeed("touch -d '2030-04-01' /srv/data/exports/ropewiki-20300401T000000Z.sql.zst")
          machine.sleep(2)
          backup()
          assert "20300401" not in machine.succeed("ls /srv/data/exports")

      with subtest("the gate opens for a fresh backup and closes when it is stale or its snapshot is gone"):
          machine.succeed("ropewiki-backup-fresh")
          machine.succeed(f"{gate} switch")
          machine.succeed(f"{gate} test")
          machine.succeed(f"{gate} boot")
          machine.succeed(f"{gate} dry-activate")
          machine.succeed("date -s '2030-06-15 13:30:00'")  # 90 minutes later
          refused("ropewiki-backup-fresh", "minutes ago (limit 60)")
          gate_refuses("switch")
          gate_refuses("test")
          gate_refuses("boot")  # the migration would run on the next boot
          machine.succeed("ropewiki-backup-fresh 7200")
          machine.sleep(2)
          backup()
          machine.succeed(f"{gate} switch")
          recorded = machine.succeed("sed -n 2p /var/lib/ropewiki-backup/last-success").strip()
          machine.succeed(f"btrfs subvolume delete {recorded}")
          refused("ropewiki-backup-fresh", "no longer exists")
          gate_refuses("switch")

      with subtest("the monitor unit fails when backups have stopped"):
          machine.sleep(2)
          backup()
          machine.succeed("systemctl start ropewiki-backup-monitor.service")
          machine.succeed("date -s '2030-06-15 17:00:00'")
          machine.fail("systemctl start ropewiki-backup-monitor.service")
    '';
}
