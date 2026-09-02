{
  nixpkgs,
  pkgs,
  hostName,
  installer,
  modules,
  specialArgs ? {},
  system ? pkgs.stdenv.hostPlatform.system,
}: let
  logging = builtins.readFile ./shell-logging.sh;
  sudo = builtins.readFile ./shell-sudo.sh;
  installerPackage = import ./mk-installer.nix (installer // {inherit hostName pkgs;});
  configuration = nixpkgs.lib.nixosSystem {
    inherit specialArgs system;
    modules =
      [
        (import ../modules/images/kexec.nix {installer = installerPackage;})
        {networking.hostName = "${hostName}-kexec";}
      ]
      ++ modules;
  };
in
  pkgs.writeShellApplication {
    name = "kexec";
    runtimeInputs = with pkgs; [coreutils gnugrep kexec-tools mokutil sbsigntool systemd];
    text = let
      commandLine = builtins.concatStringsSep " " ([
          "init=${configuration.config.system.build.toplevel}/init"
          "nohibernate"
        ]
        ++ configuration.config.boot.kernelParams);
    in ''
      ${logging}
      ${sudo}

      if ! locate_privilege_escalation; then
        log_error "No setuid sudo executable was found."
        exit 1
      fi
      kernel=${configuration.config.system.build.kexecTree}/bzImage
      if mokutil --sb-state | grep -q "SecureBoot enabled"; then
        log_info "Signing the kexec kernel for Secure Boot"
        key=/var/lib/sbctl/keys/db/db.key
        cert=/var/lib/sbctl/keys/db/db.pem
        if ! "''${sudo_command[@]}" "$(command -v stat)" "$key" > /dev/null \
          || ! "''${sudo_command[@]}" "$(command -v stat)" "$cert" > /dev/null; then
          log_error "Secure Boot signing keys are unavailable in /var/lib/sbctl."
          exit 1
        fi
        "''${sudo_command[@]}" "$(command -v sbsign)" --key "$key" --cert "$cert" \
          --output /run/${hostName}-kexec-bzImage "$kernel"
        kernel=/run/${hostName}-kexec-bzImage
        log_success "Signed the kexec kernel"
      else
        log_warning "Secure Boot is disabled; using the unsigned kexec kernel"
      fi

      log_info "Loading the ${hostName} kexec system"
      "''${sudo_command[@]}" "$(command -v kexec)" --kexec-file-syscall --load "$kernel" \
        --initrd=${configuration.config.system.build.kexecTree}/initrd.gz \
        --command-line ${pkgs.lib.escapeShellArg commandLine}
      log_success "Loaded the ${hostName} kexec system"
      log_warning "Rebooting into ${hostName} now"
      "''${sudo_command[@]}" "$(command -v systemctl)" kexec -i
    '';
  }
