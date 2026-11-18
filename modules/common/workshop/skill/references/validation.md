# Transfer, bootstrap and validation patterns

Generalized lessons from recorded development sessions, not universal recovery
commands. Follow the current repository's documented workflow and preserve its
safety boundaries.

## Complete source without leaking state

- Inventory tracked edits, required untracked source and package-manager patches
  before syncing. A successful tracked-only dry run can still omit needed files.
  Do not stage another author's work just to make a helper transfer it.
- A conservative helper may refuse legitimate internal schema links or submodules.
  Inspect each source and resolved target against the checkout boundary. Keep the
  default guard; use a separately reviewed manifest/archive if required, preserving
  only verified internal links and excluding unneeded submodules. Rsync's safe-link
  handling is defense in depth, not a substitute for reviewing the manifest.
- A reviewed HEAD archive plus an explicit edited/new-file delta is a fresh-workspace
  alternative. HEAD alone omits working-tree changes; a whole-checkout archive can
  leak credentials, databases and caches. Review both manifests.
- Sync does not remove stale source. Prefer a fresh workspace after deletions or
  branch changes; cleanup of an existing workspace must be explicitly scoped.
- Keep registry/cloud credentials and private manifests local. Publish only
  sanitized aggregate evidence, not raw browser payloads, databases or job logs.

## Bootstrap is part of the dependency graph

- Pin runtimes and tools together using the repository's Nix environment first.
  A successful package install need not build/relink an internal workspace CLI.
  Discover documented bootstrap steps rather than guessing their order.
- Warm caches can hide missing harness prerequisites. Validate a clean environment
  as well as warm iteration, and fix missing edges in the owning build graph.
- Avoid concurrently generating and consuming the same framework output directory.
  Separate workspaces or serialize prepare/build/typecheck/test tasks that share
  generated configuration. A failed concurrent batch is not a successful timing.
- A stale compiled package can break the very CLI needed to rebuild it. Inspect
  that bootstrap cycle and use the repository's supported recovery entry point.
  One recorded incident recovered through its bootstrap procedure and then passed
  typechecks and production browser validation; repeated task-runner retries or
  broad cache deletion were not established remedies.

## Verify the actual runtime

- Install browsers through the locked test-harness dependency or an explicitly
  exact runner. An unpinned convenience command can install an incompatible browser
  revision while still exiting zero. Match browser binaries to the harness, not
  merely to the browser family.
- Record whether timing includes production build, browser tests, dependencies,
  source transfer or provisioning. Do not report build-plus-test time as isolated
  browser performance.
- Use disposable backend state and validate frontend resources, HMR/events and
  WebSockets where relevant. An HTTP 200 or a ready backend is insufficient.
- Validate the staged/published artifact itself, not just the source checkout or
  a previously running server. Integrity/schema checks prove a narrower contract
  than full runtime tests; name exactly what passed.

## Transfer and resource failures

- The managed `pull` helper expects a directory. Put a single image/package archive
  in a dedicated remote artifact directory, then pull that directory. Retry a failed
  transfer from the successful build output; do not rebuild just to fix its path.
- Preserve a known compatible local artifact as a potential rsync basis, but measure
  actual matched/literal bytes. Large compressed archives may transfer mostly anew.
- Refresh only owned SSH sessions after legitimate Docker-group provisioning.
  Never bypass socket permissions or disrupt concurrent builders.
- Check memory, disk and owned-builder cache usage before large jobs. Historical
  readings are not capacity guarantees. Reclaim only approved, owned cache scope;
  do not prune shared images/volumes to manufacture benchmark headroom.
