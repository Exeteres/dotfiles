{config, lib, ...}: {
  imports = [./shell.nix];

  environment.persistence = lib.mkIf config.exeteres.disk.enable {
    "/persistent".directories = [
      {
        directory = "/home/exeteres";
        user = "exeteres";
        group = "users";
        mode = "0700";
      }
    ];
  };

  home-manager.users.exeteres.home = {
    username = "exeteres";
    homeDirectory = "/home/exeteres";
    stateVersion = "26.05";
    enableNixpkgsReleaseCheck = false;
  };
}
