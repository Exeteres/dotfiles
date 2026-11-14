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
