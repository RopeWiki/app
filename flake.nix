{
  description = "RopeWiki: MediaWiki + Semantic MediaWiki stack, packaged for NixOS";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  # The wiki's JavaScript and CSS live in their own repositories and are published as
  # MediaWiki: pages; `nix flake update commonjs commoncss` takes new versions.
  inputs.commonjs = {
    url = "github:RopeWiki/commonjs";
    flake = false;
  };
  inputs.commoncss = {
    url = "github:RopeWiki/commoncss";
    flake = false;
  };

  outputs =
    {
      self,
      nixpkgs,
      commonjs,
      commoncss,
    }:
    let
      inherit (nixpkgs) lib;

      overlay = final: _prev: {
        # MediaWiki core and the extensions webserver/Dockerfile clones; see mediawiki-pins.json.
        mediawikiExtensions = final.callPackage ./nix/packages/mediawiki-ext.nix { };
        ropewikiSitePages = final.callPackage ./nix/packages/site-pages.nix { inherit commonjs commoncss; };
        ropewiki = final.callPackage ./nix/packages/ropewiki.nix {
          repoRoot = ./.;
          codebaseVersion = self.rev or self.dirtyRev or "unknown";
        };
      };

      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems =
        f:
        lib.genAttrs systems (
          system:
          f (
            import nixpkgs {
              inherit system;
              overlays = [ overlay ];
            }
          )
        );
      # The VM and the tests are x86_64 machines.
      x86Only = pkgs: lib.optionalAttrs (pkgs.stdenv.hostPlatform.system == "x86_64-linux");

      build = self.nixosConfigurations.ropewiki-vm.config.system.build;

      # Every file in nix/tests is a NixOS VM test and becomes `checks.<system>.<file name>`.
      mkTest =
        pkgs: file:
        pkgs.testers.runNixOSTest {
          imports = [ file ];
          node.pkgsReadOnly = false; # the module adds an overlay
          defaults.imports = [ self.nixosModules.default ];
        };
      testFiles = lib.filterAttrs (name: type: type == "regular" && lib.hasSuffix ".nix" name) (
        builtins.readDir ./nix/tests
      );
    in
    {
      overlays.default = overlay;

      # `services.ropewiki.*`, usable from any NixOS configuration:
      #   imports = [ ropewiki.nixosModules.default ];
      nixosModules.default = {
        imports = [
          ./nix/modules/ropewiki.nix
          ./nix/modules/backup.nix
        ];
        nixpkgs.overlays = [ overlay ];
      };

      # A ready-to-boot machine running the site; see nix/vm.
      nixosConfigurations.ropewiki-vm = lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          self.nixosModules.default
          ./nix/vm/configuration.nix
        ];
      };

      packages = forAllSystems (
        pkgs:
        {
          default = pkgs.ropewiki;
          inherit (pkgs) ropewiki;
          inherit (pkgs.ropewiki.passthru) composerVendor;
          site-pages = pkgs.ropewikiSitePages;
          mediawiki-extensions = pkgs.mediawikiExtensions;
          update-mediawiki-ext = pkgs.mediawikiExtensions.updateScript;
        }
        // x86Only pkgs {
          vm = build.vm; # `nix run .#vm`: https://localhost:8443 (self-signed)
          image = build.images.qemu; # `nix build .#image`: a bootable qcow2 disk
        }
      );

      apps = forAllSystems (
        pkgs:
        {
          # Re-pin MediaWiki and its extensions: `nix run .#update-mediawiki-ext`
          update-mediawiki-ext = {
            type = "app";
            program = lib.getExe pkgs.mediawikiExtensions.updateScript;
            meta.description = "Re-pin MediaWiki core and the git-cloned extensions";
          };
        }
        // x86Only pkgs {
          vm = {
            type = "app";
            program = "${build.vm}/bin/run-ropewiki-vm-vm";
            meta.description = "Boot the site in a VM: https://localhost:8443";
          };
        }
      );

      checks = forAllSystems (
        pkgs:
        x86Only pkgs (
          lib.mapAttrs' (
            name: _: lib.nameValuePair (lib.removeSuffix ".nix" name) (mkTest pkgs ./nix/tests/${name})
          ) testFiles
        )
      );

      devShells = forAllSystems (pkgs: {
        # Tools for maintaining the Nix packaging (e.g. regenerating composer.lock).
        default = pkgs.mkShell {
          packages = with pkgs; [
            php83
            php83Packages.composer
            nixfmt
            jq
          ];
        };
      });

      formatter = forAllSystems (pkgs: pkgs.nixfmt);
    };
}
