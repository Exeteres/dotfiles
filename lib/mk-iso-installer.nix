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
    modules = [(import ../modules/images/iso.nix {installer = installerPackage;})] ++ modules;
  };
  isoImage = configuration.config.system.build.isoImage;
  kernelPath = "/boot/${configuration.config.boot.kernelPackages.kernel}/${configuration.config.system.boot.loader.kernelFile}";
in
  pkgs.writeShellApplication {
    name = "iso";
    runtimeInputs = with pkgs; [binutils coreutils gnugrep mtools pv sbsigntool util-linux xorriso];
    text = ''
      ${logging}
      ${sudo}

      usage() {
        cat <<EOF
      Usage:
        iso build <target.iso>
        iso write </dev/disk>
      EOF
      }

      sign_iso() (
        source=$1
        output=$2
        key=/var/lib/sbctl/keys/db/db.key
        certificate=/var/lib/sbctl/keys/db/db.pem
        shim=${pkgs.shim-unsigned}/share/shim/shimx64.efi
        work=$(mktemp -d)
        trap 'rm -rf "$work"' EXIT

        if ! "''${sudo_command[@]}" "$(command -v stat)" "$key" >/dev/null \
          || ! "''${sudo_command[@]}" "$(command -v stat)" "$certificate" >/dev/null; then
          log_error "Secure Boot signing keys are unavailable in /var/lib/sbctl."
          exit 1
        fi

        log_info "Extracting ISO Secure Boot artifacts"
        xorriso -osirrox on -indev "$source" \
          -extract /EFI/BOOT/BOOTX64.EFI "$work/grubx64.unsigned.efi" \
          -extract ${kernelPath} "$work/kernel.unsigned.efi" \
          -extract /boot/efi.img "$work/efi.img"

        cat >"$work/sbat.csv" <<'EOF'
      sbat,1,SBAT Version,sbat,1,https://github.com/rhboot/shim/blob/main/SBAT.md
      grub,6,Free Software Foundation,grub,${pkgs.grub2_efi.version},https://www.gnu.org/software/grub/
      grub.nixos,1,NixOS,grub,${pkgs.grub2_efi.version},https://nixos.org/
      EOF
        sbat_vma=
        while read -r field value _; do
          if [[ $field == SizeOfImage ]]; then
            sbat_vma=$value
            break
          fi
        done < <(objdump -p "$work/grubx64.unsigned.efi")
        if [[ ! $sbat_vma =~ ^[[:xdigit:]]+$ ]]; then
          log_error "Could not determine the GRUB PE image size for SBAT placement."
          exit 1
        fi
        objcopy \
          --add-section .sbat="$work/sbat.csv" \
          --set-section-flags .sbat=contents,alloc,load,readonly,data \
          --change-section-vma .sbat="0x$sbat_vma" \
          "$work/grubx64.unsigned.efi" \
          "$work/grubx64.sbat.efi"
        actual_sbat_vma=
        while read -r _ section _ vma _; do
          if [[ $section == .sbat ]]; then
            actual_sbat_vma=$vma
            break
          fi
        done < <(objdump -h "$work/grubx64.sbat.efi")
        if [[ ! $actual_sbat_vma =~ ^[[:xdigit:]]+$ ]] \
          || (( 16#$actual_sbat_vma != 16#$sbat_vma )); then
          log_error "The GRUB SBAT section was not placed at a valid PE address."
          exit 1
        fi
        objcopy \
          --dump-section .sbat="$work/sbat.injected.csv" \
          "$work/grubx64.sbat.efi" \
          "$work/grubx64.checked.efi"
        grep -q '^grub,6,' "$work/sbat.injected.csv"

        log_info "Signing the ISO shim, GRUB bootloader, and kernel"
        "''${sudo_command[@]}" "$(command -v sbsign)" \
          --key "$key" \
          --cert "$certificate" \
          --output "$work/BOOTX64.EFI" \
          "$shim"
        "''${sudo_command[@]}" "$(command -v sbsign)" \
          --key "$key" \
          --cert "$certificate" \
          --output "$work/grubx64.efi" \
          "$work/grubx64.sbat.efi"
        "''${sudo_command[@]}" "$(command -v sbsign)" \
          --key "$key" \
          --cert "$certificate" \
          --output "$work/kernel.efi" \
          "$work/kernel.unsigned.efi"
        "''${sudo_command[@]}" "$(command -v sbverify)" \
          --cert "$certificate" \
          "$work/BOOTX64.EFI"
        "''${sudo_command[@]}" "$(command -v sbverify)" \
          --cert "$certificate" \
          "$work/grubx64.efi"
        "''${sudo_command[@]}" "$(command -v sbverify)" \
          --cert "$certificate" \
          "$work/kernel.efi"

        chmod u+w "$work/efi.img"
        mcopy -o -i "$work/efi.img" \
          "$work/BOOTX64.EFI" \
          ::/EFI/BOOT/BOOTX64.EFI
        mcopy -o -i "$work/efi.img" \
          "$work/grubx64.efi" \
          ::/EFI/BOOT/grubx64.efi

        rm -f "$output"
        log_info "Rebuilding the hybrid ISO with signed EFI artifacts"
        xorriso -indev "$source" \
          -outdev "$output" \
          -boot_image any replay \
          -map "$work/BOOTX64.EFI" /EFI/BOOT/BOOTX64.EFI \
          -map "$work/grubx64.efi" /EFI/BOOT/grubx64.efi \
          -map "$work/kernel.efi" ${kernelPath} \
          -map "$work/efi.img" /boot/efi.img \
          -commit

        xorriso -osirrox on -indev "$output" \
          -extract /EFI/BOOT/BOOTX64.EFI "$work/BOOTX64.final.EFI"
        "''${sudo_command[@]}" "$(command -v sbverify)" \
          --cert "$certificate" \
          "$work/BOOTX64.final.EFI"
        xorriso -osirrox on -indev "$output" \
          -extract /EFI/BOOT/grubx64.efi "$work/grubx64.final.efi"
        "''${sudo_command[@]}" "$(command -v sbverify)" \
          --cert "$certificate" \
          "$work/grubx64.final.efi"
        objcopy \
          --dump-section .sbat="$work/sbat.final.csv" \
          "$work/grubx64.final.efi" \
          "$work/grubx64.final.checked.efi"
        grep -q '^grub,6,' "$work/sbat.final.csv"
        xorriso -osirrox on -indev "$output" \
          -extract ${kernelPath} "$work/kernel.final.efi"
        "''${sudo_command[@]}" "$(command -v sbverify)" \
          --cert "$certificate" \
          "$work/kernel.final.efi"
        mcopy -i "$work/efi.img" \
          ::/EFI/BOOT/BOOTX64.EFI \
          "$work/BOOTX64.embedded.EFI"
        "''${sudo_command[@]}" "$(command -v sbverify)" \
          --cert "$certificate" \
          "$work/BOOTX64.embedded.EFI"
        mcopy -i "$work/efi.img" \
          ::/EFI/BOOT/grubx64.efi \
          "$work/grubx64.embedded.efi"
        "''${sudo_command[@]}" "$(command -v sbverify)" \
          --cert "$certificate" \
          "$work/grubx64.embedded.efi"
        log_success "Signed and verified both ISO shim-to-GRUB chains and the kernel"
      )

      images=(${isoImage}/iso/*.iso)
      if [[ ''${#images[@]} -ne 1 || ! -f ''${images[0]} ]]; then
        log_error "Expected exactly one ISO image in ${isoImage}/iso."
        exit 1
      fi
      image=''${images[0]}

      if [[ $# -ne 2 ]]; then
        usage >&2
        exit 2
      fi

      if ! locate_privilege_escalation; then
        log_error "ISO signing requires root or a setuid sudo executable."
        exit 1
      fi

      case $1 in
        build)
          target=$(realpath -m -- "$2")
          log_info "Building the signed ${hostName} ISO at $target"
          mkdir -p "$(dirname "$target")"
          temporary=$(mktemp "$(dirname "$target")/.${hostName}-iso.XXXXXXXX")
          trap 'rm -f "$temporary"' EXIT
          sign_iso "$image" "$temporary"
          chmod 0644 "$temporary"
          mv -fT "$temporary" "$target"
          trap - EXIT
          log_success "Built $target"
          ;;
        write)
          device=$(realpath -e -- "$2")
          if [[ ! -b $device ]]; then
            log_error "$device is not a block device."
            exit 1
          fi
          if [[ $(lsblk -dnro TYPE "$device") != disk ]]; then
            log_error "$device is not a whole disk."
            exit 1
          fi

          mounted_devices=()
          while read -r mounted_device mountpoint; do
            if [[ -z $mountpoint ]]; then
              continue
            fi
            case $mountpoint in
              / | /boot | /boot/* | /etc | /etc/* | /home | /home/* | /nix | /nix/* | /usr | /usr/* | /var | /var/*)
                log_error "$mounted_device is mounted at system path $mountpoint; refusing to overwrite $device."
                exit 1
                ;;
            esac
            mounted_devices+=("$mounted_device")
          done < <(lsblk -nrpo NAME,MOUNTPOINT "$device")

          signed_image=$(mktemp "''${TMPDIR:-/tmp}/.${hostName}-iso.XXXXXXXX")
          trap 'rm -f "$signed_image"' EXIT
          sign_iso "$image" "$signed_image"

          image_size=$(stat --format=%s "$signed_image")
          device_size=$("''${sudo_command[@]}" "$(command -v blockdev)" --getsize64 "$device")
          if (( device_size < image_size )); then
            log_error "$device has $device_size bytes but the signed ISO requires $image_size bytes."
            exit 1
          fi

          log_warning "This will permanently overwrite $device with the signed ISO."
          if [[ ''${#mounted_devices[@]} -gt 0 ]]; then
            log_warning "Mounted filesystems on $device will be unmounted first."
          fi
          read -r -p "Type $device to continue: " confirmation
          if [[ $confirmation != "$device" ]]; then
            log_warning "Aborted."
            exit 1
          fi

          if [[ ''${#mounted_devices[@]} -gt 0 ]]; then
            log_info "Unmounting filesystems on $device"
            for ((index = ''${#mounted_devices[@]} - 1; index >= 0; index--)); do
              "''${sudo_command[@]}" "$(command -v umount)" --all-targets "''${mounted_devices[index]}"
            done
            if lsblk -nrpo MOUNTPOINT "$device" | grep -q '[^[:space:]]'; then
              log_error "$device still has active filesystems after unmounting; refusing to overwrite it."
              exit 1
            fi
            log_success "Unmounted filesystems on $device"
          fi

          log_info "Writing the ${hostName} ISO to $device"
          pv --size "$image_size" --bytes --progress --timer --eta --rate "$signed_image" \
            | "''${sudo_command[@]}" "$(command -v dd)" \
              of="$device" \
              bs=16M \
              iflag=fullblock \
              oflag=direct \
              status=none
          log_info "Flushing the device write cache"
          "''${sudo_command[@]}" "$(command -v blockdev)" --flushbufs "$device"
          log_success "Wrote and flushed $device"
          ;;
        *)
          usage >&2
          exit 2
          ;;
      esac
    '';
  }
