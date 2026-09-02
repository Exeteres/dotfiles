{
  imports = [
    ./hardware.nix
    ./sops.nix
    ./disk.nix
  ];

  boot.loader = {
    systemd-boot.enable = true;
    efi.canTouchEfiVariables = true;
  };

  exeteres.tpm = {
    enable = true;
    user = "exeteres";
  };

  networking.hostName = "amsonia";
  system.stateVersion = "26.05";
}
