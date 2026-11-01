# Private Nix modules

Private modules use these names anywhere in the repository:

| Encrypted, committed | Plaintext, ignored |
| --- | --- |
| `private.nix.enc` | `private.nix` |
| `example.private.nix.enc` | `example.private.nix` |

SOPS stores the entire Nix source as an encrypted binary document in a JSON
envelope. Recipients come from `.sops.yaml` (Rebecca's TPM and YubiKey).
Plaintext files are written atomically with mode `0600`.

## Setup per clone

```sh
scripts/private-nix install
export SOPS_AGE_KEY_FILE="$PWD/hosts/rebecca/secrets/age-tpm-identity"
scripts/private-nix decrypt
```

Use `age-yubikey-identity` instead for the YubiKey. Hardware access must be
available to the current user. Alternatively configure SOPS's normal age key
discovery. Keep the key environment available to Git hooks, including GUI Git
clients. The launcher supplies Python, SOPS, and both age plugins through the
repository's locked nixpkgs; the first run may download those tools.

`install` enables this repository's `.githooks` via local `core.hooksPath` and
refuses to replace a different hooks path. Git does not enable hooks on clone.

- `post-merge`: decrypt after a merge/fast-forward, including `git pull`.
- `post-rewrite`: decrypt after a rebase, including `git pull --rebase`.
- `pre-commit`: encrypt and **stage all private modules**, including new ones.
  A SOPS failure aborts the commit. Unchanged plaintext preserves the existing
  ciphertext, avoiding encryption-only diffs.

Run `scripts/private-nix decrypt` manually after checkout/reset or a pull that
does not trigger a hook. A post-pull hook failure cannot undo the Git operation.
Resolve the error and rerun decryption before evaluating the configuration.

## Editing and building

Edit the ignored `*.private.nix` / `private.nix`, then commit normally. For
manual encryption without staging:

```sh
scripts/private-nix encrypt
```

Synchronization state lives in the Git directory. Decryption preserves local
edits when ciphertext is unchanged and refuses conflicting incoming edits.
Encryption also refuses to overwrite ciphertext that has not been synchronized.
To resolve a conflict, back up the local plaintext, remove it, decrypt the
incoming version, then reapply the intended edits. Delete both forms explicitly
when removing a module (`git rm` the encrypted form).

The modules import their decrypted siblings. **Use `path:.` for Nix commands**
because Git-backed flake sources omit ignored plaintext:

```sh
nix flake check path:. --no-build
nix build path:.#nixosConfigurations.rebecca.config.system.build.toplevel
```

Path-based flakes copy plaintext into the Nix store, as ordinary Nix imports do.
These private modules hide configuration from Git; do not put credentials in
them. Continue using runtime SOPS secrets for credentials.
