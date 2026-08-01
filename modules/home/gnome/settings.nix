{lib, ...}: let
  mkTuple = lib.hm.gvariant.mkTuple;
in {
  dconf.settings = {
    "org/gnome/desktop/input-sources" = {
      sources = [
        (mkTuple ["xkb" "us"])
        (mkTuple ["xkb" "us+colemak"])
        (mkTuple ["xkb" "ru"])
      ];
    };

    "org/gnome/desktop/wm/keybindings" = {
      switch-input-source = ["<Shift>space" "<Super>space"];
      switch-input-source-backward = [];

      switch-to-workspace-1 = ["<Super>q"];
      switch-to-workspace-2 = ["<Super>w"];
      switch-to-workspace-3 = ["<Super>f"];
      switch-to-workspace-4 = ["<Super>p"];
    };

    "org/gnome/desktop/wm/preferences" = {
      num-workspaces = 4;
    };

    "org/gnome/desktop/interface" = {
      enable-hot-corners = false;
      show-battery-percentage = true;
    };

    "org/gnome/desktop/peripherals/touchpad" = {
      tap-to-click = true;
    };

    "org/gnome/mutter" = {
      dynamic-workspaces = false;
      workspaces-only-on-primary = false;
      experimental-features = ["scale-monitor-framebuffer"];
    };
  };
}
