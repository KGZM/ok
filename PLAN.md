# kak-emporium — Build Plan

This repo is the coordination hub and documentation anchor for a suite of personal
Kakoune forks with hermetic, mise-consumable release artifacts.

---

## Quick start (local build)

```sh
mise install          # installs zig, rust, cargo-zigbuild per mise.toml
make                  # builds kak + kak-lsp for host arch → dist/local/
make run              # launches kak from dist/local/
```

`mise.toml` at the repo root pins all build toolchain dependencies.
Never install zig or rust via the system package manager for this project.

---

## Toolchain (mise-managed)

| Tool | Version | Purpose |
|------|---------|---------|
| `zig` | 0.16.0 | C++ cross-compiler for kak; musl linker for Rust |
| `rust` | stable | kak-lsp, kak-tree-sitter |
| `cargo-zigbuild` | latest | cargo subcommand that uses zig as the Rust linker |

All pinned in `mise.toml`. Run `mise install` once after cloning.

---

## Repository Map

| Repo | Purpose | Language |
|------|---------|----------|
| `kak/` | Editor binary | C++ |
| `kak-lsp/` | LSP client | Rust |
| `kak-tree-sitter/` | Tree-sitter integration | Rust |
| `anima/` | Janet program — kak config runtime | Janet |

All four live as subdirectories of this monorepo. GitHub forks of the
upstream projects; CI pushes release artifacts to GitHub releases so
mise can pull pinned versions via the `gh:` backend.

---

## Target Matrix

Linux is the primary target. macOS is deferred until everything else is done.

| Target | OS | Arch | Static? | Priority |
|--------|----|------|---------|----------|
| `x86_64-linux-musl` | Linux | x86\_64 | fully static | **1** |
| `aarch64-linux-musl` | Linux | aarch64 | fully static | **2** |
| `x86_64-apple-darwin` | macOS | x86\_64 | non-system deps only | deferred |
| `aarch64-apple-darwin` | macOS | Apple Silicon | non-system deps only | deferred |

macOS note (for later): macOS cannot produce fully-static executables.
`dyld` and `libSystem` are always dynamic. Deferred until Linux pipeline
is stable and all other components are done.

---

## Component 1 — `kak` fork (C++)

### What
Fork `mawww/kakoune`. Own the build pipeline; no dependency on upstream CI or
packaging. Pin a specific upstream commit and pull changes deliberately.

### Build strategy
kak is C++ with no runtime dependencies beyond POSIX — no ncurses, no external
libs. It implements its own terminal I/O. This makes static linking tractable.

**Linux targets — zig cc cross-compilation:**
- Zig bundles a recent Clang and musl. Invoke via `zig c++` with
  `-target x86_64-linux-musl` or `-target aarch64-linux-musl`.
- Override kak's `Makefile`: `CXX="zig c++ -target $TARGET"`.
- Pass `-static` to produce a fully-linked binary.
- Both targets build on a single `ubuntu-latest` runner (no hardware
  emulation needed — zig cross-compiles natively).

**macOS targets — native runners:**
- `macos-13` for `x86_64-apple-darwin` (Intel runner).
- `macos-14` for `aarch64-apple-darwin` (M1 runner, free tier as of 2024).
- Build with system Clang (`c++`). No zig needed.
- Link with `-stdlib=libc++`. All third-party deps (none currently) would
  be statically linked; Apple system frameworks remain dynamic.

### Technical challenges
- **C++ standard**: kak uses C++17/20. Zig's bundled Clang must match.
  Test `zig c++ --version` and verify language standard flags pass through.
- **LTO / PGO**: kak's `Makefile` may enable LTO. Zig's LTO is per-target;
  cross-LTO requires care. Disable LTO initially; add back if binary size
  matters.
- **`config.h` / version detection**: kak generates a `version.h` or
  embeds `git describe` output. The CI build must set this explicitly
  (e.g., `KAKOUNE_VERSION=$(git describe --tags)` passed as a define).
