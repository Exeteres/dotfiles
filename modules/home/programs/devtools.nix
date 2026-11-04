{pkgs, ...}: let
  orca = pkgs.callPackage ./orca.nix {};
in {
  home.packages = with pkgs; [
    # language support
    alejandra
    nil

    # other tools
    wireshark
    devenv
    direnv
    gh
    kubectl
    kubernetes-helm
    k9s
    portal
    orca
    skills
    yandex-cloud
  ];

  programs.opencode.enable = true;
  programs.vscode.enable = true;

  programs.git = {
    enable = true;

    settings = {
      pull.rebase = true;
      gpg.format = "ssh";
      gpg.ssh.allowedSignersFile = "~/.ssh/allowed_signers";
      commit.gpgsign = true;
    };
  };

  programs.vim = {
    enable = true;
    defaultEditor = true;
  };

  home.file.".config/portal/config.yml".text = ''
    relay: portal.exeteres.net
  '';
}
