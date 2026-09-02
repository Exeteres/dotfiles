{
  boot.loader = {
    systemd-boot.enable = true;
    efi.canTouchEfiVariables = true;
  };

  exeteres.disk = {
    enable = true;
    device = "/dev/disk/by-id/replace-with-amsonia-disk";
  };

  networking.hostName = "amsonia";
  system.stateVersion = "26.05";
}
