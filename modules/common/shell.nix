{pkgs, ...}: {
  # common packages for all desktops and servers
  environment.systemPackages = with pkgs; [
    vim
    git
    htop
    age
    sops
    openssl
    tcpdump
    iptables
    traceroute
    glib
    dig
    speedtest-go
    bore-cli
    sysstat
    nmap
    dive
    attic-client
    strace
    ltrace
    lsof
    ripgrep
    jq
    yq-go
  ];

  # use zsh on all desktops and servers
  programs.zsh = {
    enable = true;
    autosuggestions.enable = true;
    syntaxHighlighting.enable = true;

    ohMyZsh = {
      enable = true;
      theme = "gallifrey";
      plugins = [
        "git"
        "sudo"
        "z"
      ];
    };
  };

  users.defaultUserShell = pkgs.zsh;

  # use vim as default editor
  programs.vim.enable = true;
  programs.vim.defaultEditor = true;
}
