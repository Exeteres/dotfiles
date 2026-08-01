{pkgs, ...}: {
  fonts.packages = with pkgs; [
    nerd-fonts.fira-code
  ];

  fonts.fontconfig.defaultFonts = {
    monospace = ["FiraCode Nerd Font"];
  };
}