- **Runtime data**: kak ships `runtime/` (kak scripts, docs). The binary
  path-searches for these. The release artifact must include them OR the
  binary must be built with a hardcoded/relocatable runtime path.
  Preferred: embed runtime path as `~/.local/share/kak` and ship runtime
  separately, or vendor runtime into kak-config repo (see Component 4).

### Artifact naming
```
kak-{version}-x86_64-linux.tar.gz        # contains: bin/kak
kak-{version}-aarch64-linux.tar.gz
kak-{version}-x86_64-macos.tar.gz
kak-{version}-aarch64-macos.tar.gz
```

---

## Component 2 — `kak-lsp` fork (Rust)

### What
Fork `kakoune-lsp/kakoune-lsp`. Vendored runtime; no dependency on upstream
release cadence.

### Build strategy
Rust has first-class cross-compilation support.

**Linux targets:**
- Use `cargo zigbuild` (a cargo subcommand wrapping the zig linker) for
  musl targets: avoids the glibc → musl ABI incompatibility that breaks
  naive `cargo build --target x86_64-unknown-linux-musl`.
- Targets: `x86_64-unknown-linux-musl`, `aarch64-unknown-linux-musl`.
- `cargo zigbuild --release --target $TARGET`.

**macOS targets:**
- Same macOS runner strategy as kak: `macos-13` (Intel), `macos-14` (M1).
- `cargo build --release --target x86_64-apple-darwin` /
  `aarch64-apple-darwin`.
- Cross-compiling macOS targets from Linux requires the macOS SDK
  (osxcross or similar) — using native runners avoids this entirely.

### Technical challenges
- **OpenSSL / TLS deps**: kak-lsp may pull in `openssl-sys` or `rustls`.
  musl + OpenSSL requires careful feature flag selection. Prefer `rustls`
  (pure Rust TLS) over OpenSSL to avoid C dep build complexity on musl.
- **Binary size**: LSP clients tend to be large. Strip release binaries
  (`strip` on Linux, `strip -x` on macOS). Consider `opt-level = "z"` in
  `Cargo.toml` profile if size matters for mise distribution.
- **Proc-macros**: proc-macro crates always compile for the *host*, even
  during cross-compilation. This is handled automatically by cargo but
  worth knowing if builds break on aarch64-linux cross.

### Artifact naming
```
kak-lsp-{version}-x86_64-linux.tar.gz
kak-lsp-{version}-aarch64-linux.tar.gz
kak-lsp-{version}-x86_64-macos.tar.gz
kak-lsp-{version}-aarch64-linux.tar.gz
```

---

## Component 3 — `kak-tree-sitter` fork (Rust)

### What
Fork `phaazon/kak-tree-sitter` (or current upstream). Provides tree-sitter
based highlighting and text objects for kak.

### Build strategy
Mirrors kak-lsp: `cargo zigbuild` for Linux musl, native macOS runners.

### Technical challenges
- **Grammar compilation**: kak-tree-sitter compiles tree-sitter grammars
  (C/C++ code) at runtime or bundles them. If grammars are compiled at
  build time and linked statically, the C compiler used (zig cc) must
  match the cross target. If compiled at runtime, the deployed system
  needs a C compiler — undesirable for a hermetic setup.
  - Preferred path: build with grammar support disabled in the binary;
    grammars compiled separately on first run via `kak-tree-sitter install`.
    Or: pre-compile and ship grammar `.so` files as separate release assets.
- **Shared library grammars on macOS**: tree-sitter loads grammars as
  `dlopen`ed `.dylib` files. These are always dynamic by nature — no
  static linking issue, but artifact packaging must include them.
- **Cross-compiled `.so` grammars**: compiling grammar shared libs for
  `aarch64-linux` from an `x86_64` runner requires a cross-linker. Zig
  can do this: `zig cc -target aarch64-linux-musl -shared grammar.c`.

---

## Component 4 — `kak-config` repo

### What
A single repo containing:
1. Vendored `/usr/share/kak/` autoload directory (locks the kak script
   runtime to a known version, placed at `~/.config/kak/autoload/` so kak
   prefers it over the system copy).
