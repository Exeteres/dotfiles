{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.exeteres.workshop;
  helper = pkgs.writeShellApplication {
    name = "workshop";
    runtimeInputs = [pkgs.python3 pkgs.openssh pkgs.rsync pkgs.git pkgs.yandex-cloud pkgs.android-tools pkgs.scrcpy pkgs.iproute2 pkgs.netcat-openbsd];
    text = ''
      exec python3 ${./skill}/scripts/workshop.py "$@"
    '';
  };
in {
  options.exeteres.workshop = {
    enable = lib.mkEnableOption "the local OpenCode Workshop skill and SSH helpers";
    bypassVpn = lib.mkEnableOption "temporary direct IPv4 routes for Workshop SSH (requires noninteractive sudo)";
    user = lib.mkOption {
      type = lib.types.str;
      description = "Local user receiving the skill and helper command.";
    };
    controller = lib.mkOption {
      type = lib.types.submodule {
        options = lib.genAttrs ["functionId" "organizationId" "login"] (_: lib.mkOption {type = lib.types.str;});
      };
      description = "Workshop Function ID and OS Login identity metadata. Credentials come from the local YC profile.";
    };
  };

  config = lib.mkIf cfg.enable {
    home-manager.users.${cfg.user} = {
      home.packages = [helper pkgs.android-tools];
      xdg.configFile."opencode/skills/workshop".source = ./skill;
      xdg.configFile."workshop/config.json".text = builtins.toJSON (cfg.controller // {inherit (cfg) bypassVpn;});
    };
  };
}
