# What a VM, a test or a local checkout needs on top of services.ropewiki, and a production host
# does not: a database that is installed on first start, and a self-signed certificate. Kept out
# of the module so it only has to describe a real deployment.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  site = config.services.ropewiki;
  serverName = builtins.head (lib.splitString ":" site.hostName);

  cert = pkgs.runCommand "ropewiki-dev-cert" { nativeBuildInputs = [ pkgs.openssl ]; } ''
    mkdir $out
    openssl req -x509 -newkey rsa:2048 -nodes -days 36500 \
      -keyout $out/key.pem -out $out/cert.pem \
      -subj /CN=${serverName} -addext subjectAltName=DNS:${serverName}
  '';
in
{
  # Redirect HTTP to HTTPS unless the host decides otherwise (e.g. a VM with forwarded ports).
  services.nginx.virtualHosts.${serverName} = {
    forceSSL = lib.mkDefault true;
    sslCertificate = "${cert}/cert.pem";
    sslCertificateKey = "${cert}/key.pem";
  };

  # A new database gets MediaWiki's own installer: core tables, the Admin user and a default front
  # page. Extension tables (SMW and the rest) and later schema changes are ropewiki-init's job.
  # install.php refuses to run when a LocalSettings.php exists and would write its own, so it
  # looks for one at a path that is not there and writes the result to a directory that is thrown
  # away (the site's settings come from the module, see siteSettings in modules/ropewiki.nix).
  systemd.services.ropewiki-install = {
    description = "Install MediaWiki into a new RopeWiki database";
    wantedBy = [ "multi-user.target" ];
    after = [ "mysql.service" ];
    requires = [ "mysql.service" ];
    before = [ "ropewiki-init.service" ];
    path = [
      config.services.mysql.package
      site.phpPackage
    ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      User = "ropewiki";
      RuntimeDirectory = "ropewiki-install";
    };
    script = ''
      socket=/run/mysqld/mysqld.sock
      tables=$(mariadb --socket=$socket --batch --skip-column-names ropewiki \
        -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'ropewiki'")
      if [ "$tables" = 0 ]; then
        # The password is replaced by ropewiki-dev-admin below: the installer applies the
        # default password policy, which "admin" does not satisfy.
        tr -dc A-Za-z0-9 </dev/urandom 2>/dev/null | head -c 32 > $RUNTIME_DIRECTORY/password
        MW_CONFIG_FILE=$RUNTIME_DIRECTORY/no-such-LocalSettings.php \
          php -d memory_limit=-1 ${site.package}/share/ropewiki/maintenance/install.php \
            --dbtype mysql --dbserver localhost:$socket --dbname ropewiki --dbuser ropewiki \
            --scriptpath "" --lang en \
            --passfile $RUNTIME_DIRECTORY/password --confpath $RUNTIME_DIRECTORY \
            ropewiki Admin
      fi
    '';
  };
  systemd.services.ropewiki-init.requires = [ "ropewiki-install.service" ];

  # A sysop login for poking around: Admin / admin. The default password policy refuses a
  # password like that (too short, same as the user name, in the common list), and so do the ones for sysop and
  # bureaucrat, so every policy is dropped.
  services.ropewiki.extraSettings = ''
    $wgPasswordPolicy['policies'] = [ 'default' => [] ];
  '';
  systemd.services.ropewiki-dev-admin = {
    description = "Give the development site an Admin user with the password admin";
    wantedBy = [ "multi-user.target" ];
    after = [ "ropewiki-init.service" ];
    requires = [ "ropewiki-init.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      maintenance=/run/current-system/sw/bin/ropewiki-maintenance
      $maintenance createAndPromote.php --force --sysop --bureaucrat Admin admin
      $maintenance changePassword.php --user=Admin --password=admin
    '';
  };
}
