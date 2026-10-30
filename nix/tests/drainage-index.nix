# rw-drainage-index.service: download the NHDPlus archive, extract it and build the index. The
# "archive" is a made-up one in the real layout (packages/rw-drainage.nix, fixtureArchive) served
# from the Nix store through a file:// URL.
#
#   nix build .#checks.x86_64-linux.drainage-index
{
  name = "ropewiki-drainage-index";

  nodes.machine =
    { pkgs, ... }:
    {
      imports = [ ../vm/dev-site.nix ];
      services.ropewiki = {
        enable = true;
        search.enable = false;
        drainage = {
          enable = true;
          sourceUrl = "file://${pkgs.rwDrainage.fixtureArchive}/nhdplus.7z";
        };
      };
      virtualisation.memorySize = 2048;
    };

  testScript =
    { nodes, ... }:
    ''
      import json

      index = "${nodes.machine.services.ropewiki.drainage.index}"
      winfo = "https://localhost/luca/rwr?waterflow=winfo=34.2533,-117.5769"

      def answer():
          return json.loads(machine.succeed(f"curl --fail --silent --insecure '{winfo}'"))

      machine.wait_for_unit("multi-user.target")

      with subtest("a new host builds its index, then the service starts by itself"):
          machine.wait_until_succeeds(f"test -e {index}", timeout=120)
          machine.wait_for_unit("rw-drainage.service")
          machine.wait_for_open_port(9002)
          machine.wait_for_open_port(443)
          assert answer()["comid"] == 22554664, answer()
          assert answer()["list"] == [" O1 L4 Drainage:3.6km2 "]

      with subtest("the download and the extracted geodatabase are cleaned up; the index is world-readable"):
          machine.succeed("test ! -e /var/lib/rw-drainage/rw-drainage-work")
          assert machine.succeed(f"stat -c %a {index}").strip() == "644"
          machine.succeed("systemctl show -p Result --value rw-drainage-index.service | grep -x success")

      with subtest("an existing index is left alone; deleting it rebuilds it"):
          before = machine.succeed(f"stat -c %Y.%y {index}")
          machine.succeed("systemctl start rw-drainage-index.service")
          assert machine.succeed(f"stat -c %Y.%y {index}") == before
          machine.succeed(f"rm {index}")
          machine.succeed("systemctl start rw-drainage-index.service")
          machine.wait_until_succeeds(f"test -e {index}", timeout=120)
          assert answer()["comid"] == 22554664

      assert machine.succeed("systemctl --failed --no-legend").strip() == ""
    '';
}
