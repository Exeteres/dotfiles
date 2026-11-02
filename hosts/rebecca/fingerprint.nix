{pkgs, ...}: let
  libfprint = pkgs.libfprint.overrideAttrs (_: {
    version = "1.94.100-goodix5f10";
    src = pkgs.fetchFromGitHub {
      owner = "mounkastel";
      repo = "goodix-5f10-libfprint";
      rev = "bda8c5123605f12644d7e4ba827eaee9f0d011da";
      hash = "sha256-TOCN/OQVs+hCt27ZXOn6l1dkosHovgnOCsw278FYiak=";
    };
    patches = [];
  });
in {
  services.fprintd = {
    enable = true;
    package = pkgs.fprintd.override {inherit libfprint;};
  };

  # the per-device TLS key is provisioned on first use and persisted under /var/lib/fprint
  systemd.services.fprintd.environment.GOODIX5F10_AUTOPROVISION = "1";
}
