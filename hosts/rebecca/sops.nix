{
  config,
  lib,
  pkgs,
  ...
}: {
  system.activationScripts = {
    setupSopsAgeIdentity = lib.stringAfter ["specialfs"] ''
      ${pkgs.coreutils}/bin/install -m 0400 \
        ${./secrets/age-tpm-identity} \
        /run/sops-age-tpm-identity
    '';
    setupSecretsForUsers.deps = ["setupSopsAgeIdentity"];
  };

  users.users.exeteres.hashedPasswordFile = config.sops.secrets.exeteres-password.path;

  exeteres.secureBoot = {
    enable = true;
    sopsFile = ./secrets/secure-boot-keys.yaml;
  };

  sops = {
    age = {
      keyFile = "/run/sops-age-tpm-identity";
      plugins = [pkgs.age-plugin-tpm];
      sshKeyPaths = lib.mkForce [];
    };
    useSystemdActivation = true;
  };

  # These are workstation secrets; the bootstrap images only need the password
  # and Secure Boot keys above.
  sops.secrets = lib.mkMerge [
    {
      exeteres-password = {
        sopsFile = ./secrets/password.yaml;
        key = "hashed-password";
        neededForUsers = true;
      };
    }
    (lib.mkIf config.services.flatpak.enable {
      wg-feed-env = {
        sopsFile = ./secrets/vpn.json;
        format = "binary";
      };
      "ssh/private_key" = {
        sopsFile = ./secrets/ssh-private-key.json;
        format = "binary";
        path = "/home/exeteres/.ssh/id_ed25519";
        owner = "exeteres";
        group = config.users.users.exeteres.group;
        mode = "0600";
      };
      "ssh/public_key" = {
        sopsFile = ./secrets/ssh-public-key.json;
        format = "binary";
        path = "/home/exeteres/.ssh/id_ed25519.pub";
        owner = "exeteres";
        group = config.users.users.exeteres.group;
        mode = "0644";
      };
      age_key = {
        sopsFile = ./secrets/age-key.json;
        format = "binary";
        path = "/home/exeteres/.config/age/key";
        owner = "exeteres";
      };
    })
  ];
}
