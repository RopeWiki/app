# The MariaDB data directory is NOCOW when it lives on btrfs.
#
#   nix build .#checks.x86_64-linux.nocow
#
# (On any other filesystem the unit does nothing; every other test runs on ext4 and relies on that.)
{
  name = "ropewiki-nocow";

  nodes.machine =
    { pkgs, ... }:
    {
      imports = [ ../vm/dev-site.nix ];
      services.ropewiki = {
        enable = true;
        search.enable = false;
      };
      virtualisation.fileSystems."/srv/db" = {
        device = "/dev/vdb";
        fsType = "btrfs";
        autoFormat = true;
      };
      services.mysql.dataDir = "/srv/db/mysql";
      environment.systemPackages = [ pkgs.e2fsprogs ];
      virtualisation.emptyDiskImages = [ 1024 ];
      virtualisation.memorySize = 2048;
    };

  testScript = ''
    machine.wait_for_unit("multi-user.target")
    machine.wait_for_unit("mediawiki-init.service")  # the database works on it
    assert machine.succeed("systemctl --failed --no-legend").strip() == "", machine.succeed("systemctl --failed")

    fstype = machine.succeed("stat -f -c %T /srv/db/mysql").strip()
    assert fstype == "btrfs", machine.succeed("findmnt; lsblk; systemctl status srv-db.mount 'systemd-makefs@dev-vdb.service' --no-pager || true") + fstype

    def nocow(path):
        return "C" in machine.succeed(f"lsattr -d {path}").split()[0]

    assert nocow("/srv/db/mysql"), "data directory is not NOCOW"
    # files MariaDB created are NOCOW too: the flag was set before it first started
    for f in ["ibdata1", "mediawiki/page.ibd"]:
        assert nocow(f"/srv/db/mysql/{f}"), f"{f} is COW"
    # data that is not the database is untouched
    machine.succeed("touch /srv/db/plain")
    assert not nocow("/srv/db/plain")
  '';
}
