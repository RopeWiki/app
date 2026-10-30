# The standard NixOS VM test (pkgs.testers.runNixOSTest) for services.ropewiki:
#
#   nix build .#checks.x86_64-linux.ropewiki
#   nix run   .#checks.x86_64-linux.ropewiki.driverInteractive     # for a Python shell
#
# The Nix counterpart of .github/workflows/test-empty-site.yml (a new site renders), plus
# HTTPS and the production-mode hardening. Every file in this directory becomes a check.
{
  name = "ropewiki";

  nodes.machine =
    { pkgs, ... }:
    {
      imports = [ ../vm/dev-site.nix ];
      services.ropewiki.enable = true; # production mode, redirect to HTTPS, self-signed certificate
      environment.systemPackages = [
        pkgs.openssl
        pkgs.imagemagick
      ];
      virtualisation.memorySize = 2048;
    };

  testScript =
    { nodes, ... }:
    ''
      import json
      import re

      def get(path, flags="--fail --silent"):
          return machine.succeed(f"curl {flags} --insecure 'https://localhost{path}'")

      def status(path):
          return machine.succeed(f"curl --silent --insecure --output /dev/null --write-out '%{{http_code}}' 'https://localhost{path}'")

      machine.wait_for_unit("multi-user.target")
      for unit in ["mediawiki-init", "phpfpm-mediawiki", "nginx", "ropewiki-searchd"]:
          machine.wait_for_unit(f"{unit}.service")
      machine.wait_for_open_port(443)
      assert machine.succeed("systemctl --failed --no-legend").strip() == "", machine.succeed("systemctl --failed")

      with subtest("front page renders on a database MediaWiki installed itself"):
          html = get("/Main_Page")
          assert "MediaWiki has been installed" in html, html[:2000]

      with subtest("tables are binary; utf8 only where MediaWiki or SMW ask for it"):
          # 4-byte characters (emoji) do not fit utf8mb3, so binary is the default (see
          # $wgDBTableOptions in LocalSettings.php). MediaWiki's searchindex is MyISAM utf8
          # because MySQL fulltext indexes need text columns; SMW makes its case-insensitive
          # columns utf8.
          db = "mariadb --batch --skip-column-names information_schema -e"
          tables = machine.succeed(f"{db} \"SELECT table_name, table_collation FROM tables WHERE table_schema = 'mediawiki' AND table_collation <> 'binary' AND table_name <> 'searchindex'\"")
          assert tables.strip() == "", tables
          columns = machine.succeed(f"{db} \"SELECT table_name, column_name, collation_name FROM columns WHERE table_schema = 'mediawiki' AND collation_name IS NOT NULL AND collation_name <> 'binary' AND table_name <> 'searchindex' ORDER BY 1, 2\"")
          assert all(l.startswith("smw_") for l in columns.splitlines()), columns

      with subtest("the extensions the site depends on are loaded"):
          info = json.loads(get("/api.php?action=query&meta=siteinfo&siprop=extensions&format=json"))
          loaded = {e["name"] for e in info["query"]["extensions"]}
          for name in ["SemanticMediaWiki", "PageForms", "Maps", "SphinxSearch", "Scribunto", "SemanticResultFormats"]:
              assert name in loaded, f"{name} missing from {sorted(loaded)}"

      with subtest("static assets, robots.txt and the codebase marker are served"):
          get("/leaflet/1.9.4/leaflet.js", "--fail --silent --output /dev/null")
          robots = get("/robots.txt")
          assert "disallow: /" in robots, robots
          get("/codebase_version.html")

      with subtest("HTTPS uses a self-signed certificate; plain HTTP redirects to it"):
          cert = machine.succeed("openssl s_client -connect localhost:443 -servername localhost </dev/null 2>/dev/null | openssl x509 -noout -subject -issuer -ext subjectAltName")
          assert "CN=localhost" in cert and "DNS:localhost" in cert, cert
          subject, issuer = [l.split("=", 1)[1].strip() for l in cert.splitlines() if l.startswith(("subject", "issuer"))]
          assert subject == issuer, cert
          machine.fail("curl --fail --silent https://localhost/")  # a verifying client rejects it
          head = machine.succeed("curl --silent --head http://localhost/Main_Page")
          assert " 301 " in head.splitlines()[0] and "location: https://localhost/main_page" in head.lower(), head
          assert "https://localhost" in get("/Main_Page")  # MediaWiki builds https URLs

      with subtest("production mode (the default) hides errors, versions and attribution"):
          head = get("/Main_Page", "--silent --head").lower()
          assert "x-powered-by" not in head, head
          assert "server: nginx\r\n" in head, head  # no version number
          page = get("/Main_Page")
          assert 'name="generator"' not in page, "generator meta tag present"
          hits = [" ".join(page[max(0, m.start() - 160):m.end() + 160].split()) for m in re.finditer("poweredby", page, re.I)]
          assert not hits, "powered-by present: " + " ||| ".join(hits)
          ini = machine.succeed("systemctl cat phpfpm-mediawiki.service | grep -o -- ' -c [^ ]*' | cut -d' ' -f3").strip()
          settings = machine.succeed(f"grep -E '^(display_errors|expose_php|log_errors)' {ini}")
          for want in [r"^display_errors\s*=\s*0", r"^expose_php\s*=\s*0", r"^log_errors\s*=\s*1"]:
              assert re.search(want, settings, re.M), f"{want} not in {settings!r}"
          for path in ["/composer.json", "/maintenance/update.php", "/includes/Setup.php", "/mw-config/index.php",
                       "/LocalSettings.php", "/extensions/Scribunto/extension.json", "/skins/Vector/skin.json",
                       "/RELEASE-NOTES-1.39"]:  # the last is just a (missing) wiki page: the file is not in the web root
              assert status(path) == "404", f"{path} -> {status(path)}"
          redirect = get("/Special:Version", "--silent --output /dev/null --write-out '%{http_code} %{redirect_url}'")
          assert redirect.startswith("302") and "UserLogin" in redirect, redirect
          # ... while the entry points the site really uses keep working
          for path in ["/index.php?title=Main_Page", "/api.php?action=query&meta=siteinfo&format=json", "/load.php?modules=startup&only=scripts&raw=1"]:
              get(path, "--fail --silent --output /dev/null")

      with subtest("Sphinx stays up and the reindex timer's job succeeds"):
          machine.wait_until_succeeds("ss -ltn | grep -q 127.0.0.1:9312")
          # A crash loop (Restart=always) can still look "active" for a moment, so check the counter.
          machine.succeed("systemctl is-active ropewiki-searchd.service")
          machine.sleep(10)
          assert machine.succeed("systemctl show -p NRestarts --value ropewiki-searchd.service").strip() == "0"
          machine.succeed("systemctl start ropewiki-sphinx-reindex.service")

      with subtest("uploaded files are stored in imagesDir and served from it"):
          images = "${nodes.machine.services.ropewiki.imagesDir}"
          # importImages stores a file the way an upload does: as the MediaWiki user, in the hashed
          # folders under $wgUploadDirectory, with a File: page (no browser session needed).
          machine.succeed("mkdir /tmp/imgs && convert -size 80x80 xc:red /tmp/imgs/Test.png && chmod -R a+rX /tmp/imgs")
          machine.succeed("ropewiki-maintenance importImages.php --comment=test /tmp/imgs png")
          info = json.loads(get("/api.php?action=query&titles=File:Test.png&prop=imageinfo&iiprop=url&iiurlwidth=40&format=json"))
          image = next(iter(info["query"]["pages"].values()))["imageinfo"][0]
          prefix = "https://localhost/images/"
          assert image["url"].startswith(prefix) and image["thumburl"].startswith(prefix + "thumb/"), image
          stored = f"{images}/{image['url'][len(prefix):]}"
          assert machine.succeed(f"stat -c %U {stored}").strip() == "mediawiki", stored
          # nginx runs as another user and the state directory is not world readable
          machine.succeed(f"curl --fail --silent --insecure -o /tmp/served.png '{image['url']}' && cmp /tmp/served.png /tmp/imgs/Test.png")
          # the thumbnail was rendered into imagesDir and is served from there
          machine.succeed(f"curl --fail --silent --insecure -o /tmp/thumb.png '{image['thumburl']}'")
          assert machine.succeed("identify -format %wx%h /tmp/thumb.png").strip() == "40x40"
          machine.succeed(f"test -f {images}/thumb/{image['url'][len(prefix):]}/40px-Test.png")
          assert status("/images/no/such/file.png") == "404"
          # nothing uploaded is ever run as PHP
          machine.succeed(f"echo '<?php echo 6*7;' > {images}/probe.php && chmod a+r {images}/probe.php")
          assert get("/images/probe.php").startswith("<?php"), "an uploaded .php file was not served as plain text"
          machine.succeed(f"rm {images}/probe.php")

      with subtest("ropewiki-help lists the tools, ropewiki-logs shows the logs"):
          help_text = machine.succeed("ropewiki-help")
          for name in ["ropewiki-help", "ropewiki-maintenance", "ropewiki-import", "ropewiki-logs", "nginx-access"]:
              assert name in help_text, (name, help_text)
          assert "ropewiki-backup" not in help_text, "backup is off, its commands should not be listed"
          # every command it names exists
          for name in re.findall(r"^  (ropewiki-[a-z-]+)", help_text, re.M):
              machine.succeed(f"command -v {name}")
          # every log it names shows something (the units are the ones this machine runs)
          for name in re.findall(r"^  ([a-z-]+)$", help_text.split("Logs\n", 1)[1], re.M):
              out = machine.succeed(f"ropewiki-logs {name} -n 5 --no-pager" if name != "nginx-access" else "ropewiki-logs nginx-access -n 5")
              assert out.strip(), f"no {name} log"
          assert "GET /Main_Page" in machine.succeed("ropewiki-logs nginx-access -n 200")
          assert machine.succeed("ropewiki-logs --no-pager -n 3").strip()  # no name means all
          assert "usage: ropewiki-logs" in machine.fail("ropewiki-logs nonsense 2>&1")  # prints usage, exits 1

      with subtest("the site JavaScript and CSS are published as MediaWiki: pages"):
          pages = "${nodes.machine.services.ropewiki.sitePages}"
          names = machine.succeed(f"ls {pages}").split("\n")[:-1]
          assert "MediaWiki:Common.js" in names and "MediaWiki:Common.css" in names, names
          for name in names:
              want = machine.succeed(f"cat '{pages}/{name}'")
              assert get(f"/index.php?title={name}&action=raw").strip() == want.strip(), name
          # what Common.css @imports must be reachable, with the pretty URL the file uses
          assert "breadcrumb" in get("/MediaWiki:Common-01-breadcrumbs.css?action=raw&ctype=text/css")
          # and ResourceLoader must be serving the site module from them
          assert "Common-01-breadcrumbs.css" in get("/load.php?modules=site.styles&only=styles&skin=vector&lang=en")
          found = re.search(r"^function (\w+)", machine.succeed(f"cat {pages}/MediaWiki:Common.js"), re.M)
          assert found, "no function in Common.js"
          assert found.group(1) in get("/load.php?modules=site&only=scripts&skin=vector&lang=en")

      with subtest("publishing again changes nothing; pages outside the build are reported, not deleted"):
          def revisions():
              return len(json.loads(get("/api.php?action=query&prop=revisions&titles=MediaWiki:Common.js&rvlimit=max&format=json"))["query"]["pages"].popitem()[1]["revisions"])
          assert revisions() == 1
          machine.succeed("echo '/* stray */' | ropewiki-maintenance edit.php 'MediaWiki:Common-99-stray.css'")
          machine.succeed("systemctl restart ropewiki-pages.service")
          assert revisions() == 1
          assert "not in the build, left alone: MediaWiki:Common-99-stray.css" in machine.succeed("journalctl -u ropewiki-pages.service --no-pager")
          assert "stray" in get("/MediaWiki:Common-99-stray.css?action=raw")
    '';
}
