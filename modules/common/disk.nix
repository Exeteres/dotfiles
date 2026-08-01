{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.exeteres.disk;
in {
  options.exeteres.disk = {
    enable = lib.mkEnableOption "the Exeteres impermanent Btrfs disk layout";
    device = lib.mkOption {
      type = lib.types.str;
      description = "Stable path to the disk that disko may erase.";
    };
    retentionDays = lib.mkOption {
      type = lib.types.ints.unsigned;
      default = 30;
      description = "Number of days to retain rotated Btrfs root subvolumes.";
    };
    swapSize = lib.mkOption {
      type = lib.types.str;
      default = "40G";
      description = "Size of the swap file created in the dedicated Btrfs subvolume.";
    };
  };

  config = lib.mkIf cfg.enable {
    boot.initrd.systemd.enable = true;
    boot.initrd.luks.devices.cryptroot.keyFile = lib.mkForce null;

    boot.initrd.systemd.services.rotate-impermanent-root = {
      description = "Rotate the ephemeral Btrfs root";
      wantedBy = ["initrd.target"];
      # successful resume transfers control to the saved kernel before rotation
      after = ["dev-mapper-cryptroot.device" "systemd-hibernate-resume.service"];
      before = ["sysroot.mount"];
      unitConfig.DefaultDependencies = "no";
      serviceConfig.Type = "oneshot";
      path = [pkgs.btrfs-progs pkgs.coreutils pkgs.findutils pkgs.util-linux];
      script = ''
        mkdir -p /btrfs
        mount -o subvolid=5 /dev/mapper/cryptroot /btrfs

        if [[ -e /btrfs/root ]]; then
          timestamp=$(date --date="@$(stat -c %Y /btrfs/root)" "+%Y-%m-%d_%H:%M:%S")
          mv /btrfs/root "/btrfs/old_roots/$timestamp"
        fi

        delete_subvolume_recursively() {
          while IFS= read -r subvolume; do
            delete_subvolume_recursively "/btrfs/$subvolume"
          done < <(btrfs subvolume list -o "$1" | cut -f 9- -d ' ')
          btrfs subvolume delete "$1"
        }

        while IFS= read -r old_root; do
          delete_subvolume_recursively "$old_root"
        done < <(find /btrfs/old_roots -mindepth 1 -maxdepth 1 -mtime +${toString cfg.retentionDays})

        btrfs subvolume create /btrfs/root
        umount /btrfs
      '';
    };

    disko.devices.disk.main = {
      type = "disk";
      inherit (cfg) device;
      content = {
        type = "gpt";
        partitions = {
          ESP = {
            size = "1G";
            type = "EF00";
            content = {
              type = "filesystem";
              format = "vfat";
              mountpoint = "/boot";
              mountOptions = ["umask=0077"];
            };
          };
          root = {
            size = "100%";
            content = {
              type = "luks";
              name = "cryptroot";
              settings.allowDiscards = true;
              content = {
                type = "btrfs";
                extraArgs = ["-f"];
                subvolumes = {
                  "/root" = {
                    mountpoint = "/";
                    mountOptions = ["compress=zstd" "noatime"];
                  };
                  "/old_roots" = {};
                  "/nix" = {
                    mountpoint = "/nix";
                    mountOptions = ["compress=zstd" "noatime"];
                  };
                  "/persistent" = {
                    mountpoint = "/persistent";
                    mountOptions = ["compress=zstd" "noatime"];
                  };
                  "/swap" = {
                    mountpoint = "/.swapvol";
                    swap.swapfile.size = cfg.swapSize;
                  };
                };
              };
            };
          };
        };
      };
    };

    fileSystems."/".neededForBoot = true;
    fileSystems."/nix".neededForBoot = true;
    fileSystems."/persistent".neededForBoot = true;

    environment.persistence."/persistent" = {
      hideMounts = true;
      directories = [
        "/etc/NetworkManager/system-connections"
        "/etc/ssh"
        "/root/.config/sops"
        "/var/lib/NetworkManager"
        "/var/lib/bluetooth"
        "/var/lib/nixos"
        "/var/lib/osquery"
        "/var/log"
      ];
      files = ["/etc/machine-id"];
    };
  };
}
