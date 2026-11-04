{
  config,
  lib,
  pkgs,
}: {
  rebecca = config.system.build.toplevel;
  kernel-module-trust = let
    hasModuleCertificates = config.boot.kernelPackages ? rebuildImage;
    kernel =
      if hasModuleCertificates
      then config.boot.kernelPackages.rebuildImage {inherit (config.system) modulesTree;}
      else config.boot.kernelPackages.kernel;
    kernelPath = "${kernel}/${config.system.boot.loader.kernelFile}";
  in
    pkgs.runCommand "kernel-module-trust" {} ''
      system=${config.system.build.toplevel}
      test "$(readlink "$system/kernel")" = ${lib.escapeShellArg kernelPath}
      ${pkgs.jq}/bin/jq -e \
        --arg kernel ${lib.escapeShellArg kernelPath} \
        '."org.nixos.bootspec.v1".kernel == $kernel' "$system/boot.json"
      ${lib.optionalString hasModuleCertificates ''
        test -s ${config.system.modulesTree}/lib/modules/${config.boot.kernelPackages.kernel.modDirVersion}/modules.cer
      ''}
      touch "$out"
    '';
}
