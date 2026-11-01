{
  exetrouter,
  pkgs,
  ...
}: {
  environment.systemPackages = [
    exetrouter.packages.${pkgs.stdenv.hostPlatform.system}.default
  ];
}