2. A minimal `kakrc` that calls the Janet program at startup.
3. The Janet project (see Component 5).

### Vendoring strategy
Copy `/usr/share/kak/` from the target kak version into `autoload/` in this
repo. Update deliberately alongside kak binary upgrades. Diff-visible changes
make kak script updates reviewable and intentional.

```
kak-config/
├── autoload/          # vendored from /usr/share/kak/autoload/
├── kakrc              # minimal: calls janet program init subcommand
└── {janet-project}/   # see Component 5
```

### kakrc
```kak
# Delegate all configuration to the Janet program.
evaluate-commands %sh{ /path/to/janet-program init }
colorscheme generated
```

`kak-janet init` prints kak script to stdout; kak evaluates it via
`evaluate-commands %sh{}`. This is the primary injection point.

---

## Component 5 — Janet program (name TBD)

### Suggested names
- **`anima`** — Latin for *soul*, *animating principle*. Janet gives kak its
  life and meaning; this is the animating force. Short, memorable, no naming
  conflicts in the Janet ecosystem. Preferred.
- **`esprit`** — French for *spirit/wit*. Slightly longer but evocative.
- **`herald`** — It announces and registers kak commands. More literal.
- **`kami`** — Japanese for *spirit/god*. Fits the aesthetic; slightly obscure.

Recommendation: **`anima`**. Five letters, zero ambiguity, directly names what
it does in the architecture.

### What
A monolithic Janet program that IS the kak configuration. Replaces all plugins.
Built with `jpm` (Janet Package Manager) or run open-face (direct `janet`
invocation from source). Distributed as a compiled `.jimage` or as source
with `janet` as a runtime dep (pulled via mise).

### Subcommand surface (initial)
```
anima init          # print kak script to stdout; called by kakrc at startup
anima pick          # interactive file picker (fzf-based)
anima grep          # interactive grep picker
anima lsp-hover     # called by kak lsp-hover mapping
anima scratch       # open scratch buffer
```

kak mappings call these via `%sh{ anima subcommand }` and evaluate or insert
the output.

### Project structure
```
anima/
├── project.janet      # jpm project descriptor
├── src/
│   ├── main.janet     # entry point, dispatch table
│   ├── init.janet     # generates startup kak script
│   ├── pick.janet     # file/grep pickers
│   └── util.janet     # shared helpers (kak protocol, shell escaping)
└── test/
    └── util_test.janet
```

### Build / distribution
- **Development**: `janet src/main.janet` — no compilation step, instant
  iteration.
- **jpm build**: compiles to a native image or produces a standalone
  executable via `jpm` + `janet` CLI.
- **mise distribution**: ship as source + a `janet` runtime dep, OR compile
  with `janet -c` to a `.jimage` that requires only the `janet` binary.
  The `janet` binary itself is distributed via mise (GitHub backend from
  janet-lang/janet releases).

### Technical challenges
- **Shell escaping**: generating kak script from Janet that contains shell
  snippets that contain kak script is a quoting tower-of-hell. Establish a
  canonical escaping layer early (`util.janet`) and never bypass it.
- **kak ↔ process protocol**: kak passes context to `%sh{}` via environment
  variables (`kak_session`, `kak_client`, `kak_bufname`, etc.). Janet must
  read these and may need to send back kak commands via the `kak -p` pipe
  protocol for async operations (e.g., after fzf returns a selection).
- **Startup latency**: `anima init` runs at every kak startup. Keep it fast.
  The init subcommand should emit static kak script; avoid shelling out
  during init. Measured target: < 50ms.
- **jpm vs open-face**: jpm provides a build system and module resolution.
  Running open-face (`janet src/main.janet`) is simpler for development but
  loses module paths. Decision: use jpm for the project structure but make
  `janet src/main.janet` work in development via a `(import ./util)` style
  relative import path.

---

## Component 6 — GitHub Actions CI/CD

### Structure
Each fork repo gets its own `.github/workflows/release.yml`. The emporium
may hold a dispatch workflow that triggers all three.

### Release workflow (per repo)

