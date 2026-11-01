{...}: {
  boot = {
    initrd.availableKernelModules = [
      "nvme"
      "xhci_pci"
      "thunderbolt"
    ];
    kernelParams = ["lockdown=integrity"];
    kernelModules = ["kvm-amd"];
  };

  hardware = {
    cpu.amd.updateMicrocode = true;
    enableRedistributableFirmware = true;
  };

  services.fprintd.enable = true;

  security.lsm = ["lockdown"];
}
