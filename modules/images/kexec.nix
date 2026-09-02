{installer}: {modulesPath, ...}: {
  imports = [
    (import ./shared.nix {inherit installer;})
    (modulesPath + "/installer/netboot/netboot-base.nix")
  ];

  boot.initrd.network.enable = true;
}
