{
  sops.secrets."wg-feed-env" = {
    mode = "0600";
  };

  services.wg-feed = {
    enable = true;
    logLevel = "debug";
    environmentFile = "/run/secrets/wg-feed-env";

    amnezia = {
      enable = true;
      networkManagerPlugin.enable = true;
      useKernelModule = true;
    };

    feeds.main = {
      sync.endpoints = ["$SETUP_URLS"];

      backends.default.type = "networkmanager";

      backends.netns = {
        type = "netns";

        tunnels = {
          amsterdam.enabled = true;
          malmo-1.enabled = true;
          malmo.enabled = true;
        };
      };
    };
  };
}
