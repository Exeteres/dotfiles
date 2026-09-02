let
  toApp = pkgs: package: {
    type = "app";
    program = pkgs.lib.getExe package;
    meta.description = "Run ${package.name}";
  };
in {
  mkIsoInstaller = args: toApp args.pkgs (import ./mk-iso-installer.nix args);
  mkInstaller = args: import ./mk-installer.nix args;
  mkKexec = args: toApp args.pkgs (import ./mk-kexec.nix args);
  mkUpdateSecrets = args: toApp args.pkgs (import ./mk-update-secrets.nix args);
}
