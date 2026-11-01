{
  imports = [
    ./disk.nix
    ./pivy-agent
    ./shell.nix
    ./ssh-agent-mux
    ./tpm.nix
    ./unfree.nix
  ];

  # allow passwordless sudo
  security.sudo.wheelNeedsPassword = false;
  users.mutableUsers = false;

  nix.settings = {
    experimental-features = ["nix-command" "flakes"];
    auto-optimise-store = true;

    substituters = [
      "https://cache.nixos.org"
    ];

    trusted-users = ["exeteres"];
  };

  nix.gc = {
    automatic = true;
    dates = "daily";
    options = "--delete-older-than 7d";
  };
}
