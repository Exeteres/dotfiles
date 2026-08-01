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

    wg-feed = {
      url = "github:Exeteres/wg-feed";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs: {
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
      workstation = {
        imports = [
          inputs.sops-nix.nixosModules.sops
          inputs.home-manager.nixosModules.home-manager
          ./modules/desktop/workstation.nix
        ];

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
  };
}
