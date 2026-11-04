{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.exeteres.bitwardenAgent;
  pinentry = pkgs.writeShellScript "rbw-pinentry-sops" ''
    exec ${pkgs.python3}/bin/python3 ${./pinentry.py} \
      "''${RBW_PASSWORD_FILE:-${cfg.passwordFile}}" \
      ${pkgs.pinentry-gnome3}/bin/pinentry-gnome3 "$@"
  '';
in {
  options.exeteres.bitwardenAgent = {
    enable = lib.mkEnableOption "the rbw SSH agent with automatic SOPS-backed unlocking";
    user = lib.mkOption {
      type = lib.types.str;
      description = "User running rbw and owning its encrypted vault cache.";
    };
    passwordFile = lib.mkOption {
      type = lib.types.str;
      description = "Runtime SOPS secret containing the Bitwarden master password.";
    };
    email = lib.mkOption {
      type = lib.types.str;
      description = "Bitwarden account email.";
    };
    baseUrl = lib.mkOption {
      type = lib.types.str;
      description = "Bitwarden server base URL.";
    };
    syncInterval = lib.mkOption {
      type = lib.types.ints.positive;
      default = 300;
      description = "Fallback sync interval in seconds, in addition to server notifications.";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [pkgs.rbw];
    home-manager.users.${cfg.user}.xdg.configFile."rbw/config.json".text = builtins.toJSON {
      email = cfg.email;
      base_url = cfg.baseUrl;
      pinentry = toString pinentry;
      lock_timeout = 3600;
      sync_interval = cfg.syncInterval;
    };
    exeteres.sshAgentMux.agents = ["%t/rbw/ssh-agent-socket"];
    systemd.user.services.rbw-agent = {
      description = "Bitwarden-compatible rbw vault and SSH agent";
      wantedBy = ["default.target"];
      before = ["ssh-agent-mux.service"];
      unitConfig.ConditionUser = cfg.user;
      environment.RBW_PASSWORD_FILE = "%d/master-password";
      serviceConfig = {
        Type = "exec";
        ExecStart = "${pkgs.rbw}/bin/rbw-agent --no-daemonize";
        LoadCredential = "master-password:${cfg.passwordFile}";
        RuntimeDirectory = "rbw";
        RuntimeDirectoryMode = "0700";
        UMask = "0077";
        LimitCORE = 0;
        TimeoutStartSec = 120;
        Restart = "on-failure";
        RestartSec = 30;
      };
    };
    systemd.user.services.ssh-agent-mux = lib.mkIf config.exeteres.sshAgentMux.enable {
      wants = ["rbw-agent.service"];
      after = ["rbw-agent.service"];
    };
  };
}
