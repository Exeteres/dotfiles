{
  config,
  lib,
  pkgs,
  ...
}: {
  imports = [
    ./minimal.nix
    ./other/boot.nix
    ./other/i18n.nix
    ./other/sound.nix
    ./other/timezone.nix
    ./other/vpn.nix
    ./other/smartcard.nix
  ];

  services.flatpak.enable = true;
  hardware.keyboard.qmk.enable = true;

  nixpkgs.overlays = [
    (_: previous: {
      # backport nixpkgs c399e1b7's Linux dependency hash for OpenCode 2.2.5
      opencode =
        if previous.stdenv.hostPlatform.isLinux && previous.opencode.version == "2.2.5"
        then
          previous.opencode.overrideAttrs (old: {
            node_modules = old.node_modules.overrideAttrs {
              outputHash = "sha256-prx9dX7kUvs/E3zopkaPk5LXh3xJAy5sZeum/W8L7cA=";
            };
          })
        else previous.opencode;
    })
  ];

  virtualisation.docker = {
    enable = true;
    daemon.settings = {
      mtu = 1280;
      registry-mirrors = ["https://mirror.gcr.io"];
    };
  };

  virtualisation.podman.enable = true;

  networking = {
    firewall.allowedTCPPorts = [8080 6768];
    nameservers = ["1.1.1.1" "1.0.0.1"];
    networkmanager.dns = "none";
  };

  boot.kernelPackages = pkgs.linuxPackages_zen;

  boot.loader = {
    systemd-boot.enable = true;
    efi.canTouchEfiVariables = true;
    efi.efiSysMountPoint = "/boot";
  };

  boot.supportedFilesystems = ["ntfs"];

  home-manager.useGlobalPkgs = true;

  services.earlyoom.enable = true;

  environment.persistence = lib.mkIf config.exeteres.disk.enable {
    "/persistent".directories = [
      "/var/lib/docker"
      "/var/lib/containers"
      "/var/lib/flatpak"
      "/var/lib/wg-feed"
    ];
  };
}
