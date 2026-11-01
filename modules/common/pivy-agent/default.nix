{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.exeteres.pivyAgent;
  args =
    ["-i" "-a" cfg.socket "-S" ("!all," + lib.concatStringsSep "," cfg.slots)]
    ++ lib.optionals (cfg.guid != null) ["-g" cfg.guid]
    ++ lib.optionals (cfg.cardAuthenticationKey != null) ["-K" cfg.cardAuthenticationKey];
in {
  options.exeteres.pivyAgent = {
    enable = lib.mkEnableOption "the Pivy PIV SSH agent";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.callPackage ./package.nix {};
      description = "Pivy package providing pivy-agent and pivy-tool.";
    };

    guid = lib.mkOption {
      type = lib.types.nullOr (lib.types.strMatching "[0-9a-fA-F]{32}");
      default = null;
      description = "Full PIV token GUID, as shown by pivy-tool list. Required when enabled.";
    };

    slots = lib.mkOption {
      type = lib.types.listOf (lib.types.strMatching "(8[2-9a-f]|9[0-5acde])");
      default = ["9a"];
      description = "PIV slots exposed for SSH. The default excludes age's retired key-management slots.";
    };

    cardAuthenticationKey = lib.mkOption {
      type = lib.types.nullOr lib.types.singleLineStr;
      default = null;
      description = "Optional slot 9e public key in OpenSSH format, passed as key text to -K to authenticate the token.";
    };

    askpass = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = "${pkgs.openssh-askpass}/libexec/gtk-ssh-askpass";
      defaultText = lib.literalExpression ''"''${pkgs.openssh-askpass}/libexec/gtk-ssh-askpass"'';
      description = "SSH_ASKPASS executable for PIN entry; null requires explicit unlocking through the Pivy socket.";
    };

    socket = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      default = "%t/pivy-agent/agent.sock";
      description = "Pivy's private backend socket, using the systemd user runtime-directory specifier.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.guid != null;
        message = "exeteres.pivyAgent.guid must be set to the full PIV token GUID.";
      }
      {
        assertion = cfg.slots != [];
        message = "exeteres.pivyAgent.slots must expose at least one SSH key slot.";
      }
    ];

    services.pcscd.enable = true;
    environment.systemPackages = [cfg.package];

    # Start with the graphical session so askpass inherits its display context.
    # This is a backend only: it never changes the session's SSH_AUTH_SOCK.
    systemd.user.services.pivy-agent = {
      description = "Pivy PIV SSH agent";
      wantedBy = ["graphical-session.target"];
      partOf = ["graphical-session.target"];
      after = ["graphical-session-pre.target"];
      environment =
        {
          SSH_NOTIFY_SEND = "${pkgs.libnotify}/bin/notify-send";
        }
        // lib.optionalAttrs (cfg.askpass != null) {
          SSH_ASKPASS = cfg.askpass;
        };
      serviceConfig = {
        Type = "exec";
        ExecStartPre = "${pkgs.coreutils}/bin/rm -f ${cfg.socket}";
        ExecStart = "${lib.getExe cfg.package} ${lib.escapeShellArgs args}";
        Restart = "on-failure";
        RestartSec = 3;
        RuntimeDirectory = "pivy-agent";
        RuntimeDirectoryMode = "0700";
        UMask = "0077";
      };
    };
  };
}
