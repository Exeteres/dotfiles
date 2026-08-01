{pkgs, ...}: {
  imports = [
    ./gsconnect.nix
  ];

  # enable gnome display manager
  services.displayManager.gdm = {
    enable = true;
  };

  environment.systemPackages = [pkgs.xprop];

  # enable gnome desktop environment
  services.desktopManager.gnome.enable = true;

  # remove unwanted GNOME packages
  environment.gnome.excludePackages = with pkgs; [
    gnome-tour
    cheese
    yelp
    epiphany
    simple-scan
    gnome-software
  ];
}
