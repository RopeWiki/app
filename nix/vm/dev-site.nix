# What a VM, a test or a local checkout needs on top of services.ropewiki, and a production host
# does not: a database that starts from the empty schema, and a self-signed certificate. Kept out
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

  # `deploy_tool.py restore_empty_db`: load database/empty_schema.sql into a database without tables.
  systemd.services.ropewiki-empty-schema = {
    description = "Load the empty RopeWiki schema into a new database";
    wantedBy = [ "multi-user.target" ];
    after = [ "mysql.service" ];
    requires = [ "mysql.service" ];
    before = [ "ropewiki-init.service" ];
    path = [ config.services.mysql.package ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      User = "ropewiki";
    };
    script = ''
      db="mariadb --socket=/run/mysqld/mysqld.sock --batch --skip-column-names ropewiki"
      tables=$($db -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'ropewiki'")
      if [ "$tables" = 0 ]; then
        $db < ${site.package.emptySchema}
      fi
    '';
  };
  systemd.services.ropewiki-init.requires = [ "ropewiki-empty-schema.service" ];
}
