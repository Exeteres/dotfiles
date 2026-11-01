# Dotfiles

NixOS and Home Manager configuration for **rebecca** and other external systems, with reusable system and
home modules, SOPS secrets, and installer helpers.

- `hosts/rebecca/`: hardware, storage, and host secrets.
- `modules/`: shared system, desktop, and home configuration.
- `users/`: user profiles.
- `lib/`: installer and maintenance helpers.

## Setup

With Nix installed, enable the repository hooks once per clone and decrypt the
private modules using an authorized SOPS age identity:

```sh
scripts/private-nix install
export SOPS_AGE_KEY_FILE="$PWD/hosts/rebecca/secrets/age-tpm-identity"
scripts/private-nix decrypt
```

The TPM identity requires access to Rebecca's TPM; the YubiKey identity is an
alternative. See [private-module setup](scripts/README.md) for details.

Hooks decrypt after merges/rebases and encrypt and stage private modules before
commits. Edit `private.nix` or `*.private.nix`; only their `.enc` counterparts
belong in Git.

## Check and build

Use `path:.` so Nix includes ignored, decrypted private modules:

```sh
nix flake check path:. --no-build
nix build path:.#nixosConfigurations.rebecca.config.system.build.toplevel
```

Format Nix files with Alejandra. Review the disk configuration before installing
or deploying: it defines an encrypted Btrfs layout and an impermanent root.
