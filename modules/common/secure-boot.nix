{
  config,
  lib,
  options,
  pkgs,
  ...
}: let
  cfg = config.exeteres.secureBoot;
  logging = builtins.readFile ../../lib/shell-logging.sh;
  useSystemdActivation = config.sops.useSystemdActivation;
  secretsActivationScript =
    if useSystemdActivation
    then "setupSecretsForUsers"
    else "setupSecrets";
  syncUnits = lib.optionals useSystemdActivation ["sync-secure-boot-secrets.service"];
  stagingDirectory = "/run/secrets/secure-boot";
  destinationDirectory = "/var/lib/sbctl";
  trustedKernel = config.boot.kernelPackages.rebuildImage {
    inherit (config.system) modulesTree;
  };
  trustedKernelPath = "${trustedKernel}/${config.system.boot.loader.kernelFile}";
  syncSecureBootSecrets = pkgs.writeShellApplication {
    name = "sync-secure-boot-secrets";
    runtimeInputs = [pkgs.coreutils];
    text = ''
      ${logging}

      copy_secret() {
        source=$1
        target=$2
        mode=$3
        target_directory=$(dirname "$target")
        target_name=$(basename "$target")

        mkdir -p "$target_directory"
        temporary=$(mktemp "$target_directory/.$target_name.XXXXXXXX")
        install -m "$mode" -o root -g root "$source" "$temporary"
        mv -fT "$temporary" "$target"
      }

      log_info "Installing restored Secure Boot keys"
      copy_secret ${stagingDirectory}/GUID ${destinationDirectory}/GUID 0444
      copy_secret ${stagingDirectory}/PK.key ${destinationDirectory}/keys/PK/PK.key 0400
      copy_secret ${stagingDirectory}/PK.pem ${destinationDirectory}/keys/PK/PK.pem 0444
      copy_secret ${stagingDirectory}/KEK.key ${destinationDirectory}/keys/KEK/KEK.key 0400
      copy_secret ${stagingDirectory}/KEK.pem ${destinationDirectory}/keys/KEK/KEK.pem 0444
      copy_secret ${stagingDirectory}/db.key ${destinationDirectory}/keys/db/db.key 0400
      copy_secret ${stagingDirectory}/db.pem ${destinationDirectory}/keys/db/db.pem 0444
      log_success "Installed the restored sbctl key hierarchy"
    '';
  };
in {
  options.exeteres.secureBoot = {
    enable = lib.mkEnableOption "mutable Secure Boot key restoration";

    sopsFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "SOPS YAML file containing the sbctl GUID and key hierarchy.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.sopsFile != null;
        message = "exeteres.secureBoot.sopsFile is required when Secure Boot secret restoration is enabled.";
      }
    ];

    boot = {
      # Newer kernels enforce lockdown, but their module certificates must be
      # inserted into the final image. Keep older, pre-rebuildImage pins working.
      bootspec.writer = lib.mkIf (config.boot.kernelPackages ? rebuildImage) (lib.mkForce (
        options.boot.bootspec.writer.default
        + "\n"
        + ''
          ln -sf ${lib.escapeShellArg trustedKernelPath} "$out/kernel"
          ${pkgs.buildPackages.jq}/bin/jq \
            --arg kernel ${lib.escapeShellArg trustedKernelPath} \
            '."org.nixos.bootspec.v1".kernel = $kernel' \
            "$out/boot.json" > "$out/boot.json.tmp"
          mv "$out/boot.json.tmp" "$out/boot.json"
        ''
      ));
      lanzaboote = {
        enable = true;
        pkiBundle = destinationDirectory;
      };
      loader = {
        systemd-boot.enable = lib.mkForce false;
        efi = {
          canTouchEfiVariables = true;
          efiSysMountPoint = "/boot";
        };
      };
    };

    environment.systemPackages = [pkgs.sbctl];

    systemd.services.sync-secure-boot-secrets = lib.mkIf useSystemdActivation {
      description = "Install mutable Secure Boot secrets";
      wantedBy = ["multi-user.target"];
      requires = ["sops-install-secrets.service"];
      after = ["sops-install-secrets.service"];
      unitConfig.ConditionPathExists = "${stagingDirectory}/GUID";
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${syncSecureBootSecrets}/bin/sync-secure-boot-secrets";
      };
    };

    system.activationScripts.syncSecureBootSecrets = lib.stringAfter [secretsActivationScript] ''
      ${syncSecureBootSecrets}/bin/sync-secure-boot-secrets
    '';

    sops.secrets = {
      secure-boot-guid = {
        sopsFile = cfg.sopsFile;
        key = "guid";
        path = "${stagingDirectory}/GUID";
        neededForUsers = useSystemdActivation;
        restartUnits = syncUnits;
      };
      secure-boot-pk-key = {
        sopsFile = cfg.sopsFile;
        key = "pk/key";
        path = "${stagingDirectory}/PK.key";
        neededForUsers = useSystemdActivation;
        restartUnits = syncUnits;
      };
      secure-boot-pk-cert = {
        sopsFile = cfg.sopsFile;
        key = "pk/cert";
        path = "${stagingDirectory}/PK.pem";
        neededForUsers = useSystemdActivation;
        restartUnits = syncUnits;
      };
      secure-boot-kek-key = {
        sopsFile = cfg.sopsFile;
        key = "kek/key";
        path = "${stagingDirectory}/KEK.key";
        neededForUsers = useSystemdActivation;
        restartUnits = syncUnits;
      };
      secure-boot-kek-cert = {
        sopsFile = cfg.sopsFile;
        key = "kek/cert";
        path = "${stagingDirectory}/KEK.pem";
        neededForUsers = useSystemdActivation;
        restartUnits = syncUnits;
      };
      secure-boot-db-key = {
        sopsFile = cfg.sopsFile;
        key = "db/key";
        path = "${stagingDirectory}/db.key";
        neededForUsers = useSystemdActivation;
        restartUnits = syncUnits;
      };
      secure-boot-db-cert = {
        sopsFile = cfg.sopsFile;
        key = "db/cert";
        path = "${stagingDirectory}/db.pem";
        neededForUsers = useSystemdActivation;
        restartUnits = syncUnits;
      };
    };
  };
}
