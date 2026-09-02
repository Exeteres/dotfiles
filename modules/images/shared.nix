{installer}: {
  lib,
  pkgs,
  ...
}: {
  boot.zfs.forceImportRoot = false;

  networking.networkmanager.enable = true;

  users.users = {
    nixos.enable = lib.mkForce false;
    root.initialHashedPassword = lib.mkForce null;
  };

  services = {
    displayManager.autoLogin.enable = lib.mkForce false;
    getty.autologinUser = lib.mkForce null;
  };

  environment.systemPackages = with pkgs; [
    cryptsetup
    disko
    git
    kexec-tools
    nixos-install-tools
    sbctl
    tmux
    installer
  ];

  system.stateVersion = "26.05";
}
