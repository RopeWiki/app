# services.ropewiki.drainage: the drainage-area lookup that replaces the Luca server's
# `waterflow=winfo=` request, behind the site's nginx. The index is built from the small data set in
# packages/rw-drainage/fixtures; nothing is downloaded.
#
#   nix build .#checks.x86_64-linux.drainage
{
  name = "ropewiki-drainage";

  nodes.machine =
    { pkgs, ... }:
    {
      imports = [ ../vm/dev-site.nix ];
      services.ropewiki = {
        enable = true;
        search.enable = false;
        drainage = {
          enable = true;
          sourceUrl = null; # an index is provided, by the test script, below
        };
      };
      systemd.tmpfiles.rules = [ "d /var/lib/rw-drainage 0755 root root - -" ];
      environment.systemPackages = [ pkgs.rwDrainage ];
      virtualisation.memorySize = 2048;
    };

  testScript =
    { nodes, ... }:
    ''
      import json

      winfo = "https://localhost/luca/rwr?waterflow=winfo=34.2533,-117.5769"
      index = "${nodes.machine.services.ropewiki.drainage.index}"

      def fetch(url=winfo, flags=""):
          return machine.succeed(f"curl --silent --insecure {flags} --write-out '\\n%{{http_code}}' '{url}'").rsplit("\n", 1)

      machine.wait_for_unit("multi-user.target")
      machine.wait_for_unit("ropewiki-pages.service")
      machine.wait_for_open_port(443)

      with subtest("until the index exists nothing listens, nothing has failed, and the page just gets an error"):
          machine.succeed("systemctl is-active rw-drainage.path")
          machine.fail("systemctl is-active rw-drainage.service")
          assert fetch()[1] == "502", fetch()
          assert machine.succeed("systemctl --failed --no-legend").strip() == ""

      with subtest("the service starts when the index appears"):
          machine.succeed(f"install -m 0644 ${nodes.machine.services.ropewiki.drainage.package.fixtureIndex} {index}")
          machine.wait_for_unit("rw-drainage.service")
          machine.wait_for_open_port(9002)  # "active" is a moment before Python has bound it

      with subtest("the request the page sends, through nginx"):
          body, code = fetch(flags="--include")
          head, _, doc = body.partition("\r\n\r\n")
          assert code == "200", body
          assert "access-control-allow-origin: *" in head.lower(), head
          assert "application/json" in head.lower(), head
          doc = json.loads(doc)
          assert doc == {"list": [" O1 L4 Drainage:3.6km2 "], "drainage_km2": 3.6, "comid": 22554664}, doc

      with subtest("no river nearby is an empty list; other Luca requests are not served here"):
          assert json.loads(fetch("https://localhost/luca/rwr?waterflow=winfo=40,-100")[0]) == {"list": []}
          assert fetch("https://localhost/luca/rwr?pdfx=Lytle_Creek")[1] == "404"
          assert fetch("https://localhost/luca/rwr?waterflow=winfo=abc")[1] == "400"

      with subtest("only nginx can reach it"):
          listening = machine.succeed("ss -ltnH")
          assert "127.0.0.1:9002" in listening and "0.0.0.0:9002" not in listening and "*:9002" not in listening, listening

      with subtest("no builder unit when an index is provided"):
          machine.fail("systemctl cat rw-drainage-index.service")

      with subtest("the site's JavaScript reads the number from the reply"):
          js = machine.succeed("curl --fail --silent --insecure 'https://localhost/index.php?title=MediaWiki:Common.js&action=raw'")
          assert "drainage_km2" in js

      assert machine.succeed("systemctl --failed --no-legend").strip() == ""
    '';
}
