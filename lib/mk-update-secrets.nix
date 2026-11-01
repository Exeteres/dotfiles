{
  pkgs,
  secureBootFile,
  tpmIdentityFile,
  yubikeyIdentityFile ? null,
  secureBootDirectory ? "/var/lib/sbctl",
  sopsConfig ? ".sops.yaml",
}: let
  logging = builtins.readFile ./shell-logging.sh;
  sudo = builtins.readFile ./shell-sudo.sh;
in
  pkgs.writeShellApplication {
    name = "update-secrets";
    runtimeInputs = with pkgs; [age-plugin-tpm age-plugin-yubikey coreutils sops yq-go];
    text = ''
      ${logging}
      ${sudo}

      if ! locate_privilege_escalation; then
        log_error "Updating Secure Boot secrets requires root or a setuid sudo executable."
        exit 1
      fi

      tpm_identity_file=$(realpath -m ${pkgs.lib.escapeShellArg tpmIdentityFile})
      ${pkgs.lib.optionalString (yubikeyIdentityFile != null) ''
      yubikey_identity_file=$(realpath -m ${pkgs.lib.escapeShellArg yubikeyIdentityFile})
      ''}
      secure_boot_sops_file=$(realpath -m ${pkgs.lib.escapeShellArg secureBootFile})
      sops_config=$(realpath -m ${pkgs.lib.escapeShellArg sopsConfig})

      temporary=$(mktemp -d)
      trap 'rm -rf "$temporary"' EXIT

      install_encrypted() {
        source=$1
        target=$2
        target_directory=$(dirname "$target")

        mkdir -p "$target_directory"
        staged=$(mktemp "$target_directory/.update-secrets.XXXXXXXX")
        install -m 0600 "$source" "$staged"
        mv -fT "$staged" "$target"
      }

      verify_encrypted() {
        encrypted_file=$1
        tpm_home="$temporary/tpm-home"
        mkdir -m 0700 "$tpm_home"

        if ! "''${sudo_command[@]}" env -i \
          HOME="$tpm_home" \
          PATH="$PATH" \
          SOPS_AGE_KEY_FILE="$tpm_identity_file" \
          "$(command -v sops)" decrypt "$encrypted_file" > /dev/null; then
          log_error "Failed to verify generated Secure Boot secrets for $secure_boot_sops_file."
          log_error "SOPS could not decrypt the generated ciphertext using the configured TPM identity."
          log_warning "The encrypted destination file was not modified."
          return 1
        fi
        log_success "Verified generated Secure Boot secrets with the TPM identity"
        ${pkgs.lib.optionalString (yubikeyIdentityFile != null) ''
        yubikey_home="$temporary/yubikey-home"
        mkdir -m 0700 "$yubikey_home"
        if ! env -i \
          HOME="$yubikey_home" \
          PATH="$PATH" \
          SOPS_AGE_KEY_FILE="$yubikey_identity_file" \
          "$(command -v sops)" decrypt "$encrypted_file" > /dev/null; then
          log_error "Failed to verify generated Secure Boot secrets for $secure_boot_sops_file with a YubiKey."
          log_error "SOPS could not decrypt the generated ciphertext using the configured YubiKey identity."
          log_warning "The encrypted destination file was not modified."
          return 1
        fi
        log_success "Verified generated Secure Boot secrets with the YubiKey identity"
      ''}
      }

      log_info "Encrypting Secure Boot keys"
      "''${sudo_command[@]}" "$(command -v yq)" -n '
        .guid = load_str(${builtins.toJSON "${secureBootDirectory}/GUID"}) |
        .pk.key = load_str(${builtins.toJSON "${secureBootDirectory}/keys/PK/PK.key"}) |
        .pk.cert = load_str(${builtins.toJSON "${secureBootDirectory}/keys/PK/PK.pem"}) |
        .kek.key = load_str(${builtins.toJSON "${secureBootDirectory}/keys/KEK/KEK.key"}) |
        .kek.cert = load_str(${builtins.toJSON "${secureBootDirectory}/keys/KEK/KEK.pem"}) |
        .db.key = load_str(${builtins.toJSON "${secureBootDirectory}/keys/db/db.key"}) |
        .db.cert = load_str(${builtins.toJSON "${secureBootDirectory}/keys/db/db.pem"})
      ' | sops --config "$sops_config" encrypt \
        --filename-override "$secure_boot_sops_file" \
        --input-type yaml \
        --output-type yaml \
        > "$temporary/secure-boot.sops.yaml"
      verify_encrypted "$temporary/secure-boot.sops.yaml"

      log_info "Installing verified encrypted Secure Boot secrets"
      install_encrypted "$temporary/secure-boot.sops.yaml" "$secure_boot_sops_file"
      log_success "Updated encrypted Secure Boot secrets"
    '';
  }
