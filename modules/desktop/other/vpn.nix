{config, ...}: {
  sops.secrets."wg-feed-env" = {
    mode = "0600";
  };

  services.wg-feed = {
    enable = true;
    logLevel = "debug";
    environmentFile = config.sops.secrets.wg-feed-env.path;

    amnezia = {
      enable = true;
      networkManagerPlugin.enable = true;
      useKernelModule = true;
    };

    feeds.main = {
      sync.endpoints = ["$SETUP_URLS"];

      backends.default.type = "networkmanager";
    };
  };
}
