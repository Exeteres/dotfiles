{pkgs, ...}: {
  home.packages = with pkgs; [
    # language support
    alejandra
    nil
    python3

    # other tools
    wireshark
    nmap
    devenv
    direnv
    gh
    grpcurl
    kubectl
    kubernetes-helm
    k9s
    portal
  ];

  programs.opencode.enable = true;

  programs.vscode = {
    enable = true;
  };

  programs.git = {
    enable = true;

    settings = {
      pull.rebase = true;
      gpg.format = "ssh";
      gpg.ssh.allowedSignersFile = "~/.ssh/allowed_signers";
      user.signingkey = "~/.ssh/id_ed25519.pub";
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
