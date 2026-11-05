{
  inputs = {
    nixpkgs.url = "nixpkgs/nixos-unstable";

    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    impermanence = {
      url = "github:nix-community/impermanence";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
    };

    nixvim = {
      url = "github:nix-community/nixvim";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-flatpak.url = "github:gmodena/nix-flatpak";

    lanzaboote = {
      url = "github:nix-community/lanzaboote";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    wg-feed = {
      url = "github:Exeteres/wg-feed";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    exetrouter = {
      url = "github:mocki-toki/exetrouter/main";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
    };
  };

  outputs = inputs @ {
    self,
    nixpkgs,
    ...
  }: let
    system = "x86_64-linux";
    lib = nixpkgs.lib;
    pkgs = nixpkgs.legacyPackages.${system};
    privateModule = path:
      if builtins.pathExists path
      then path
      else
        throw ''
          Missing decrypted private module: ${toString path}
          Run scripts/with-private-nix with an authorized SOPS identity before evaluating private configuration.
          External consumers must use its local path input override.
        '';

    commonModules = [
      self.nixosModules.default
      self.nixosModules.secure-boot
    ];

    hostModules = [
      self.nixosModules.workstation
      self.nixosModules.workstation-private
      self.nixosModules.exeteres-workstation
      ./hosts/rebecca
      (privateModule ./hosts/rebecca/private.nix)
    ];

    bootstrapModules = [
      self.nixosModules.minimal
      self.nixosModules.exeteres-minimal
      ./hosts/rebecca/sops.nix
    ];
  in {
    lib = import ./lib;

    nixosModules = {
      default = {
        imports = [
          inputs.disko.nixosModules.disko
          inputs.impermanence.nixosModules.impermanence
          ./modules/common
        ];
      };

      minimal = {
        imports = [
          inputs.home-manager.nixosModules.home-manager
          ./modules/desktop/minimal.nix
        ];
        home-manager.sharedModules = [./modules/home/minimal.nix];
      };

      exeteres-shell = ./users/exeteres/shell.nix;
      exeteres-minimal = ./users/exeteres/minimal.nix;
      exeteres-workstation = ./users/exeteres/workstation.nix;

      secure-boot = {
        imports = [
          inputs.sops-nix.nixosModules.sops
          inputs.lanzaboote.nixosModules.lanzaboote
          ./modules/common/secure-boot.nix
        ];
      };

      workstation = {
        imports = [
          inputs.sops-nix.nixosModules.sops
          inputs.home-manager.nixosModules.home-manager
          inputs.wg-feed.nixosModules.wg-feed
          ./modules/desktop/workstation.nix
        ];

        home-manager.sharedModules = [
          inputs.nix-flatpak.homeManagerModules.nix-flatpak
          inputs.nixvim.homeModules.nixvim
          ./modules/home/workstation.nix
        ];
      };

      workstation-private = {
        imports = [
          (import (privateModule ./modules/desktop/workstation.private.nix) {inherit inputs;})
        ];
        home-manager.sharedModules = [(privateModule ./modules/home/programs/private.nix)];
      };
    };

    homeModules = {
      default = ./modules/home;
      minimal = ./modules/home/minimal.nix;
      workstation = ./modules/home/workstation.nix;
    };

    nixosConfigurations.rebecca = lib.nixosSystem {
      inherit system;
      modules = commonModules ++ hostModules;
    };

    apps.${system} = {
      rebecca-iso = self.lib.mkIsoInstaller {
        inherit nixpkgs pkgs;
        hostName = "rebecca";
        modules = commonModules ++ bootstrapModules;
        installer.configuration = self.nixosConfigurations.rebecca;
      };

      rebecca-kexec = self.lib.mkKexec {
        inherit nixpkgs pkgs;
        hostName = "rebecca";
        modules = commonModules ++ bootstrapModules;
        installer.configuration = self.nixosConfigurations.rebecca;
      };

      rebecca-update-secrets = self.lib.mkUpdateSecrets {
        inherit pkgs;
        secureBootFile = "hosts/rebecca/secrets/secure-boot-keys.yaml";
        tpmIdentityFile = "hosts/rebecca/secrets/age-tpm-identity";
        yubikeyIdentityFile = "hosts/rebecca/secrets/age-yubikey-identity";
      };
    };

    checks.${system} = import ./checks {
      inherit lib pkgs;
      config = self.nixosConfigurations.rebecca.config;
    };
  };
}
