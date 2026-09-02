{installer}: {modulesPath, ...}: {
  imports = [
    (import ./shared.nix {inherit installer;})
    (modulesPath + "/installer/cd-dvd/installation-cd-minimal.nix")
  ];

  fonts.fontconfig.enable = true;
}
