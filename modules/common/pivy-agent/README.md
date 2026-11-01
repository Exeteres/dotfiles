# Pivy PIV SSH backend

Enable it through the SSH agent mux:

```nix
exeteres.pivyAgent = {
  guid = "YOUR_32_HEX_DIGIT_PIV_GUID";
  # Optional: output from pivy-tool -g <GUID> pubkey 9e.
  # cardAuthenticationKey = "ecdsa-sha2-nistp256 AAAA...";
};
exeteres.sshAgentMux.pivy.enable = true;
```

The switch enables the Pivy service and adds `%t/pivy-agent/agent.sock` to the
mux's explicit backends. GNOME remains the primary agent for additions. The
mux's default signing timeout becomes 120 seconds to allow PIN entry and touch.
Socket discovery remains disabled; identity refresh picks up Pivy once ready.

Pivy starts with the graphical session, using OpenSSH's GTK PIN prompt and touch
notifications. Its default slot filter is `!all,9a`, keeping age's retired
key-management slots out of SSH. The token GUID is required, and no token keys
or PIN policies are changed by this module.

To run the service without adding it to the mux, use
`exeteres.pivyAgent.enable = true` and configure the GUID. It does not replace
`SSH_AUTH_SOCK`; clients can address its backend socket explicitly:

```sh
SSH_AUTH_SOCK="$XDG_RUNTIME_DIR/pivy-agent/agent.sock" ssh-add -X
```

That command unlocks Pivy directly. Set `askpass = null` to use manual unlocking
instead of graphical prompts. `ssh-add -D` against the same socket forgets its
cached PIN.

Pivy uses shared PC/SC access and releases transactions between operations.
Age can continue using the same token, although overlapping PIN/touch requests
may wait and changes to shared PIV authentication state may require another PIN
prompt. This module does not hold exclusive token access.