```yaml
on:
  push:
    tags: ['v*']

jobs:
  build:
    strategy:
      matrix:
        include:
          - os: ubuntu-latest
            target: x86_64-linux
            cargo_target: x86_64-unknown-linux-musl   # Rust repos
            zig_target: x86_64-linux-musl             # kak
          - os: ubuntu-latest
            target: aarch64-linux
            cargo_target: aarch64-unknown-linux-musl
            zig_target: aarch64-linux-musl
          - os: macos-13
            target: x86_64-macos
            cargo_target: x86_64-apple-darwin
          - os: macos-14
            target: aarch64-macos
            cargo_target: aarch64-apple-darwin
    runs-on: ${{ matrix.os }}
    steps:
      - uses: actions/checkout@v4
      # ... install zig / rustup / cargo-zigbuild
      # ... build
      # ... package into .tar.gz
      - uses: actions/upload-artifact@v4
  release:
    needs: build
    runs-on: ubuntu-latest
    steps:
      - uses: actions/download-artifact@v4
      - uses: softprops/action-gh-release@v2
        with:
          files: '*.tar.gz'
```

### mise consumption
mise's GitHub (`gh:`) backend uses the `ubi` asset-matching heuristic.
Asset names must contain recognisable OS and arch tokens:

| Token | Matches |
|-------|---------|
| `linux` | Linux |
| `darwin` / `macos` | macOS |
| `x86_64` / `amd64` | Intel 64-bit |
| `aarch64` / `arm64` | ARM 64-bit |

Canonical artifact name pattern: `{name}-{version}-{arch}-{os}.tar.gz`
e.g. `kak-v1.2.3-x86_64-linux.tar.gz`.

In `mise.toml` (this repo or user's dotfiles):
```toml
[tools]
"gh:you/kak"              = "1.2.3"
"gh:you/kak-lsp"          = "0.5.0"
"gh:you/kak-tree-sitter"  = "1.0.0"
"gh:you/kak-config"       = "latest"   # or pin
```

### Zig installation in CI
```yaml
- uses: mlugg/setup-zig@v1
  with:
    version: 0.14.0   # or 'master' for latest
```

### cargo-zigbuild installation in CI
```yaml
- run: cargo install cargo-zigbuild
- run: rustup target add ${{ matrix.cargo_target }}
```

---

## Sequencing

1. **Fork kak** → add `release.yml` → verify zig cross-compile builds clean
   Linux binaries → verify macOS native builds → cut a test tag → confirm
   artifacts appear in GitHub releases → test `mise use gh:you/kak@test`.
2. **Fork kak-lsp** → same workflow pattern → verify musl build links
   correctly (OpenSSL/TLS selection) → cut test tag.
3. **Fork kak-tree-sitter** → same → decide grammar distribution strategy.
4. **Create kak-config repo** → vendor current `/usr/share/kak/autoload/` →
   create `anima/` janet project skeleton → wire `kakrc` → verify kak starts.
5. **Wire mise.toml** in this emporium repo pinning all four → smoke test
   full install from scratch.

---

## Open Questions

- **Runtime path for kak**: should kak look for its scripts in
  `~/.config/kak/autoload/` (kak-config provides them) or in a
  system path? Decision: vendor in kak-config, configure kak to use
  `~/.config/kak/` as its only runtime location. This makes the kak binary
  runtime-agnostic; the config repo owns all scripts.
- **Grammar distribution for kak-tree-sitter**: ship pre-compiled grammar
  `.so`/`.dylib` per platform in the release, or compile at first run via
  `kak-tree-sitter install`? Pre-compiled is hermetic but multiplies artifact
  count. First-run compilation requires a C compiler on the target machine.
- **`anima` distribution**: source + janet runtime (simplest), compiled
  `.jimage` (faster startup, requires janet binary), or native binary via
  `janet --nimage` / `janetc`? Start with source; decide after measuring
  startup latency.
- **macOS code signing**: unsigned binaries on macOS require Gatekeeper
  bypass (`xattr -dr com.apple.quarantine`). For personal use via mise this
  is acceptable. Document the workaround in the README.
