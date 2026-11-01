{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.exeteres.sshAgentMux;
  socket = "%t/ssh-agent-mux/agent.sock";
  agents = lib.unique (
    lib.optional cfg.gnomeKeyring.enable "%t/gcr/ssh"
    ++ lib.optional cfg.pivy.enable config.exeteres.pivyAgent.socket
    ++ cfg.agents
  );
  args =
    [
      "start"
      "--foreground"
      "--no-discovery"
      "--socket"
      socket
      "--pid-file"
      "%t/ssh-agent-mux/mux.pid"
      "--refresh-interval"
      (toString cfg.identityRefreshInterval)
      "--sign-timeout"
      (toString cfg.signTimeout)
    ]
    ++ lib.concatMap (agent: ["--agent" agent]) agents
    ++ lib.optionals (cfg.primaryAgent != null) ["--primary-agent" cfg.primaryAgent];
in {
  options.exeteres.sshAgentMux = {
    enable = lib.mkEnableOption "the SSH agent multiplexer as the default user agent";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.callPackage ./package.nix {};
      description = "SSH agent multiplexer package.";
    };

    gnomeKeyring.enable = lib.mkEnableOption "the GNOME Keyring/GCR SSH agent backend";
    pivy.enable = lib.mkEnableOption "the Pivy SSH agent backend (configured through exeteres.pivyAgent)";

    agents = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      example = ["%t/gcr/ssh" "%t/another-agent.sock"];
      description = ''
        Additional explicit backend sockets, with systemd specifiers such as
        %t supported. GNOME Keyring and Pivy are included separately when enabled.
        Discovery is always disabled, including at startup and on refresh.
        At least one backend must be configured. Identities are refreshed only
        from these sockets, periodically and after key-changing operations.
      '';
    };

    primaryAgent = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default =
        if cfg.gnomeKeyring.enable
        then "%t/gcr/ssh"
        else null;
      defaultText = lib.literalExpression ''if config.exeteres.sshAgentMux.gnomeKeyring.enable then "%t/gcr/ssh" else null'';
      description = "Backend for ssh-add operations; null rejects additions. Custom sockets must also be listed in agents to expose their keys.";
    };

    signTimeout = lib.mkOption {
      type = lib.types.ints.positive;
      default =
        if cfg.pivy.enable
        then 120
        else 30;
      defaultText = lib.literalExpression "if config.exeteres.sshAgentMux.pivy.enable then 120 else 30";
      description = "Timeout in seconds for signing and other interactive agent operations.";
    };

    identityRefreshInterval = lib.mkOption {
      type = lib.types.ints.unsigned;
      default = 30;
      description = ''
        Interval in seconds for refreshing identities from configured sockets.
        The background worker also handles refreshes after key-changing
        operations. Zero disables the worker; manual refresh remains available.
        Socket discovery is always disabled regardless of this setting.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = agents != [];
        message = "exeteres.sshAgentMux requires at least one backend: enable gnomeKeyring or pivy, or provide agents.";
      }
    ];

    programs.ssh.startAgent = lib.mkDefault false;
    exeteres.pivyAgent.enable = lib.mkIf cfg.pivy.enable true;
    environment.systemPackages = [cfg.package];

    environment.sessionVariables.SSH_AUTH_SOCK = "\${XDG_RUNTIME_DIR}/ssh-agent-mux/agent.sock";
    environment.etc."environment.d/90-ssh-agent-mux.conf".text = ''
      SSH_AUTH_SOCK=''${XDG_RUNTIME_DIR}/ssh-agent-mux/agent.sock
    '';

    services.gnome.gnome-keyring.enable = lib.mkIf cfg.gnomeKeyring.enable true;
    services.gnome.gcr-ssh-agent.enable = lib.mkIf cfg.gnomeKeyring.enable true;

    # Keep GNOME's socket activation from replacing the default client socket.
    systemd.user.sockets.gcr-ssh-agent = lib.mkIf config.services.gnome.gcr-ssh-agent.enable {
      socketConfig.ExecStartPost = [
        ""
        "${pkgs.systemd}/bin/systemctl --user set-environment SSH_AUTH_SOCK=${socket}"
      ];
    };

    systemd.user.services.ssh-agent-mux = {
      description = "SSH agent multiplexer";
      wantedBy = ["default.target"];
      requires = lib.optional cfg.gnomeKeyring.enable "gcr-ssh-agent.service";
      after = lib.optional cfg.gnomeKeyring.enable "gcr-ssh-agent.service";

      serviceConfig = {
        Type = "exec";
        ExecStart = "${lib.getExe cfg.package} ${lib.escapeShellArgs args}";
        Restart = "on-failure";
        RestartSec = 2;
        RuntimeDirectory = "ssh-agent-mux";
        RuntimeDirectoryMode = "0700";
        UMask = "0077";
      };
    };
  };
}
