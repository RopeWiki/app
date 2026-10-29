# services.ropewiki: the RopeWiki backend on one NixOS machine.
#
# Replaces the webserver and database containers of docker-compose.yaml:
#   nginx + php-fpm, MariaDB over a unix socket, Sphinx search, and a oneshot that migrates the
#   database on every start. TLS, firewalling and everything else are ordinary NixOS settings
#   (services.nginx.virtualHosts.<hostName>.enableACME, networking.firewall, ...); see
#   nix/README.md. What is not covered yet is listed in nix/TODO.md.
#
# MediaWiki itself is run by nixpkgs' services.mediawiki (php-fpm pool, database and user,
# generated settings, the mediawiki-init unit) with `webserver = "none"`: that module hardcodes
# /w/ and /wiki/ URLs, RopeWiki's are at the root, so the nginx virtual host is ours. Its
# `mediawiki-init` script is replaced and the `mediawiki-*` maintenance wrappers it installs do not
# work, both because nixpkgs' module is written for a newer MediaWiki than the 1.39 this site
# runs; see "After the MediaWiki upgrade" in nix/TODO.md.
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
    mkDefault
    types
    ;

  cfg = config.services.ropewiki;

  # services.mediawiki fixes the user, group and database name (with its local database) and the
  # state and cache directories.
  user = "mediawiki";
  dbName = "mediawiki";
  stateDir = "/var/lib/mediawiki";
  cacheDir = "/var/cache/mediawiki";
  # services.mediawiki's copy of the site tree, with the tool paths fixed up.
  root = "${config.services.mediawiki.finalPackage}/share/mediawiki";
  dbSocket = "/run/mysqld/mysqld.sock";

  # hostName may carry a port ("localhost:8443"); nginx wants the bare name.
  serverName = builtins.head (lib.splitString ":" cfg.hostName);
  vhost = config.services.nginx.virtualHosts.${serverName};
  https = vhost.forceSSL || vhost.addSSL || vhost.onlySSL;

  production = cfg.mode == "production";

  # Image proxy mode (https://github.com/RopeWiki/app/wiki/Image-Proxy-Mode): the live site's 70 GB
  # of uploads, read through instead of copied.
  proxyUrl = lib.removeSuffix "/" cfg.imageProxy;
  # With a resolver configured (services.nginx.resolver.addresses), nginx looks the host up when a
  # file is requested; without one, when it starts (and then it does not start without DNS).
  proxyAtRequest = config.services.nginx.resolver.addresses != [ ];
  proxyHost = builtins.head (
    lib.splitString "/" (lib.removePrefix "https://" (lib.removePrefix "http://" proxyUrl))
  );

  # The only PHP files that may be executed from the web: MediaWiki's own entry points and the
  # one script this repository adds. Everything else (extension and maintenance files, the
  # installer in mw-config/, LocalSettings.php, ...) answers 404.
  phpEntryPoints = "index|load|api|rest|thumb|thumb_handler|opensearch_desc|img_auth|kml_to_gpx";

  # Programs MediaWiki and its extensions run: thumbnails, PDFs, KML to GPX, diffs.
  runtimePath = with pkgs; [
    imagemagick
    ghostscript
    poppler-utils
    gpsbabel
    diffutils
    coreutils
  ];

  # The immutable site tree reads its configuration from PHP files named in the environment:
  # the settings services.mediawiki generates (MEDIAWIKI_CONFIG, plus `siteSettings` below as its
  # extraConfig) before the repo's LocalSettings.php, and `overrides` after it (the repo file
  # hardcodes Docker paths such as /usr/bin/convert).
  phpFile =
    name: text:
    pkgs.writeTextFile {
      inherit name text;
      checkPhase = ''${cfg.phpPackage}/bin/php --syntax-check "$target"'';
    };

  # What system_start.sh and SiteSpecificSettings.php.template produced in the Docker image that
  # services.mediawiki does not (name, URL, database and secret key it does).
  siteSettings = ''
    $wgMetaNamespace = "Ropewiki";
    $wgLogo = "$wgServer/Ropewiki.png";
    $semanticServer = "${cfg.hostName}";

    # Only used by the web updater, which is unreachable without shell access anyway.
    $wgUpgradeKey = substr( hash( 'sha256', "upgrade" . $wgSecretKey ), 0, 16 );

    # The generated settings differ from MediaWiki's defaults here, and the repo's
    # LocalSettings.php (which comes after) does not set them.
    $wgPingback = false;
    $wgAuthenticationTokenVersion = null;
  '';

  overrides = phpFile "ropewiki-overrides.php" ''
    <?php
    $wgUploadDirectory = "${cfg.imagesDir}";
    $wgCacheDirectory  = "${cacheDir}";
    # SMW writes .smw.json (setup state) next to its code by default; the store is read-only.
    $smwgConfigFileDir = "${stateDir}/smw";

    $wgImageMagickConvertCommand = "${pkgs.imagemagick}/bin/convert";
    $wgDiff3 = "${pkgs.diffutils}/bin/diff3";
    $wgScribuntoEngineConf['luastandalone']['luaPath'] = "${pkgs.lua5_1}/bin/lua";

    # Mail goes to an MTA on this machine (the Docker setup used a postfix relay container).
    $wgSMTP = [ 'host' => "localhost", 'port' => 25, 'auth' => false ];

    ${lib.optionalString (cfg.imageProxy != null) ''
      # Image proxy mode: URLs of uploaded files and thumbnails point at the other site, and
      # thumbnails are not generated here (there are no files to read them from).
      $wgUploadPath = "${proxyUrl}/images";
      $wgThumbPath = "${proxyUrl}/images/thumb";
      $wgGenerateThumbnailOnParse = false;
    ''}
    ${lib.optionalString (!cfg.search.enable) ''
      $wgSearchType = null;
      $wgEnableSphinxPrefixSearch = false;
    ''}
    ${lib.optionalString production "require \"${../php/production.php}\";"}
    ${cfg.extraSettings}
  '';

  # What php-fpm adds to services.mediawiki's own environment (MEDIAWIKI_CONFIG).
  poolEnv = {
    ROPEWIKI_OVERRIDES = "${overrides}";
    ROPEWIKI_IMAGES_DIR = cfg.imagesDir;
    PATH = lib.makeBinPath runtimePath;
  };
  # Everything PHP needs to know when it runs outside php-fpm: maintenance scripts, the units below.
  phpEnv = poolEnv // {
    inherit (config.services.phpfpm.pools.mediawiki.phpEnv) MEDIAWIKI_CONFIG;
  };

  # `ropewiki-maintenance update.php --quick`, run as the service user. Scripts of extensions
  # (rebuildData.php, ...) are found by name too.
  maintenance = pkgs.writeShellScriptBin "ropewiki-maintenance" ''
    if [ $# -lt 1 ]; then
      echo "usage: ropewiki-maintenance <script.php> [args...]   (core and extension maintenance scripts)" >&2
      exit 1
    fi
    script=$1; shift
    for dir in ${root}/maintenance ${root}/extensions/*/maintenance; do
      if [ -e "$dir/$script" ]; then path=$dir/$script; break; fi
    done
    if [ -z "''${path:-}" ]; then
      echo "ropewiki-maintenance: no maintenance script called $script" >&2
      exit 1
    fi
    become=()
    if [ "$(id -un)" != ${user} ]; then
      become=(/run/wrappers/bin/sudo -u ${user} --)
    fi
    exec "''${become[@]}" ${pkgs.coreutils}/bin/env \
      ${lib.concatStringsSep " " (lib.mapAttrsToList (k: v: "${k}=${lib.escapeShellArg v}") phpEnv)} \
      ${cfg.phpPackage}/bin/php -d memory_limit=-1 "$path" "$@"
  '';

  # `ropewiki-import export.xml...`: load Special:Export / dumpBackup.php files, then bring
  # Semantic MediaWiki's tables and the job queue up to date (what a page edit would have done).
  importer = pkgs.writeShellScriptBin "ropewiki-import" ''
    set -e
    if [ $# -lt 1 ]; then
      echo "usage: ropewiki-import export.xml [more.xml ...]" >&2
      exit 1
    fi
    for file in "$@"; do
      ${maintenance}/bin/ropewiki-maintenance importDump.php < "$file"
    done
    ${maintenance}/bin/ropewiki-maintenance rebuildData.php
    ${maintenance}/bin/ropewiki-maintenance runJobs.php
  '';

  # --- Sphinx ----------------------------------------------------------------------------

  sphinx = pkgs.sphinxsearch;

  # The repo's sphinx.conf with what system_start.sh substituted at start-up done at build time.
  sphinxConf = pkgs.runCommand "ropewiki-sphinx.conf" { } ''
    sed -E \
      -e 's|\{\{WG_DB_SERVER\}\}|localhost|' \
      -e 's|\{\{WG_DB_USER\}\}|${user}|' \
      -e 's|^(\s*sql_db\s*=\s*)ropewiki\s*$|\1${dbName}|' \
      -e 's|\{\{WG_DB_PASSWORD\}\}||' \
      -e 's|^\s*#\s*sql_sock\s*=.*|sql_sock = ${dbSocket}|' \
      -e 's|/var/log/sphinxsearch/searchd.pid|/run/ropewiki-sphinx/searchd.pid|' \
      -e 's|^(\s*pid_file\s*=.*)$|\1\n\n\t# Binary logs are only for RT indexes, and the default path is inside the read-only\n\t# Nix store (searchd dies with "failed to open .../var/data/binlog.lock"). Empty disables.\n\tbinlog_path =|' \
      -e 's|/var/log/sphinxsearch|/var/log/ropewiki-sphinx|' \
      -e 's|/var/data/sphinx|${stateDir}/sphinx|' \
      ${cfg.package.sphinxConfTemplate} > $out
    # Fail loudly if the repo's template changes shape.
    grep -q '^\s*sql_sock\s*=' $out
    grep -q '^\s*sql_db\s*=\s*${dbName}$' $out
    grep -q '${stateDir}/sphinx/wiki_main' $out
    grep -q '^\s*binlog_path\s*=\s*$' $out
  '';

  sphinxUnit = {
    User = user;
    Group = user;
    RuntimeDirectory = "ropewiki-sphinx";
    RuntimeDirectoryPreserve = true;
    LogsDirectory = "ropewiki-sphinx";
  };
in
{
  options.services.ropewiki = {
    enable = mkEnableOption "the RopeWiki site (MediaWiki + Semantic MediaWiki)";

    package = mkOption {
      type = types.package;
      default = pkgs.ropewiki;
      defaultText = lib.literalExpression "pkgs.ropewiki";
      description = "The assembled site tree, see nix/packages/ropewiki.nix.";
    };

    phpPackage = mkOption {
      type = types.package;
      default = pkgs.php83.buildEnv {
        extensions = { all, enabled }: enabled ++ [ all.apcu ];
        extraConfig = "memory_limit = 256M";
      };
      defaultText = lib.literalExpression "pkgs.php83.buildEnv { ... apcu }";
      description = "PHP used by php-fpm and maintenance scripts (APCu is MediaWiki's main cache).";
    };

    mode = mkOption {
      type = types.enum [
        "production"
        "development"
      ];
      default = "production";
      description = ''
        `production` hides errors from visitors (errors go to the journal) and hides what is
        running: no `X-Powered-By`, generator tag or "Powered by" icons, `Special:Version` only for
        logged-in users, no exception details, no release notes or `composer.json` served.
        `development` keeps the verbose behaviour of the Docker setup: errors and deprecations are
        printed into the page.
      '';
    };

    hostName = mkOption {
      type = types.str;
      default = "localhost";
      example = "ropewiki.com";
      description = ''
        Public host name, with `:port` if it is not the default for the scheme (`WG_HOSTNAME`).
        The scheme is https when `services.nginx.virtualHosts.<hostName>` has `forceSSL`,
        `addSSL` or `onlySSL` set.
      '';
    };

    robots = mkOption {
      type = types.enum [
        "dev"
        "prod"
      ];
      default = "dev";
      description = "Which webserver/robots/robots_*.txt to serve (`RW_ROBOTS`).";
    };

    imagesDir = mkOption {
      type = types.path;
      default = "${stateDir}/images";
      description = "Uploaded files (the `IMAGES_FOLDER` volume), served as /images.";
    };

    search.enable = mkOption {
      type = types.bool;
      default = true;
      description = "Run Sphinx for site search (SphinxSearch extension).";
    };

    sitePages = mkOption {
      type = types.nullOr types.package;
      default = pkgs.ropewikiSitePages;
      defaultText = lib.literalExpression "pkgs.ropewikiSitePages";
      description = ''
        Directory of wiki pages, one file per page named by its title (`MediaWiki:Common.js`,
        `MediaWiki:Common.css`, ...), that `ropewiki-pages.service` writes into the wiki on every
        start. By default the site's JavaScript and CSS from the `commonjs` and `commoncss` flake
        inputs. A page edited by hand is overwritten the next time the service runs. `null` leaves
        the pages alone (an imported database keeps its own).
      '';
    };

    imageProxy = mkOption {
      type = types.nullOr (types.strMatching "https?://[^/]+/?");
      default = null;
      example = "https://ropewiki.com";
      description = ''
        Development only: show the uploaded files of another site instead of this one's (which has
        none). MediaWiki then links files and thumbnails to `<imageProxy>/images`, and nginx
        answers requests for `/images/...` that MediaWiki does not know about (paths written into
        page text) by fetching them from there. Read-only: uploads still work but the files are
        not shown. By default the host name is resolved when nginx starts, so nginx does not start
        without DNS; set `services.nginx.resolver.addresses` to resolve it when a file is
        requested instead. The other site may refuse a server-side request (ropewiki.com puts Cloudflare's
        browser check in front of everything, /images/ included); MediaWiki's own links, which the
        browser fetches itself, work regardless. See nix/docs/image-proxy.md.
      '';
    };

    openFirewall = mkOption {
      type = types.bool;
      default = false;
      description = "Open TCP ports 80 and 443.";
    };

    extraSettings = mkOption {
      type = types.lines;
      default = "";
      description = "PHP appended after everything else (a late `LocalSettings.php`).";
    };
  };

  config = mkIf cfg.enable {
    # --- MediaWiki ----------------------------------------------------------------------
    services.mediawiki = {
      enable = true;
      package = cfg.package;
      phpPackage = cfg.phpPackage;
      name = "ropewiki";
      url = "${if https then "https" else "http"}://${cfg.hostName}";
      webserver = "none";
      extraConfig = siteSettings;
      # The repo's LocalSettings.php loads the skin it uses; the module's MonoBook and Timeless
      # are not wanted.
      skins = lib.mkForce { };
      # Uploads: the module would `chown -R` the folder on every boot, which is minutes with 70 GB
      # of files; imagesDir is created below and $wgUploadDirectory is set in the overrides.
      uploadsDir = null;
      # Only read by the module's own mediawiki-init script, which is replaced below. The first
      # administrator comes from the installer, see nix/vm/dev-site.nix.
      passwordFile = "/dev/null";
      # php-fpm: mirrors webserver/fpm-pool.conf and the sed edits in webserver/Dockerfile /
      # system_start.sh. (With webserver = "none" the module would hand the socket to mediawiki
      # itself.)
      poolConfig = {
        "listen.owner" = config.services.nginx.user;
        "listen.group" = config.services.nginx.group;
        pm = "ondemand";
        "pm.max_children" = 16;
        "pm.process_idle_timeout" = "10s";
        "pm.max_requests" = 200;
        request_terminate_timeout = "30s";
        # PHP's own error log lines go to the journal (phpfpm-mediawiki.service).
        catch_workers_output = true;
        decorate_workers_output = false;
      };
    };

    users.users.${user}.home = stateDir;
    # nginx serves the uploaded files from imagesDir, inside the 0750 state directory.
    users.users.${config.services.nginx.user}.extraGroups = [ user ];

    # The state and cache directories are services.mediawiki's.
    systemd.tmpfiles.rules = [
      "d '${stateDir}/smw' 0750 ${user} ${user} - -"
      "d '${stateDir}/sphinx' 0750 ${user} ${user} - -"
      # Not recursive: the uploads folder can be huge and is restored from backups.
      "d '${cfg.imagesDir}' 0755 ${user} ${user} - -"
      # On btrfs, copy-on-write makes database files slow (every page write allocates a new extent)
      # and InnoDB checksums its own pages anyway, so MariaDB's data directory is NOCOW. The flag
      # applies to files created after it is set, so a database that already exists keeps its COW
      # files (nix/docs/backups.md says how to convert them). Snapshots still work: the first write
      # to a block after a snapshot is copied once. Other filesystems ignore the flag.
      "h '${config.services.mysql.dataDir}' - - - - +C"
    ];

    warnings =
      lib.optional (cfg.imageProxy != null && production)
        "services.ropewiki.imageProxy is a development mode; with mode = \"production\" every visitor's file requests go to ${proxyUrl}.";

    # Without a resolver, nginx resolves the proxied host name when it starts.
    systemd.services.nginx = mkIf (cfg.imageProxy != null && !proxyAtRequest) {
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];
    };

    # --- database -----------------------------------------------------------------------
    # services.mediawiki (database.createLocally) creates the `mediawiki` database and user, with
    # unix-socket authentication as the `mediawiki` OS user: no password anywhere.

    # --- php-fpm ------------------------------------------------------------------------
    # The pool is services.mediawiki's (poolConfig above).
    services.phpfpm.settings = {
      emergency_restart_threshold = mkDefault 10;
      emergency_restart_interval = mkDefault "1m";
      process_control_timeout = mkDefault "10s";
    };
    services.phpfpm.pools.mediawiki = {
      phpEnv = poolEnv;
      phpOptions = {
        upload_max_filesize = "10M";
        post_max_size = "10M";
        "opcache.enable" = 1;
        "opcache.memory_consumption" = 128;
        "opcache.interned_strings_buffer" = 8;
        "opcache.max_accelerated_files" = 10000;
        log_errors = 1;
        html_errors = 0;
        display_errors = if production then 0 else 1;
      }
      // lib.optionalAttrs production {
        expose_php = 0;
        "session.cookie_httponly" = 1;
        "session.use_strict_mode" = 1;
        "session.cookie_secure" = if https then 1 else 0;
      };
    };
    systemd.services.phpfpm-mediawiki = {
      after = [ "mediawiki-init.service" ];
      requires = [ "mediawiki-init.service" ];
    };

    # --- nginx --------------------------------------------------------------------------
    # Mirrors webserver/nginx/sites-enabled/ropewiki.com. TLS is the host's business:
    # set enableACME/forceSSL/... on services.nginx.virtualHosts.<hostName>.
    services.nginx = {
      enable = true;
      recommendedGzipSettings = mkDefault true;
      recommendedOptimisation = mkDefault true;
      virtualHosts.${serverName} = {
        default = true;
        root = root;
        extraConfig = ''
          index index.php index.html index.htm;
          # 1M over the PHP limit so PHP/MediaWiki can answer with a friendly error.
          client_max_body_size 11M;
        '';
        locations = {
          "/".tryFiles = "$uri $uri/ @rewrite";
          "@rewrite".extraConfig = ''
            rewrite ^/(.*)$ /index.php?title=$1&$args;
          '';
          "~ \\.php$".extraConfig = ''
            if ($uri !~ "^/(${phpEntryPoints})\.php$") { return 404; }
            fastcgi_hide_header X-Powered-By;
            fastcgi_split_path_info ^(.+\.php)(/.+)$;
            fastcgi_pass unix:${config.services.phpfpm.pools.mediawiki.socket};
            fastcgi_index index.php;
            include ${config.services.nginx.package}/conf/fastcgi.conf;
          '';
          # Code that has no business being fetched over HTTP, and files that name versions.
          "~ ^/(maintenance|includes|languages|tests|docs|vendor|cache|serialized|mw-config)(/|$)".return =
            "404";
          "~ ^/(composer\\.(json|lock)|.*/(extension|skin)\\.json)$".return = "404";
          # ^~ so that nothing uploaded can ever reach the .php location above.
          "^~ /images/" =
            if cfg.imageProxy == null then
              { alias = "${cfg.imagesDir}/"; }
            else
              {
                # A variable makes nginx resolve the name per request (with the resolver), and
                # sends the request's own URI, which is /images/... on the other site too.
                proxyPass = if proxyAtRequest then "$image_upstream" else "${proxyUrl}/images/";
                extraConfig = ''
                  ${lib.optionalString proxyAtRequest "set $image_upstream ${proxyUrl};"}
                  limit_except GET HEAD { deny all; }
                  proxy_set_header Host ${proxyHost};
                  # This site's login cookies are none of the other site's business.
                  proxy_set_header Cookie "";
                  ${lib.optionalString (lib.hasPrefix "https://" proxyUrl) ''
                    # Handle proxying https requests to a different hostname properly, and check
                    # that it is that host's certificate.
                    proxy_ssl_server_name on;
                    proxy_ssl_name ${proxyHost};
                    proxy_ssl_verify on;
                    proxy_ssl_trusted_certificate ${config.security.pki.caBundle};
                  ''}
                '';
              };
          "= /robots.txt".alias = "${cfg.package.robotsDir}/robots_${cfg.robots}.txt";
        };
      };
    };
    networking.firewall.allowedTCPPorts = mkIf cfg.openFirewall [
      80
      443
    ];

    # --- schema migrations --------------------------------------------------------------
    # services.mediawiki's unit, with its script replaced: the module's installs MediaWiki into an
    # empty database through maintenance/run.php, which 1.39 does not have (nix/vm/dev-site.nix
    # installs a development database itself, a real site restores a backup). What is left is
    # the secret key and the migration.
    systemd.services.mediawiki-init = {
      requires = [ "mysql.service" ];
      path = [ cfg.phpPackage ] ++ runtimePath;
      environment = removeAttrs phpEnv [ "PATH" ];
      serviceConfig.RemainAfterExit = true;
      script = lib.mkForce ''
        if ! test -e ${stateDir}/secret.key; then
          install -m 0600 /dev/null ${stateDir}/secret.key
          tr -dc A-Za-z0-9 </dev/urandom 2>/dev/null | head -c 64 > ${stateDir}/secret.key
        fi
        # Same as `maintenance/update.php --quick` in .github/workflows/test-empty-site.yml;
        # for SMW this also (re)creates its tables.
        php -d memory_limit=-1 ${root}/maintenance/update.php --quick
      '';
    };

    # --- site JavaScript and CSS ---------------------------------------------------------
    # What commonjs/upload.py and commoncss/upload.py do over the API, from the store instead. A
    # page whose text is unchanged gets no new revision, so running this on every start is free.
    # The unit changes whenever the pages do, so a `switch` that brings new ones runs it again.
    systemd.services.ropewiki-pages = mkIf (cfg.sitePages != null) {
      description = "Publish the site JavaScript and CSS as MediaWiki: pages";
      wantedBy = [ "multi-user.target" ];
      after = [ "mediawiki-init.service" ];
      requires = [ "mediawiki-init.service" ];
      path = [
        cfg.phpPackage
        config.services.mysql.package
      ]
      ++ runtimePath;
      environment = removeAttrs phpEnv [ "PATH" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = user;
        Group = user;
        PrivateTmp = true;
      };
      script = ''
        for page in ${cfg.sitePages}/*; do
          php -d memory_limit=-1 ${root}/maintenance/edit.php \
            -u 'RopeWiki deploy' -s 'nix sync' --bot "$(basename "$page")" < "$page"
        done

        # upload.py's orphan check: report, never delete.
        comm -23 \
          <(mariadb --socket=${dbSocket} ${dbName} -N -e "SELECT CONCAT('MediaWiki:', page_title) FROM page WHERE page_namespace = 8 AND page_title LIKE 'Common%'" | tr _ ' ' | sort) \
          <(ls ${cfg.sitePages} | tr _ ' ' | sort) \
          | sed 's/^/not in the build, left alone: /'
      '';
    };

    # --- Sphinx search ---------------------------------------------------------------------
    systemd.services.ropewiki-searchd = mkIf cfg.search.enable {
      description = "Sphinx search daemon for RopeWiki";
      wantedBy = [ "multi-user.target" ];
      after = [ "mediawiki-init.service" ];
      requires = [ "mediawiki-init.service" ];
      serviceConfig = sphinxUnit // {
        # system_start.sh builds the indexes once before starting searchd, and restarts it if it dies.
        ExecStartPre = pkgs.writeShellScript "ropewiki-sphinx-first-index" ''
          if ! test -e ${stateDir}/sphinx/wiki_main.spi; then
            ${sphinx}/bin/sphinxsearch-indexer --config ${sphinxConf} --all
          fi
        '';
        ExecStart = "${sphinx}/bin/sphinxsearch-searchd --nodetach --config ${sphinxConf}";
        Restart = "always";
        RestartSec = 2;
      };
    };
    # webserver/html/ropewiki/extensions/SphinxSearch/sphinx.cron: every 30 minutes.
    systemd.services.ropewiki-sphinx-reindex = mkIf cfg.search.enable {
      description = "Rebuild RopeWiki Sphinx indexes";
      after = [ "mediawiki-init.service" ];
      requires = [ "mediawiki-init.service" ];
      serviceConfig = sphinxUnit // {
        Type = "oneshot";
        ExecStart = "${sphinx}/bin/sphinxsearch-indexer --rotate --config ${sphinxConf} --all";
      };
    };
    systemd.timers.ropewiki-sphinx-reindex = mkIf cfg.search.enable {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "*:0/30";
        Persistent = true;
      };
    };

    environment.systemPackages = [
      maintenance
      importer
    ];
  };
}
