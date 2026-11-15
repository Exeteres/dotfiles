---
name: Remote Work
description: Offload builds, tests and other CPU-heavy work to SSH machines while keeping OpenCode, editing and optional runtime assembly local. Maintain VM access, synchronize source and artifact deltas, benchmark alternatives, and manage loopback tunnels.
---

# Remote work

Keep OpenCode and the authoritative checkout local. Treat the remote checkout,
dependencies and caches as replaceable. Use this skill for generic development
and build machines, not production deployment or infrastructure teardown.

## First steps

1. Read the repository's agent and development/testing guides. Discover its actual
   toolchain, lockfiles, build boundaries and test harness; do not assume commands.
2. Use the managed `remote-work` command (source: `scripts/remote-work.py`). Run
   `remote-work --help` and `remote-work COMMAND --help` before unfamiliar actions.
3. Choose an existing SSH alias and a dedicated absolute remote workspace beneath
   the login user's home. On Rebecca the generic build host alias is `dev`.
   `remote-work doctor dev` checks noninteractive access and remote capabilities.
   Its public identity selector is NixOS managed; the private key remains in the
   unlocked Bitwarden agent. Do not export keys, copy vault caches, disable host-key
   checking, bypass authentication, or modify cloud credentials.
4. Pin matching compiler/runtime versions and lockfiles. Never copy local native
   dependencies to a different OS/architecture. Install dependencies remotely using
   the repository's locked/frozen command, only when inputs change.

## Helpers

```sh
remote-work ssh dev                         # establish/reuse an SSH control master
remote-work sync dev "$PWD" /home/dev/work/my-project
remote-work run dev /home/dev/work/my-project -- bun run test
remote-work run dev /home/dev/work/my-project -- cargo test --locked
remote-work pull dev /home/dev/work/my-project/dist ./scratch-release/dist
remote-work tunnel dev --forward 43000:43000 --forward 43002:43002
remote-work close dev                       # only this helper's connection
```

`sync` sends **Git-tracked files only**, including local edits, from the repository
root. It excludes environment/credential/state/build paths and refuses symlinks
that could escape the checkout. It does not upload untracked files, dependencies,
submodules or remove stale remote files. Review `--dry-run` output; add needed
files to Git's index yourself or use an explicitly reviewed transfer. Use a fresh
workspace for branch switches/deleted files rather than broad remote deletion.
Exclusions are defense in depth, not a secret scanner: review unusual tracked
configuration before transfer. Helpers target Linux hosts with rsync and GNU env;
adapt deliberately for other operating systems instead of guessing portability.
Do not stage user work automatically. Remote commands are argv-quoted, not eval'd;
shell operators are literal arguments. For multi-step logic use a reviewed source
script, not generated executable strings. `run` reports wall time and exit status.

`pull` checksum-selects files and delta-compresses over SSH; it never deletes local
files. Use a fresh release directory for correctness when filenames disappear,
or pass **`--delete` only for an existing dedicated scratch artifact directory**.
It refuses the home directory, checkout root, symlink destinations and non-scratch
deletion targets; the marker `.remote-work-artifacts` authorizes that directory
only (`pull --init` initializes an empty directory). Never overwrite a live runtime
tree. Test a staging release with the project's shared isolated harness, then use
the project's supported atomic activation mechanism. Keep stable local dependencies
only where the build's external-module contract permits it; output is not always
self-contained. Refresh stable layers on lockfile/backend/compiler/ABI changes.

Tunnel binds are loopback-only, with failure-on-bind-error. Forward **all** runtime
ports (frontend, events/WebSockets, HMR, API as applicable). A 200 HTML response
does not prove that the app loads or live updates work. Test in a real browser.
Close only tunnels/masters you own; never kill arbitrary processes to free ports.

## VM maintenance

`remote-work vm status|start|stop --id ID [--folder-id FOLDER]` uses an already
authorized Yandex `yc` CLI locally. Discover/verify the resource and account first;
`start` and especially `stop` need user approval. The helper will not create,
recreate, resize, delete disks/snapshots, rotate identities or manage secrets.
For infrastructure-managed resources use the owning IaC tool instead. Never mutate
managed resources directly just because a cloud CLI is convenient. Other providers
should use their normal authenticated CLI and explicit resource IDs with the same
approval rules. No provider credentials belong on the build host.

Check free disk/RAM, pinned tools and SSH connectivity before jobs. Stop only owned
jobs. Use graceful cancellation and scoped cache pruning with approval; do not
wipe shared caches. Preemptible hosts can disappear: preserve source and results
locally, make jobs restartable, and regard remote caches as disposable.

## Choosing what to offload

Measure the full path, not just remote compiler time: source delta, dependency
refresh, build/test, output delta, local assembly and verification. Separate cold
provisioning from warm daily iteration. Run repeated same-commit/same-toolchain
trials with comparable cache states; record wall times, bytes and failures. Do not
overlap benchmark workloads on one machine. Local thermal/power/network variation
can dominate small differences. Remote jobs may be useful for CPU isolation even
without a latency win. Preserve raw logs; never publish credentials or databases.

Prefer independent test batches first. Keep interactive development local unless
real browser/HMR/event tests prove the remote loop usable. For artifact assembly,
compare checksum-selected deltas (`rsync -azc`) rather than assuming every rebuilt
file's timestamp means its content changed. Hashed entry chunks can still cause
large deltas. Do not sell an unchanged sync as a changed-build measurement.

Read `references/languages.md` for language-specific patterns and
`references/measurements.md` for an empirical example and its limitations.
