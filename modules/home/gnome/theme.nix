{pkgs, ...}: {
  dconf.settings = {
    # configure gnome appearance
    "org/gnome/desktop/interface" = {
      cursor-theme = "Adwaita";
      color-scheme = "prefer-dark";
      icon-theme = "Papirus-Dark";
      gtk-theme = "Adwaita-dark";
    };
  };

  # install gnome themes and icons
  home.packages = with pkgs; [
    gnome-themes-extra
    papirus-icon-theme
  ];
}
