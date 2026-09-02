{
  exeteres.disk = {
    enable = true;
    device = "/dev/disk/by-id/replace-with-amsonia-disk";
    swapSize = "40G";
    retentionDays = 30;
  };

  boot.initrd.luks.devices.cryptroot.crypttabExtraOpts = ["tpm2-device=auto"];

  environment.persistence."/persistent".directories = [
    "/var/lib/fprint"
    "/var/lib/sbctl"
  ];
}
