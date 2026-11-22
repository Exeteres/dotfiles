{inputs}: final: previous: let
  upstream = inputs.opencode.overlays.default final previous;
in {
  opencode = upstream.opencode.overrideAttrs (old: {
    # The release's dependency hash differs with our locked Linux Bun toolchain.
    node_modules =
      if previous.stdenv.hostPlatform.system == "x86_64-linux"
      then old.node_modules.override {hash = "sha256-PYcpyYP/i0e6ZIt27u1tFYbjU4Cl848w77dU1NiIEls=";}
      else old.node_modules;
  });
  opencode-desktop = (upstream.opencode-desktop.override {opencode = final.opencode;}).overrideAttrs (old: {
    # v2.3.0's build script still checks ../cli/dist, not OPENCODE_CLI_DIST.
    buildPhase = builtins.replaceStrings ["$TMPDIR/desktop-cli"] ["$PWD/../cli/dist"] old.buildPhase;
    postPatch =
      old.postPatch
      + ''
        substituteInPlace \
          packages/desktop/src/main/windows/early.ts \
          packages/desktop/src/main/service/sidecar-probe.ts \
          --replace-fail "process.resourcesPath" "'$out/opt/opencode-desktop/resources'"

        # The pinned Nix CLI uses the prod channel. Patch Desktop's bundled
        # discovery client so both its startup probe and ensure use that file.
        substituteInPlace packages/client/src/service-probe.ts \
          --replace-fail '"opencode", "service.json"' '"opencode", "service-prod.json"'
      '';
  });
}
