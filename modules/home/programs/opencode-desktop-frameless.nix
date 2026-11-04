{pkgs}:
pkgs.opencode-desktop.overrideAttrs (old: {
  postPatch =
    (old.postPatch or "")
    + ''
      # Native Wayland Electron decorations cannot be hidden by GNOME Unite.
      substituteInPlace packages/desktop/src/main/windows/defaults.ts \
        --replace-fail 'const frame: BrowserWindowConstructorOptions = {}' \
          'const frame: BrowserWindowConstructorOptions = process.platform === "linux" ? { frame: false } : {}'

      # Preserve tab interactions; only the surrounding header moves the window.
      cat >> packages/app/src/shell/titlebar/titlebar.css <<'EOF'

      [data-slot="titlebar-v2"], [data-slot="sidebar-header"] {
        -webkit-app-region: drag;
        app-region: drag;
      }
      [data-slot="titlebar-v2"] :is(button, a, input, textarea, select, [role="button"], [role="tab"], [role="menuitem"], [contenteditable], [draggable="true"]),
      [data-slot="sidebar-header"] :is(button, a, input, [role="button"], [role="tab"], [contenteditable], [draggable="true"]) {
        -webkit-app-region: no-drag;
        app-region: no-drag;
      }
      EOF
    '';
})
