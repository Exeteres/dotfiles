{
  config,
  lib,
  pkgs,
  ...
}: {
  imports = [
    ./gnome
    ./other/fonts.nix
  ];

  networking.networkmanager.enable = true;

  exeteres.sshAgentMux = {
    enable = lib.mkDefault true;
    gnomeKeyring.enable = lib.mkDefault true;
  };

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

  environment.sessionVariables = {
    DO_NOT_TRACK = "1";
    DOTNET_CLI_TELEMETRY_OPTOUT = "1";
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
