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
        sopsFile = ../../secrets/password.yaml;
        key = "hashed-password";
        neededForUsers = true;
      };
    }
    (lib.mkIf config.services.flatpak.enable {
      age_key = {
        sopsFile = ../../secrets/age-key.json;
        format = "binary";
        path = "/home/exeteres/.config/age/key";
        owner = "exeteres";
      };
    })
  ];
}
