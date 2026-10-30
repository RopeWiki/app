# A self-contained machine running the site, for `nix run .#vm` and `nix build .#image`.
#
# The VM forwards https://localhost:8443 (and plain http://localhost:8080) to the guest and starts
# from the empty development database with a self-signed certificate, so the browser will warn.
# The login for the console is root / root.
{ lib, ... }:
{
  imports = [ ./dev-site.nix ];

  system.stateVersion = "25.11";
  networking.hostName = "ropewiki-vm";

  services.ropewiki = {
    enable = true;
    # Like docker-compose.yaml's default WG_HOSTNAME for local development, but over TLS.
    hostName = "localhost:8443";
    # Show PHP errors and deprecations in the page, like the Docker setup did.
    mode = "development";
    openFirewall = true;
  };
  # Serve both: the redirect NixOS emits would drop the :8443 and send browsers to port 443.
  services.nginx.virtualHosts.localhost = {
    forceSSL = false;
    addSSL = true;
  };

  users.users.root.initialPassword = "root";
  services.getty.autologinUser = "root";
  services.openssh.enable = true;

  # Placeholders so that the configuration is complete on its own (`nix flake check` evaluates it);
  # the VM runner and the image builders bring their own disks and bootloader.
  fileSystems."/" = lib.mkDefault {
    device = "/dev/disk/by-label/nixos";
    fsType = "ext4";
  };
  boot.loader.grub.devices = lib.mkDefault [ "nodev" ];

  # `nix run .#vm` (system.build.vm)
  virtualisation.vmVariant.virtualisation = {
    memorySize = 2048;
    cores = 2;
    graphics = false;
    forwardPorts = [
      {
        from = "host";
        host.port = 8080;
        guest.port = 80;
      }
      {
        from = "host";
        host.port = 8443;
        guest.port = 443;
      }
      # Not 22: QEMU runs as the user, who can't bind a privileged port.
      #   ssh -p 2222 root@localhost   (password: root)
      {
        from = "host";
        host.port = 2222;
        guest.port = 22;
      }
    ];
  };
  # Only the `nix run .#vm` variant takes passwords: the image and the tests keep sshd's defaults.
  virtualisation.vmVariant.services.openssh.settings = {
    PermitRootLogin = "yes";
    PasswordAuthentication = true;
  };

  # Image proxy mode (nix/docs/image-proxy.md) is deliberately off here until it is validated: an
  # imported page only shows the live site's images if the database also knows those files, and
  # the test imports have none. To try it, add to this block:
  #   services.ropewiki.imageProxy = "https://ropewiki.com";
  #   services.nginx.resolver = { addresses = [ "10.0.2.3" ]; ipv6 = false; };
  # (10.0.2.3 is QEMU's DNS forwarder; with it nginx starts without a network.)

  # `nix build .#image` (system.build.images.qemu): a qcow2 disk for any QEMU/KVM host.
  virtualisation.diskSize = 8 * 1024;
}
