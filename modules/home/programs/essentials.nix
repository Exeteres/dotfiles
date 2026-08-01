{pkgs, ...}: {
  home.packages = with pkgs; [
    # utils
    ffmpeg
    home-manager
    wireguard-tools
  ];

  programs.home-manager.enable = true;
  services.syncthing.enable = true;
}
