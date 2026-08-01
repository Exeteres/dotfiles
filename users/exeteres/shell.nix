{
  users.users.exeteres = {
    isNormalUser = true;
    uid = 1000;
    description = "Fedor Chubukov";

    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMNIqtAny6k6r7uB8XIyyycLEUJy/Ecd9RIiZWji2GdI exeteres"
    ];

    extraGroups = [
      "docker"
      "fuse"
      "networkmanager"
      "wheel"
      "wireshark"
    ];
  };
}
