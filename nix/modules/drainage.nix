# services.ropewiki.drainage: the "~N mi2" drainage-area badge on canyon pages.
#
# The Luca server (RWServer) answered `/luca/rwr?waterflow=winfo=<lat>,<lng>` from river data it
# had scraped from the EPA years ago. This serves the same request from NHDPlus V2.1 with
# nix/packages/rw-drainage.nix. Design and what is and is not covered: nix/docs/drainage.md.
#
# Off by default. Turning it on with the default `sourceUrl` makes the next `switch` download the
# EPA's 7.8 GB archive in the background (rw-drainage-index.service), once; until the index
# exists nothing listens and /luca/rwr answers 502, which the page treats as "no badge".
{
  config,
  lib,
  pkgs,
  ...
}:

let
  inherit (lib)
    mkEnableOption
    mkIf
    mkOption
    types
    ;

  cfg = config.services.ropewiki.drainage;
  site = config.services.ropewiki;
  serverName = builtins.head (lib.splitString ":" site.hostName);

  user = "rw-drainage";
  address = "127.0.0.1:${toString cfg.port}";
  stateDir = "/var/lib/rw-drainage";
  build = cfg.sourceUrl != null;

  hardening = {
    User = user;
    Group = user;
    NoNewPrivileges = true;
    PrivateTmp = true;
    PrivateDevices = true;
    ProtectSystem = "strict";
    ProtectHome = true;
    ProtectKernelTunables = true;
    ProtectKernelModules = true;
    ProtectControlGroups = true;
    RestrictAddressFamilies = [
      "AF_INET"
      "AF_INET6"
    ];
    RestrictNamespaces = true;
    LockPersonality = true;
    SystemCallFilter = [ "@system-service" ];
  };
in
{
  options.services.ropewiki.drainage = {
    enable = mkEnableOption "the drainage-area lookup that replaces the Luca server's waterflow request";

    package = mkOption {
      type = types.package;
      default = pkgs.rwDrainage;
      defaultText = lib.literalExpression "pkgs.rwDrainage";
      description = "See nix/packages/rw-drainage.nix.";
    };

    port = mkOption {
      type = types.port;
      default = 9002;
      description = "TCP port on 127.0.0.1 that nginx proxies `/luca/rwr` to. Never exposed.";
    };

    index = mkOption {
      type = types.path;
      default = "${stateDir}/nhdplus.gpkg";
      description = ''
        The index file `rw-drainage build` makes. The service starts as soon as it exists. To
        rebuild it (a new NHDPlus release, a changed builder), delete it and start
        `rw-drainage-index.service`.
      '';
    };

    sourceUrl = mkOption {
      type = types.nullOr types.str;
      default = "https://dmap-data-commons-ow.s3.amazonaws.com/NHDPlusV21/Data/NationalData/NHDPlusV21_NationalData_Seamless_Geodatabase_Lower48_07.7z";
      description = ''
        The NHDPlus V2.1 national geodatabase (a 7z archive) that `rw-drainage-index.service`
        downloads and turns into `index` when `index` does not exist. Needs about 25 GB of free
        space under /var/lib/rw-drainage while it runs and several GB of memory. `null` never
        builds: provide `index` yourself.
      '';
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = site.enable;
        message = "services.ropewiki.drainage adds a location to the site's nginx virtual host; enable services.ropewiki too.";
      }
    ];

    services.ropewiki.help.logs.drainage = {
      description = "The drainage-area lookup and the build of its index";
      units = [ "rw-drainage.service" ] ++ lib.optional build "rw-drainage-index.service";
    };

    users.users.${user} = {
      group = user;
      isSystemUser = true;
    };
    users.groups.${user} = { };

    # The page calls <site>/luca/rwr, the path the Luca server was proxied at. Anything else RWServer
    # did (PDF export, ...) gets a 404 from the service.
    services.nginx.virtualHosts.${serverName}.locations."= /luca/rwr".proxyPass = "http://${address}";

    # Started by the path unit when the index appears, so a host that is still building it has no
    # failed unit.
    systemd.services.rw-drainage = {
      description = "Drainage area of a point on a stream (the Luca server's waterflow lookup)";
      serviceConfig = hardening // {
        ExecStart = "${lib.getExe cfg.package} serve --index ${cfg.index} --host 127.0.0.1 --port ${toString cfg.port}";
        Restart = "on-failure";
        RestartSec = 5;
      };
    };
    systemd.paths.rw-drainage = {
      wantedBy = [ "multi-user.target" ];
      pathConfig.PathExists = cfg.index;
    };

    systemd.tmpfiles.rules = lib.optional build "d '${dirOf cfg.index}' 0755 ${user} ${user} - -";

    # Type=exec: switching to a configuration that starts this does not wait hours for it.
    # A network error ends the unit and the retry resumes the download (curl -C -).
    systemd.services.rw-drainage-index = mkIf build {
      description = "Build the NHDPlus index for rw-drainage";
      wantedBy = [ "multi-user.target" ];
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];
      unitConfig.ConditionPathExists = "!${cfg.index}";
      path = [
        pkgs.curl
        pkgs._7zz
        pkgs.findutils
        pkgs.coreutils
      ];
      serviceConfig = hardening // {
        Type = "exec";
        ReadWritePaths = [ (dirOf cfg.index) ];
        Restart = "on-failure";
        RestartSec = "10min";
        StartLimitIntervalSec = 0;
        TimeoutStopSec = 30;
        Nice = 10;
      };
      script = ''
        work=${dirOf cfg.index}/rw-drainage-work
        mkdir -p "$work"
        cd "$work"

        curl --fail --location --continue-at - --retry 3 --output nhdplus.7z '${cfg.sourceUrl}'
        rm -rf gdb && mkdir gdb
        7zz x -y -bso0 -bsp0 -ogdb nhdplus.7z
        rm nhdplus.7z

        # the geodatabase is a directory called *.gdb somewhere in the archive
        source=$(find gdb -type d -name '*.gdb' -print -quit)
        test -n "$source" || { echo "no .gdb directory in the archive" >&2; exit 1; }
        ${lib.getExe cfg.package} build "$source" --out ${cfg.index}
        chmod 0644 ${cfg.index}

        cd /
        rm -rf "$work"
      '';
    };
  };
}
