{lib, ...}: let
  allowedPackages = [
    # closed source
    "jetbrains-toolbox"
    "libfprint-2-tod1-broadcom"
    "vscode"
    "yandex-cloud"

    # strange licenses
    "vault-bin"
  ];
in {
  nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) allowedPackages;
}
