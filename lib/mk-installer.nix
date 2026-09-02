{
  configuration,
  pkgs,
  hostName,
}: let
  logging = builtins.readFile ./shell-logging.sh;
  target = import ./installer-target.nix {inherit configuration;};
in
  pkgs.writeShellApplication {
    name = "install-system";
    runtimeInputs = [
      pkgs.cryptsetup
      pkgs.coreutils
      pkgs.gnugrep
      pkgs.jq
      pkgs.mokutil
      pkgs.nix
      pkgs.nixos-install-tools
      pkgs.openssl
      pkgs.util-linux
    ];
    text = ''
      ${logging}

      dry_run=false
      flake_reference=

      usage() {
        cat <<EOF
      Usage: install-system [--dry-run] [--flake <flake>#<configuration>]

      Examples:
        install-system
        install-system --flake /path/to/flake#${hostName}
      EOF
      }

      fail() {
        log_error "$1"
        if [[ ''${installation_started:-false} == true ]]; then
          installation_failed 1
        fi
        exit 1
      }

      check_secret() {
        if [[ ! -s $1 ]]; then
          fail "Required Secure Boot file $1 is unavailable or empty. Check SOPS decryption services."
        fi
      }

      check_key_pair() {
        local name=$1
        local key=$2
        local certificate=$3
        local key_public
        local certificate_public

        if ! key_public=$(openssl pkey -in "$key" -pubout 2>/dev/null); then
          fail "$name private key is invalid: $key"
        fi
        if ! certificate_public=$(openssl x509 -in "$certificate" -pubkey -noout 2>/dev/null); then
          fail "$name certificate is invalid: $certificate"
        fi
        if [[ $key_public != "$certificate_public" ]]; then
          fail "$name private key and certificate do not match."
        fi
      }

      while [[ $# -gt 0 ]]; do
        case $1 in
          -h | --help)
            usage
            exit 0
            ;;
          --dry-run)
            dry_run=true
            shift
            ;;
          --flake)
            if [[ $# -lt 2 || -z $2 ]]; then
              usage >&2
              exit 2
            fi
            flake_reference=$2
            shift 2
            ;;
          *)
            usage >&2
            exit 2
            ;;
        esac
      done

      if [[ -n $flake_reference ]]; then
        flake_uri=''${flake_reference%%#*}
        configuration_name=''${flake_reference#*#}
        if [[ $flake_uri == "$flake_reference" || -z $flake_uri || -z $configuration_name ]]; then
          fail "The flake reference must have the form <flake>#<configuration>."
        fi
        case $flake_uri in
          . | ./* | ../* | /*) flake_uri=$(realpath -m -- "$flake_uri") ;;
        esac
      fi

      disk=${pkgs.lib.escapeShellArg target.disk}
      disko_script=${pkgs.lib.escapeShellArg target.diskoScript}
      encrypted_root=${pkgs.lib.escapeShellArg target.encryptedRoot}
      luks_device=${pkgs.lib.escapeShellArg target.luksDevice}
      target_system=${pkgs.lib.escapeShellArg target.systemClosure}

      log_info "Checking installer privileges"
      if [[ $EUID -ne 0 ]]; then
        fail "This installer must run as root."
      fi
      log_success "Running as root"

      if [[ -n $flake_reference ]]; then
        log_info "Validating target configuration from $flake_reference"
        if ! target_metadata=$(nix eval --impure --raw \
          --argstr flakeUri "$flake_uri" \
          --argstr configurationName "$configuration_name" \
          --expr '
            { flakeUri, configurationName }:
            let
              flake = builtins.getFlake flakeUri;
              configuration = builtins.getAttr configurationName flake.nixosConfigurations;
              target = import ${./installer-target.nix} { inherit configuration; };
            in
              builtins.toJSON {
                inherit (target) disk encryptedRoot luksDevice;
                flakeUri = flake.outPath;
              }
          '); then
          fail "The target configuration is not a valid installer target. No disk changes were made."
        fi
        disk=$(jq --exit-status --raw-output '.disk' <<<"$target_metadata")
        encrypted_root=$(jq --exit-status --raw-output '.encryptedRoot' <<<"$target_metadata")
        luks_device=$(jq --exit-status --raw-output '.luksDevice' <<<"$target_metadata")
        resolved_flake_uri=$(jq --exit-status --raw-output '.flakeUri' <<<"$target_metadata")
        installable="$resolved_flake_uri#nixosConfigurations.$configuration_name.config.system.build"
        log_info "Building target NixOS system and disko script from $flake_reference"
        if ! target_system=$(nix build --no-link --print-out-paths "''${installable}.toplevel"); then
          fail "Could not build target NixOS system from $flake_reference. No disk changes were made."
        fi
        if ! disko_script=$(nix build --no-link --print-out-paths "''${installable}.diskoScript"); then
          fail "Could not build target disko script from $flake_reference. No disk changes were made."
        fi
        if [[ $target_system == *$'\n'* || ! -d $target_system ]]; then
          fail "The flake reference did not produce exactly one realised system closure. No disk changes were made."
        fi
        if [[ $disko_script == *$'\n'* || ! -x $disko_script ]]; then
          fail "The flake reference did not produce exactly one executable disko script. No disk changes were made."
        fi
        log_success "Validated and built target configuration from $flake_reference"
      else
        log_info "Checking the bundled target NixOS system and disko script"
        if ! nix-store --realise "$target_system" "$disko_script" >/dev/null; then
          fail "The bundled target is incomplete. No disk changes were made."
        fi
        log_success "Bundled target configuration is complete"
      fi

      log_info "Checking target disk"
      if [[ ! -b $disk ]]; then
        fail "Expected installation disk $disk was not found."
      fi
      if [[ $(lsblk -dnro TYPE "$disk") != disk ]]; then
        fail "$disk is not a whole disk."
      fi
      previous_install_mounts=false
      while IFS= read -r mountpoint; do
        if [[ -z $mountpoint ]]; then
          continue
        fi
        case $mountpoint in
          /mnt | /mnt/*) previous_install_mounts=true ;;
          *) fail "$disk is mounted at $mountpoint; refusing to treat it as an interrupted installation." ;;
        esac
      done < <(lsblk -nrpo MOUNTPOINTS "$disk")
      if [[ $previous_install_mounts == true ]]; then
        log_warning "Found mounts from a previous installation attempt under /mnt; they will be cleaned up after confirmation."
      else
        log_success "$disk is an unmounted whole disk"
      fi

      log_info "Checking Secure Boot"
      if ! mokutil --sb-state | grep -q "SecureBoot enabled"; then
        fail "Secure Boot must be enabled before installation."
      fi
      log_success "Secure Boot is enabled"

      log_info "Checking restored Secure Boot keys"
      secure_boot_directory=/var/lib/sbctl
      check_secret "$secure_boot_directory/GUID"
      check_secret "$secure_boot_directory/keys/PK/PK.key"
      check_secret "$secure_boot_directory/keys/PK/PK.pem"
      check_secret "$secure_boot_directory/keys/KEK/KEK.key"
      check_secret "$secure_boot_directory/keys/KEK/KEK.pem"
      check_secret "$secure_boot_directory/keys/db/db.key"
      check_secret "$secure_boot_directory/keys/db/db.pem"
      guid=$(<"$secure_boot_directory/GUID")
      if [[ ! $guid =~ ^[[:xdigit:]]{8}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{12}$ ]]; then
        fail "Secure Boot GUID is not a valid UUID."
      fi
      check_key_pair PK "$secure_boot_directory/keys/PK/PK.key" "$secure_boot_directory/keys/PK/PK.pem"
      check_key_pair KEK "$secure_boot_directory/keys/KEK/KEK.key" "$secure_boot_directory/keys/KEK/KEK.pem"
      check_key_pair db "$secure_boot_directory/keys/db/db.key" "$secure_boot_directory/keys/db/db.pem"
      log_success "SOPS restored a complete and internally consistent sbctl key hierarchy"

      if [[ $dry_run == true ]]; then
        log_success "All preflight checks passed. No disk changes were made."
        exit 0
      fi

      prompt_interrupted() {
        printf '\n'
        log_warning "Installation interrupted. No disk changes were made."
        exit 130
      }
      trap prompt_interrupted INT

      log_warning "Disko will ask for the LUKS password while formatting the encrypted root."
      log_warning "This password is the normal disk unlock method and will remain enrolled after installation."
      log_warning "This will permanently erase $disk and install ${hostName}."
      if ! IFS= read -r -p "Type ${hostName} to continue: " confirmation; then
        fail "Could not read installation confirmation. No disk changes were made."
      fi
      if [[ $confirmation != ${pkgs.lib.escapeShellArg hostName} ]]; then
        log_warning "Aborted. No disk changes were made."
        exit 1
      fi
      trap - INT

      installation_started=true
      installation_state="preparing installation"
      installation_risk="No disk data has been changed yet."

      installation_failed() {
        local status=$1
        trap - ERR INT
        log_error "Installation stopped while $installation_state."
        log_warning "$installation_risk"
        log_info "After resolving the failure, rerun install-system; it will restart by reformatting $disk."
        exit "$status"
      }

      installation_interrupted() {
        printf '\n'
        installation_failed 130
      }

      begin_step() {
        installation_state=$1
        installation_risk=$2
        log_info "$3"
      }

      trap 'installation_failed $?' ERR
      trap installation_interrupted INT

      unset confirmation

      begin_step \
        "cleaning up a previous installation attempt" \
        "The target has not been reformatted by this run; stale mounts or mappings may remain." \
        "Cleaning up previous installation state"
      if [[ $previous_install_mounts == true ]]; then
        umount --recursive /mnt
      fi
      if cryptsetup status "$encrypted_root" >/dev/null 2>&1; then
        cryptsetup close "$encrypted_root"
      fi
      if lsblk -nrpo MOUNTPOINTS "$disk" | grep -q '[^[:space:]]'; then
        fail "$disk still has active mounts after cleanup."
      fi
      log_success "Cleaned up previous installation state"

      begin_step \
        "partitioning and formatting $disk" \
        "The previous partition table may be gone and the new layout may be incomplete; rerunning will recreate it." \
        "Partitioning and formatting $disk"
      "$disko_script"
      log_success "Partitioned, formatted, and mounted $disk"

      begin_step \
        "verifying the new disk layout" \
        "The new disk layout exists but installation is incomplete; rerunning will reformat it." \
        "Verifying the new disk layout"
      if [[ ! -b $luks_device ]] || ! cryptsetup isLuks "$luks_device"; then
        fail "Disk formatting did not create the expected LUKS device $luks_device."
      fi
      log_success "Verified the new disk layout"

      begin_step \
        "installing the target NixOS system" \
        "The target system may be only partially installed and should not be booted; rerunning will reformat it." \
        "Installing the target NixOS system"
      TMPDIR=/tmp nixos-install --no-root-passwd --system "$target_system"
      log_success "Installed the target NixOS system"

      installation_started=false
      trap - ERR INT

      log_success "${hostName} installed with password-based LUKS unlock."
      log_info "Boot the installed system before enrolling TPM-backed unlock."
    '';
  }
