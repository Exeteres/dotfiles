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

    commonModules = [
      self.nixosModules.default
      self.nixosModules.secure-boot
    ];

    hostModules = [
      self.nixosModules.workstation
      self.nixosModules.exeteres-workstation
      ./hosts/rebecca
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

        _module.args.exetrouter = inputs.exetrouter;

        home-manager.sharedModules = [
          inputs.nix-flatpak.homeManagerModules.nix-flatpak
          inputs.nixvim.homeModules.nixvim
          ./modules/home/workstation.nix
        ];
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

    checks.${system}.rebecca = self.nixosConfigurations.rebecca.config.system.build.toplevel;
  };
}
