{pkgs, ...}: {
  imports = [./minimal.nix];

  home-manager.users.exeteres = {
    home.file.".ssh/allowed_signers".text = ''
      exeteres@proton.me ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMNIqtAny6k6r7uB8XIyyycLEUJy/Ecd9RIiZWji2GdI exeteres
    '';

    programs.opencode = {
      enable = true;
      extraPackages = [pkgs.wl-clipboard];
    };

    programs.git.settings.user = {
      name = "Fedor Chubukov";
      email = "exeteres@proton.me";
    };
  };
}
