{
  imports = [
    ./hardware.nix
    ./fingerprint.nix
    ./sops.nix
    ./disk.nix
    ./private.nix
  ];

  boot.loader = {
    systemd-boot.enable = true;
    efi.canTouchEfiVariables = true;
  };

  exeteres.tpm = {
    enable = true;
    user = "exeteres";
  };

  exeteres.pivyAgent.guid = "3C79FEBBA08048CABF41D4FF82007463";
  exeteres.sshAgentMux.pivy.enable = true;

  services.touchegg.enable = true;

  networking.hostName = "rebecca";
  system.stateVersion = "26.05";
}
