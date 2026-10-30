# services.ropewiki.imageProxy: development mode where uploaded files are shown from another site.
# The "other site" is a second VM with HTTPS and a certificate the wiki's machine trusts. It has two
# virtual hosts with different certificates, so a request without the right SNI name or Host header
# fails (as it would against the real thing, behind a shared address).
#
#   nix build .#checks.x86_64-linux.image-proxy
{ pkgs, lib, ... }:

let
  mkCert =
    name:
    pkgs.runCommand "cert-${name}" { nativeBuildInputs = [ pkgs.openssl ]; } ''
      mkdir $out
      openssl req -x509 -newkey rsa:2048 -nodes -days 36500 \
        -keyout $out/key.pem -out $out/cert.pem \
        -subj /CN=${name} -addext subjectAltName=DNS:${name}
    '';
  prod = mkCert "prod.example";
  other = mkCert "other.example";
in
{
  name = "ropewiki-image-proxy";

  nodes.production =
    { config, ... }:
    {
      # a DNS server for the machine's nginx, whose resolver does not read /etc/hosts
      services.dnsmasq = {
        enable = true;
        resolveLocalQueries = false;
        settings = {
          no-resolv = true;
          address = "/prod.example/${config.networking.primaryIPAddress}";
        };
      };
      services.nginx = {
        enable = true;
        virtualHosts."prod.example" = {
          onlySSL = true;
          sslCertificate = "${prod}/cert.pem";
          sslCertificateKey = "${prod}/key.pem";
          locations."/images/" = {
            root = pkgs.runCommand "prod-files" { } ''
              mkdir -p $out/images/a/ab $out/images/thumb/a/ab/Test.png
              printf 'the file on the other site' > $out/images/a/ab/Test.png
              printf 'its thumbnail' > $out/images/thumb/a/ab/Test.png/40px-Test.png
            '';
            # what the proxy sent, to check that it did not pass the visitor's cookies on
            extraConfig = ''
              add_header X-Seen-Host "$host";
              add_header X-Seen-Cookie "[$http_cookie]"; # brackets: nginx omits a header whose value is empty
            '';
          };
        };
        # whoever connects without asking for prod.example (no SNI) lands here
        virtualHosts."other.example" = {
          default = true;
          onlySSL = true;
          sslCertificate = "${other}/cert.pem";
          sslCertificateKey = "${other}/key.pem";
          locations."/".return = "421";
        };
      };
      networking.firewall.allowedTCPPorts = [ 443 ];
      networking.firewall.allowedUDPPorts = [ 53 ];
    };

  nodes.machine =
    { nodes, ... }:
    {
      imports = [ ../vm/dev-site.nix ];
      services.ropewiki = {
        enable = true;
        search.enable = false;
        imageProxy = "https://prod.example";
      };
      networking.extraHosts = "${nodes.production.networking.primaryIPAddress} prod.example";
      security.pki.certificateFiles = [ "${prod}/cert.pem" ];
      virtualisation.memorySize = 2048;

      # the same, with the name looked up when a file is requested (what nix run .#vm does)
      specialisation.request-time-dns.configuration = {
        services.nginx.resolver = {
          addresses = [ nodes.production.networking.primaryIPAddress ];
          valid = "1s";
          ipv6 = false;
        };
        networking.extraHosts = lib.mkForce ""; # only DNS knows prod.example now
      };
    };

  testScript = ''
    import json

    def get(path, flags=""):
        return machine.succeed(f"curl --silent --insecure {flags} 'https://localhost{path}'")

    def code(path, flags=""):
        return get(path, f"--output /dev/null --write-out '%{{http_code}}' {flags}")

    start_all()
    production.wait_for_unit("nginx.service")
    machine.wait_for_unit("multi-user.target")
    machine.wait_for_open_port(443)

    with subtest("MediaWiki links uploaded files and thumbnails to the other site"):
        # a file of the kind an upload would have made; importImages registers it without needing a browser
        machine.succeed("mkdir /tmp/imgs && ${pkgs.imagemagick}/bin/convert -size 80x80 xc:red /tmp/imgs/Test.png && chmod -R a+rX /tmp/imgs")
        machine.succeed("ropewiki-maintenance importImages.php --comment=test /tmp/imgs png")
        info = json.loads(get("/api.php?action=query&titles=File:Test.png&prop=imageinfo&iiprop=url&iiurlwidth=40&format=json"))
        image = next(iter(info["query"]["pages"].values()))["imageinfo"][0]
        assert image["url"].startswith("https://prod.example/images/"), image
        assert image["thumburl"].startswith("https://prod.example/images/thumb/"), image
        # and nothing was rendered here for it
        machine.fail("find /var/lib/mediawiki/images/thumb -type f | grep .")

    with subtest("/images/ for paths MediaWiki does not know are fetched from the other site"):
        assert get("/images/a/ab/Test.png") == "the file on the other site"
        assert get("/images/thumb/a/ab/Test.png/40px-Test.png") == "its thumbnail"
        assert code("/images/no/such/file.png") == "404"

    with subtest("the other site sees its own name, and none of the visitor's cookies"):
        head = get("/images/a/ab/Test.png", "--head --cookie 'wikiUserName=Admin; wiki_session=secret'").lower()
        assert "x-seen-host: prod.example" in head, head
        assert "x-seen-cookie: []" in head and "secret" not in head, head

    with subtest("it is read-only"):
        assert code("/images/a/ab/Test.png", "-X POST --data x") == "403"
        assert code("/images/a/ab/New.png", "-X PUT --data x") == "403"

    with subtest("with a resolver the name is looked up per request, so nginx starts without DNS"):
        machine.succeed("/run/current-system/specialisation/request-time-dns/bin/switch-to-configuration test")
        production.wait_for_unit("dnsmasq.service")
        assert get("/images/a/ab/Test.png") == "the file on the other site"
        production.succeed("systemctl stop dnsmasq.service")
        # looked up at start, prod.example could not be found and nginx would refuse to start
        machine.succeed("systemctl restart nginx.service")
        machine.wait_for_open_port(443)
        assert code("/images/a/ab/Test.png") == "502"
        assert "Test.png" in get("/api.php?action=query&titles=File:Test.png&prop=imageinfo&iiprop=url&format=json")  # the wiki itself is up
        production.succeed("systemctl start dnsmasq.service")
        machine.wait_until_succeeds("curl --silent --insecure --fail https://localhost/images/a/ab/Test.png | grep -q 'the file on the other site'")

    assert machine.succeed("systemctl --failed --no-legend").strip() == ""
  '';
}
