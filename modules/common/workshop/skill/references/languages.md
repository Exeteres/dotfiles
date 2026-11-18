# Language and toolchain patterns

These are starting points, not commands that override a project's guides.

| Ecosystem | Good remote work | Stable layers / local assembly caveats |
| --- | --- | --- |
| JavaScript / TypeScript | Typecheck, lint, unit/e2e batches, production bundling | Pin Node/Bun and lockfile; frozen install remotely. Reuse package-store caches per lock/toolchain. Do not copy native node_modules cross-platform. Bundlers may externalize workspace packages: transfer their compiled outputs too when changed. Nuxt/Vite dev needs frontend, HMR and event ports; verify in browser. |
| Rust | cargo test/clippy, release builds | Pin rust-toolchain and Cargo.lock; use --locked. Remote target cache or sccache, never assume target is portable. Linux executable is usable locally only with matching architecture/libc/linker contract; cross-compile deliberately. Keep Cargo registry/target out of source sync. |
| Go | go test, race tests, compile | Pin Go and go.sum; use module/build caches. CGO needs matching C toolchain/libc. Pure Go cross-builds can target a local OS/arch but tests still execute on the remote platform. |
| Python | pytest batches, mypy/ruff, wheel builds | Lock interpreter/dependencies and create a remote venv. Transfer source or compatible wheels, never a venv. Compiled wheels must match platform/Python ABI; pure-Python outputs are easier to reuse locally. |
| C / C++ | CMake/Ninja builds, tests, static analysis | Separate build directories, matching compiler/sysroot, ccache/sccache. Do not reuse path-dependent object/build trees blindly. Export final libraries/binaries plus required ABI/runtime manifest; debug paths may need mapping. |
| JVM | Gradle/Maven test/compile/package | Pin JDK/build wrapper; reuse caches. Transfer JARs/resources and keep compatible JRE locally. Native/JNI and platform-specific tests are separate. |
| .NET | dotnet test/build/publish | Pin SDK/global.json and restore lock; preserve NuGet cache. Framework-dependent output can reuse a matching local runtime; RID/native assets constrain portability. |
| Nix | Explicit remote builder for derivations | Prefer Nix's supported SSH builders and substitution over copying build directories. Match systems/features/trust; use least-privilege builder accounts. Nix store closures are stable layers, but copying a closure can cost more than the build. Never forward signing keys or broaden trusted-users casually. |

Across ecosystems: split build/test from runtime state. Remote e2e suites need
disposable data, unique ports/sockets and cleanup, not copies of personal databases.
Use the owning repository's harness. Stable dependencies are allowed; a fully
self-contained artifact is unnecessary when an explicit compatible local layer
exists. Invalidate that layer deliberately when its inputs change.

## Minimal-host JavaScript bootstrap fallback

Prefer the pinned repository environment. If a workspace-private toolchain is
needed, record its version and pass its bin path explicitly to remote jobs.
When `unzip` is absent, Python's standard-library `python3 -m zipfile -e` can
extract a checksum-verified Bun ZIP; it may not preserve executable permissions.
Set the executable bit only on the intended binary and verify `bun --version`.
If a `bunx` shim is absent, use `bun x`. These are bootstrap remedies, not measured
warm-iteration speedups. Browser provisioning must use the locked harness runner;
see `validation.md` before assuming a successful download is compatible.
