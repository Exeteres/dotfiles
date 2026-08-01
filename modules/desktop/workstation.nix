{pkgs, ...}: {
  imports = [
    ./minimal.nix
    ./other/boot.nix
    ./other/i18n.nix
    ./other/sound.nix
    ./other/timezone.nix
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

  boot.kernelPackages = pkgs.linuxPackages_zen;

  boot.loader = {
    systemd-boot.enable = true;
    efi.canTouchEfiVariables = true;
    efi.efiSysMountPoint = "/boot";
  };

  boot.supportedFilesystems = ["ntfs"];

  home-manager.useGlobalPkgs = true;

  environment.sessionVariables = {
    DO_NOT_TRACK = "1";
    DOTNET_CLI_TELEMETRY_OPTOUT = "1";
  };

  services.earlyoom.enable = true;
}
