{
  users.users.exeteres = {
    isNormalUser = true;
    uid = 1000;
    description = "Fedor Chubukov";

    extraGroups = [
      "docker"
      "fuse"
      "networkmanager"
      "wheel"
      "wireshark"
    ];
  };
}
