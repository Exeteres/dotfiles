{config, lib, pkgs, ...}: {
  imports = [
    ./gnome
    ./other/fonts.nix
  ];

  networking.networkmanager.enable = true;

  services = {
    fstrim.enable = true;
    fwupd.enable = true;
    power-profiles-daemon.enable = true;
    xserver.enable = true;
    pipewire = {
      enable = true;
      alsa.enable = true;
      alsa.support32Bit = true;
      pulse.enable = true;
    };
  };

  security.rtkit.enable = true;
  hardware.bluetooth.enable = true;

  programs = {
    dconf.enable = true;
    nix-ld.enable = true;
  };

  environment.systemPackages =
    (with pkgs; [
      git
      vim
      wget
    ])
    ++ lib.optional (!config.services.flatpak.enable) pkgs.firefox;
}
