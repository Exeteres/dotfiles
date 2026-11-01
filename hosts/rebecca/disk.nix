{
  exeteres.disk = {
    enable = true;
    device = "/dev/disk/by-id/nvme-eui.e8238fa6bf530001001b444a45927103";
    swapSize = "40G";
    retentionDays = 30;
  };

  boot.initrd.luks.devices.cryptroot.crypttabExtraOpts = ["tpm2-device=auto"];

  environment.persistence."/persistent".directories = [
    "/var/lib/fprint"
    "/var/lib/sbctl"
  ];
}
