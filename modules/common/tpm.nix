{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.exeteres.tpm;
in {
  options.exeteres.tpm = {
    enable = lib.mkEnableOption "TPM 2.0 and age-plugin-tpm support";
    user = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "User to add to the tss group.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.user == null || builtins.hasAttr cfg.user config.users.users;
        message = "exeteres.tpm.user must name an entry in users.users.";
      }
    ];

    security.tpm2 = {
      enable = true;
      applyUdevRules = true;
    };

    environment.systemPackages = [pkgs.age-plugin-tpm];

    users.groups.tss.members = lib.optional (cfg.user != null) cfg.user;
  };
}
