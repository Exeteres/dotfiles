{pkgs, ...}: {
  services.pcscd = {
    enable = true;
    extraArgs = ["--disable-polkit"];
  };

  security.pam.p11.enable = true;

  environment.systemPackages = with pkgs; [
    yubikey-manager
    opensc
    pcsc-tools
    libp11
  ];
}
