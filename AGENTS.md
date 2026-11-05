# Repository instructions

- Create `README.md` files only when explicitly requested by the user.
- Use single-line Conventional Commit messages: `type(scope): imperative summary`,
  with an optional scope and a lowercase summary, e.g.
  `refactor(secrets): share encrypted credentials across hosts`.
- This repository configures NixOS host `rebecca` and Home Manager. Keep shared
  configuration in `modules/`, host specifics in `hosts/rebecca/`, and user
  profiles in `users/`.
- When a module grows into a directory, move its entry point from `name.nix`
  to `name/default.nix`, update relative paths, and import the directory.
- Preserve existing staged and unstaged work. Do not stage or commit unless
  asked; the installed pre-commit hook stages encrypted private modules.
- Do not deploy, switch configurations, modify disks/bootloaders, or reboot
  without explicit authorization.
- Use `path:.` in Nix flake commands; Git-backed sources omit ignored private
  modules. Validate with `nix flake check path:. --no-build` and
  `git diff --check`; format Nix with Alejandra.
- Private module names are `private.nix` or `*.private.nix`; plaintext is ignored.
  Track only `private.nix.enc` / `*.private.nix.enc`, managed by SOPS through
  `scripts/private-nix`. Never force-add plaintext or print decrypted secrets.
- Read `scripts/README.md` before changing the encryption workflow. Keep
  credentials in runtime SOPS secrets: imported private Nix enters the Nix store.
