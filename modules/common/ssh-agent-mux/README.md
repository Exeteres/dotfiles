# SSH agent mux

The common module provides `exeteres.sshAgentMux`. Desktop profiles enable it
and its GNOME Keyring/GCR backend by default. Applications use
`$XDG_RUNTIME_DIR/ssh-agent-mux/agent.sock`; the user service is
`ssh-agent-mux.service`.

```nix
exeteres.sshAgentMux = {
  enable = true;
  gnomeKeyring.enable = true;
  agents = ["%t/another-agent.sock"];
  # Defaults to GNOME's socket when that backend is enabled.
  primaryAgent = "%t/gcr/ssh";
};
```

`agents` adds explicit backend sockets. GNOME's `%t/gcr/ssh` socket is included
when `gnomeKeyring.enable` is true. `primaryAgent` routes additions such as
`ssh-add`; set it to `null` to reject additions through the mux.

Set `pivy.enable = true` and configure `exeteres.pivyAgent.guid` to enable the
Pivy backend at `%t/pivy-agent/agent.sock`. This raises the default signing
timeout to 120 seconds and retains GNOME as the primary agent. See
[`../pivy-agent/README.md`](../pivy-agent/README.md) for token and slot settings.

Socket discovery is disabled at startup and in the background. With both GNOME
and Pivy disabled and `agents = []`, NixOS configuration validation fails. The packaged patch
adds `--no-discovery`, permits empty agents, and makes all identity refreshes
retain the configured backend list instead of invoking discovery.

Identities refresh automatically every 30 seconds, and after key-changing
operations through the mux. Changes made directly in a backend become visible
on the next periodic refresh. Set `identityRefreshInterval` to change this
interval; zero disables the background worker, including operation-triggered
refreshes. Refresh never scans for new sockets or watches discovery directories.

For an immediate update after changing backend keys or availability:

```sh
ssh-agent-mux refresh
ssh-agent-mux status
```

Restart `ssh-agent-mux.service` after changing the configured socket list.
The package's sandboxed regression checks cover empty configurations,
explicit-only refresh, primary-agent additions, signing, and socket permissions.
