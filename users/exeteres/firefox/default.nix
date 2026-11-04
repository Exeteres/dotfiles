{
  # Honor profiles.ini's default rather than creating a per-installation profile.
  services.flatpak.overrides.settings."org.mozilla.firefox" = {
    Environment.MOZ_LEGACY_PROFILES = "1";
    # Home Manager's configuration files are symlinks into the Nix store.
    Context.filesystems = ["/nix/store:ro"];
  };

  programs.firefox = {
    enable = true;
    # Firefox itself is installed through Flatpak.
    package = null;
    configPath = ".var/app/org.mozilla.firefox/config/mozilla/firefox";

    profiles.default = {
      id = 0;
      isDefault = true;
      path = "default";
      settings = import ./settings.nix;
      userChrome = ./userChrome.css;
    };
  };
}
