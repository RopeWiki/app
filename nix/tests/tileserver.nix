# services.ropewiki.tileserver: the container runs with the tile directory mounted read-only, the
# arguments Docker used, and answers on its own host name behind the site's nginx. The image is
# a stand-in built here (a static file server on 8080 in place of tileserver-gl, which cannot be
# pulled in a test), so what is checked is the wiring, not tileserver-gl.
#
#   nix build .#checks.x86_64-linux.tileserver
{
  name = "ropewiki-tileserver";

  nodes.machine =
    { pkgs, ... }:
    let
      # `tileserver-gl -c config.json` serves /data; this serves /data and records its arguments.
      stub = pkgs.dockerTools.buildImage {
        name = "tileserver-stub";
        tag = "test";
        copyToRoot = pkgs.buildEnv {
          name = "stub-root";
          paths = [
            pkgs.busybox
            (pkgs.writeTextDir "etc/passwd" "root:x:0:0:root:/:/bin/sh\n") # `--user root` needs it
            (pkgs.writeScriptBin "tileserver" ''
              #!${pkgs.busybox}/bin/sh
              mkdir -p /www
              echo "$@" > /www/args
              id -u > /www/uid
              ln -s /data /www/data
              exec httpd -f -p 8080 -h /www
            '')
          ];
        };
        config.Entrypoint = [ "/bin/tileserver" ];
      };
    in
    {
      imports = [ ../vm/dev-site.nix ];
      services.ropewiki = {
        enable = true;
        search.enable = false;
        tileserver = {
          enable = true;
          image = "tileserver-stub:test";
          imageFile = stub;
        };
      };
      virtualisation.memorySize = 2048;
    };

  testScript =
    { nodes, ... }:
    let
      data = nodes.machine.services.ropewiki.tileserver.dataDir;
      container = "ropewiki-tileserver";
    in
    ''
      def tiles(path):
          return machine.succeed(f"curl --silent --fail --header 'Host: tiles.localhost' http://localhost{path}")

      machine.wait_for_unit("multi-user.target")
      machine.wait_for_unit("ropewiki-pages.service")
      machine.wait_for_unit("podman-${container}.service")
      machine.wait_for_open_port(8080)

      with subtest("the data directory exists and is listed with the logs"):
          machine.succeed("test -d ${data}")
          assert "podman-${container}.service" in machine.succeed("ropewiki-help")
          machine.succeed("ropewiki-logs tileserver")

      with subtest("the container gets Docker's arguments and the tile directory, read-only"):
          assert tiles("/args").strip() == "-c config.json", tiles("/args")
          machine.succeed("podman inspect ${container} --format '{{range .Mounts}}{{.Source}}:{{.Destination}}:{{.RW}}{{println}}{{end}}' | grep -Fx '${data}:/data:false'")
          machine.succeed("echo '{}' > ${data}/config.json && echo tile > ${data}/9.pbf")
          assert tiles("/data/9.pbf").strip() == "tile"
          machine.fail("podman exec ${container} sh -c 'echo x > /data/new'")

      with subtest("only nginx publishes it: loopback port, own host name"):
          machine.succeed("curl --silent --fail http://127.0.0.1:8080/args")
          machine.fail("curl --silent --fail --max-time 3 http://$(hostname -i | cut -d' ' -f1):8080/args")
          # the site's own host name does not reach the tile server
          assert "-c config.json" not in machine.succeed("curl --silent --insecure https://localhost/args")
    '';
}
