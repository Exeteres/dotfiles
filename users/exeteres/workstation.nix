{
  lib,
  pkgs,
  ...
}: let
  githubKey = lib.removeSuffix "\n" (builtins.readFile ./keys/rebecca-github.pub);
in {
  imports = [./minimal.nix];

  home-manager.users.exeteres = {lib, ...}: {
    home.file.".ssh/allowed_signers".text = ''
      exeteres@proton.me ${githubKey}
    '';

    home.file.".ssh/rebecca-github.pub".source = ./keys/rebecca-github.pub;

    programs.ssh = {
      enable = true;
      enableDefaultConfig = false;
      settings."github.com" = {
        User = "git";
        IdentityFile = "~/.ssh/rebecca-github.pub";
        IdentitiesOnly = true;
      };
    };

    programs.opencode = {
      enable = true;
      extraPackages = [pkgs.wl-clipboard];
    };

    programs.git.settings = {
      user = {
        name = "Fedor Chubukov";
        email = "exeteres@proton.me";
        signingkey = "~/.ssh/rebecca-github.pub";
      };

      # Use the agent-backed GitHub key even for HTTPS clone/push URLs.
      url."git@github.com:".insteadOf = "https://github.com/";
    };
  };
}
