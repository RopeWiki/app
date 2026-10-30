# services.ropewiki.tileserver: the map tile server on its own host name (tiles.ropewiki.com),
# from upstream PR RopeWiki/app#155 ("Setup tileserver for public land tiles").
#
# Docker ran `maptiler/tileserver-gl` as the compose service `ropewiki_tileserver` with the tile
# directory (`<images>/tiles`, holding a `config.json` and the tile files) mounted at /data, and the
# reverse proxy answered `tiles.<host>` with `proxy_pass http://ropewiki_tileserver:8080`. This is
# the same: an OCI container (nixpkgs has no tileserver-gl package; it needs a Node build with
# native renderers) behind a second virtual host of the site's nginx.
#
# Off by default. The tiles themselves are data, not code: they are not part of the repository
# and the database export does not include them.
{
  config,
  lib,
  ...
}:

let
  inherit (lib)
    mkEnableOption
    mkIf
    mkOption
    types
    ;

  cfg = config.services.ropewiki.tileserver;
  site = config.services.ropewiki;
  serverName = builtins.head (lib.splitString ":" site.hostName);
  oci = config.virtualisation.oci-containers;

  containerName = "ropewiki-tileserver";
in
{
  options.services.ropewiki.tileserver = {
    enable = mkEnableOption "the map tile server (maptiler/tileserver-gl) on its own host name";

    hostName = mkOption {
      type = types.str;
      default = "tiles.${serverName}";
      defaultText = lib.literalExpression ''"tiles.''${site host name}"'';
      description = ''
        The name the tile server answers to, a virtual host of the site's nginx. TLS is the host's
        business, as for the site: set `enableACME`/`forceSSL`/... on
        `services.nginx.virtualHosts.<hostName>`. Production sits behind Cloudflare, which does
        the caching; nothing here caches.
      '';
    };

    dataDir = mkOption {
      type = types.path;
      default = "${site.imagesDir}/tiles";
      defaultText = lib.literalExpression ''"''${services.ropewiki.imagesDir}/tiles"'';
      description = ''
        The directory mounted (read-only) at /data in the container: `config.json` and the tile
        files it names. Production keeps it with the uploaded files, as `/rw/mount/images/tiles`
        was in Docker. Created empty when missing.
      '';
    };

    configFile = mkOption {
      type = types.str;
      default = "config.json";
      description = "tileserver-gl's `-c` argument: the configuration, relative to `dataDir`.";
    };

    image = mkOption {
      type = types.str;
      default = "docker.io/maptiler/tileserver-gl:latest";
      description = ''
        The container image. Docker pulled `latest` too, which means a restart after the image
        changed upstream upgrades the server; pin a tag or a digest for a reproducible system.
      '';
    };

    imageFile = mkOption {
      type = types.nullOr types.package;
      default = null;
      description = ''
        An image archive to load instead of pulling `image` (`pkgs.dockerTools.buildImage` and
        friends), for hosts without a registry and for the VM test.
      '';
    };

    port = mkOption {
      type = types.port;
      default = 8080;
      description = ''
        TCP port on 127.0.0.1 that the container publishes and nginx proxies to. Docker published
        8080 on every interface for debugging; this does not.
      '';
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = site.enable;
        message = "services.ropewiki.tileserver adds a virtual host to the site's nginx; enable services.ropewiki too.";
      }
      {
        assertion = cfg.hostName != serverName;
        message = "services.ropewiki.tileserver.hostName must differ from the site's host name (${serverName}).";
      }
    ];

    services.ropewiki.help.logs.tileserver = {
      description = "The map tile server (the container's output)";
      units = [ "${oci.backend}-${containerName}.service" ];
    };

    virtualisation.oci-containers.containers.${containerName} = {
      inherit (cfg) image;
      imageFile = mkIf (cfg.imageFile != null) cfg.imageFile;
      ports = [ "127.0.0.1:${toString cfg.port}:8080" ];
      volumes = [ "${cfg.dataDir}:/data:ro" ];
      cmd = [
        "-c"
        cfg.configFile
      ];
      # As Docker ran it: the tile files belong to whoever copied them there, and the image's own
      # user cannot be counted on to read them. Nothing is written (the mount is read-only).
      user = "root";
    };

    # Podman refuses to start a container whose mount source does not exist. -: leave an existing
    # directory's owner and mode alone.
    systemd.tmpfiles.rules = [ "d '${cfg.dataDir}' - - - - -" ];

    services.nginx.virtualHosts.${cfg.hostName}.locations."/".proxyPass =
      "http://127.0.0.1:${toString cfg.port}";
  };
}
