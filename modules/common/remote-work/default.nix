{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.exeteres.remoteWork;
  helper = pkgs.writeShellApplication {
    name = "remote-work";
    runtimeInputs = [pkgs.python3 pkgs.openssh pkgs.rsync pkgs.git];
    text = ''
      exec python3 ${./skill/scripts/remote-work.py} "$@"
    '';
  };
in {
  options.exeteres.remoteWork = {
    enable = lib.mkEnableOption "the local OpenCode remote-work skill and SSH helpers";
    user = lib.mkOption {
      type = lib.types.str;
      description = "Local user receiving the skill and helper command.";
    };
  };

  config = lib.mkIf cfg.enable {
    home-manager.users.${cfg.user} = {
      home.packages = [helper];
      xdg.configFile."opencode/skills/remote-work".source = ./skill;
    };
  };
}
