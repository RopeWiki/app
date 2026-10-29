# The standard NixOS VM test (pkgs.testers.runNixOSTest) for services.ropewiki:
#
#   nix build .#checks.x86_64-linux.ropewiki
#   nix run   .#checks.x86_64-linux.ropewiki.driverInteractive     # for a Python shell
#
# The Nix counterpart of .github/workflows/test-empty-site.yml (an empty site renders), plus
# HTTPS and the production-mode hardening. Every file in this directory becomes a check.
{
  name = "ropewiki";

  nodes.machine =
    { pkgs, ... }:
    {
      imports = [ ../vm/dev-site.nix ];
      services.ropewiki.enable = true; # production mode, redirect to HTTPS, self-signed certificate
      environment.systemPackages = [ pkgs.openssl ];
      virtualisation.memorySize = 2048;
    };

  testScript = ''
    import json
    import re

    def get(path, flags="--fail --silent"):
        return machine.succeed(f"curl {flags} --insecure 'https://localhost{path}'")

    def status(path):
        return machine.succeed(f"curl --silent --insecure --output /dev/null --write-out '%{{http_code}}' 'https://localhost{path}'")

    machine.wait_for_unit("multi-user.target")
    for unit in ["ropewiki-init", "phpfpm-ropewiki", "nginx", "ropewiki-searchd"]:
        machine.wait_for_unit(f"{unit}.service")
    machine.wait_for_open_port(443)
    # on ext4 the NOCOW flag on the MariaDB directory (a btrfs thing) must be harmless
    assert machine.succeed("systemctl --failed --no-legend").strip() == "", machine.succeed("systemctl --failed")

    with subtest("front page renders from the empty schema"):
        html = get("/Main_Page")
        assert "This is a blank copy of ropewiki" in html, html[:2000]

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
        ini = machine.succeed("systemctl cat phpfpm-ropewiki.service | grep -o -- ' -c [^ ]*' | cut -d' ' -f3").strip()
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
  '';
}
