{lib, ...}: let
  allowedPackages = [
    # closed source
    "jetbrains-toolbox"
    "libfprint-2-tod1-broadcom"
    "vscode"
  ];
in {
  nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) allowedPackages;
}
