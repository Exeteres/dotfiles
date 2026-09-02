{pkgs, ...}: {
  boot = {
    initrd.availableKernelModules = [
      "xhci_pci"
      "thunderbolt"
      "ahci"
      "nvme"
      "rtsx_pci_sdmmc"
    ];
    initrd.kernelModules = ["dm-snapshot"];
    kernelParams = ["lockdown=integrity"];
    kernelModules = ["kvm-intel"];
  };

  hardware = {
    cpu.intel.updateMicrocode = true;
    enableRedistributableFirmware = true;
  };

  services.fprintd = {
    enable = true;
    tod = {
      enable = true;
      driver = pkgs.libfprint-2-tod1-broadcom;
    };
  };

  security.lsm = ["lockdown"];
}
