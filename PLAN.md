# kak-emporium — Architecture and Plan

---

## What this repo is

**overk** (this repo, `kak-emporium`) is the coordination hub for a self-contained
kakoune distribution. It:

- Pins exact versions of all upstream components via `components.toml`
- Orchestrates builds from subrepo source via `Makefile`
- Assembles the final bundle via `mise run bundle`
- Provides `ok` — the Janet program that is the editor config runtime

overk is NOT a plugin manager and NOT a dotfiles repo. It IS the editor.

---

## Operational modes

### Mode 1 — Config-only (daily use)

The normal workflow once the stack is stable. Like editing a neovim config
without rebuilding neovim.

- `kak`, `kak-lsp`, `kak-tree-sitter` binaries come from **release tarballs**
  (downloaded, not built from source). No subrepo checkouts required.
- `ok` runs from **source** (`janet src/main.janet` or the compiled `bin/ok`).
  Iterate on Janet freely; no recompile needed in dev (janet is interpreted).
- `mise run bundle` assembles from downloaded artifacts + current ok source.

Subrepos (`kak/`, `kak-lsp/`, `kak-tree-sitter/`) need not be present or
fully cloned in this mode. A future `mise run fetch` task will download
prebuilt artifacts pinned in `components.toml` instead of building from source.

### Mode 2 — Integrated development

Full stack development. All subrepos checked out, all builds from source.

- `make` builds all components from source into `dist/<target>/`
- `mise run bundle` assembles bundle from `dist/<target>/`
- Changes to kak scripts → commit to `kak/` fork
- Changes to kak-lsp config → commit to `kak-lsp/` fork
- Changes to ok config runtime → commit here

### Mode 3 — Bundle / release (end-user)

Download a pre-built overk release tarball. No source at all.
Extract, symlink onto PATH, done. No mise, no janet, no compiler.

The tarball is produced by this repo's CI and contains all binaries, all
kak scripts, grammars, and a compiled `ok` binary.

---

## Component ownership

| Component | Lives in | Notes |
|-----------|----------|-------|
| `kak` binary | `kak/` fork | zig cross-compiled, static musl |
| kak runtime scripts (rc/, autoload/, colors/) | `kak/` fork | pulled into bundle at assembly time |
| `kak-lsp` binary | `kak-lsp/` fork | static musl |
| kak-lsp rc files (lsp.kak, servers.kak) | `kak-lsp/` fork | pulled into bundle at assembly time |
| `kak-tree-sitter` + `ktsctl` binaries | `kak-tree-sitter/` fork | **glibc dynamic** (dlopen for grammars) |
| tree-sitter grammars (`.so` files) | `kak-tree-sitter/` fork build | compiled by kts build |
| `ok` janet runtime | here (`src/`) | compiled to `bin/ok` via jpm |
| bundle assembly | here (`mise/tasks/bundle`) | reads from `dist/<target>/` |

**Key rule**: kak scripts belong in the `kak/` fork, not here. overk only
pulls them in at bundle time. Edit kak scripts → commit to `kak/` fork.

---

## Version manifest

`components.toml` is the fake submodule manifest — it pins the upstream
commit and (once forks exist) the release tag for each component.

```toml
[kak]
upstream_commit = "..."
# release = "v0.0.0"   ← fill when fork CI publishes

[kak-lsp]
upstream_commit = "..."
# release = "v0.0.0"

[kak-tree-sitter]
upstream_commit = "..."
# release = "v0.0.0"
```

Bumping a `release` field is what promotes a new upstream build into the bundle.
A future `mise run fetch` task will read these and download the artifacts
without requiring full subrepo checkouts.

---

## Target matrix

| Target | kak | kak-lsp | kak-tree-sitter |
|--------|-----|---------|-----------------|
| `x86_64-linux` | static musl ✓ | static musl ✓ | **glibc dynamic** ✓ |
| `aarch64-linux` | static musl (pending) | static musl (pending) | **glibc dynamic** (pending) |
| macOS | deferred | deferred | deferred |

**kak-tree-sitter MUST be glibc dynamic on all targets.** It uses `dlopen`
to load grammar `.so` files at runtime. A musl static binary cannot dlopen.
The grammars themselves are `.so` files cross-compiled for the target arch.

---

## aarch64 build plan

### Testing

qemu-user binfmt_misc is available on this machine — cross-compiled aarch64
binaries can be tested directly by running them (the kernel transparently
invokes qemu-aarch64).

```sh
# Verify qemu binfmt_misc is active
ls /proc/sys/fs/binfmt_misc/

# Build for aarch64
make aarch64

# Test the resulting binary (qemu-user handles it transparently)
dist/aarch64-linux/bin/kak --version
dist/aarch64-linux/bin/kak-lsp --version
```

### kak (C++) — aarch64

`make aarch64` already passes `CXX="zig c++ -target aarch64-linux-musl"`.
Should work without changes — zig handles this natively.

### kak-lsp (Rust) — aarch64

`cargo zigbuild --target aarch64-unknown-linux-musl`. Needs:
- `rustup target add aarch64-unknown-linux-musl`
- `cargo-zigbuild` (already in mise.toml)

### kak-tree-sitter + grammars — aarch64 (glibc, not musl)

The binary itself: `cargo zigbuild --target aarch64-unknown-linux-gnu`
with the `direct-unix-socket` feature. Target is `linux-gnu` not `linux-musl`.

Grammars are compiled C/C++ shared libraries (`.so`). Each grammar needs to
be cross-compiled for aarch64:
```sh
zig cc -target aarch64-linux-gnu -shared -fPIC grammar.c -o grammar.so
```
The kts build system (in `kak-tree-sitter/Makefile`) must pass the right
cross target when `DIST_TARGET=aarch64-linux`.

### ok binary — aarch64

jpm compiles Janet → C → native binary. For aarch64:
- Compile the C output with `zig cc -target aarch64-linux-musl`
- Or run `jpm build` natively on an aarch64 machine (qemu-user makes this
  possible — run the aarch64 janet binary under qemu binfmt_misc)

---

## Build pipeline (current — integrated dev mode)

```
make [DIST_TARGET=aarch64-linux]
  ├── kak/Makefile       → dist/<target>/bin/kak, share/kak/
  ├── kak-lsp/Makefile   → dist/<target>/bin/kak-lsp, share/kak-lsp/
  └── kak-tree-sitter/   → dist/<target>/bin/kak-tree-sitter, share/kak-tree-sitter/

mise run bundle
  └── reads dist/<target>/
  └── writes dist/bundle/   ← the runnable bundle
       ├── bin/kak           (wrapper script)
       ├── bin/kak-real      (actual kak binary)
       ├── bin/kak-lsp
       ├── bin/kak-tree-sitter
       ├── bin/ktsctl
       ├── bin/ok            (compiled) or symlink to repo ok (dev)
       ├── share/kak/        (scripts from kak fork)
       └── share/kak-tree-sitter/  (grammars)
```

---

## CI plan (once GitHub forks exist)

Each fork repo gets its own release workflow. overk's CI assembles and
publishes the final bundle.

### Per-component workflow (fork repos)

```yaml
on:
  push:
    tags: ['v*']
jobs:
  build:
    strategy:
      matrix:
        include:
          - target: x86_64-linux
            os: ubuntu-latest
          - target: aarch64-linux
            os: ubuntu-latest   # cross-compile, no hardware needed
    steps:
      - build for target
      - upload artifact: {name}-{version}-{target}.tar.gz
  release:
    needs: build
    steps:
      - create GitHub release with artifacts
```

### overk bundle workflow

```yaml
on:
  push:
    paths: ['components.toml']   # bump a component → rebuild bundle
jobs:
  bundle:
    steps:
      - read components.toml
      - download each component's release artifact
      - mise run bundle
      - publish overk-{version}-{target}.tar.gz
```

### mise consumption

```toml
[tools]
"gh:kgzm/kak"              = "1.2.3"
"gh:kgzm/kak-lsp"          = "0.5.0"
"gh:kgzm/kak-tree-sitter"  = "3.2.1"
```

Asset names follow the pattern `{name}-{version}-{arch}-{os}.tar.gz` to
match mise's `ubi` asset-matching heuristic.

---

## Known build quirks

### kak-tree-sitter: C++ scanner grammars excluded locally

Six grammars are excluded from the local zig-based build — their C++ scanners
cause `zig c++` to hang during the link step:

`yaml`, `html`, `sql`, `cmake`, `ruby`, `vue`

These compile fine with a standard `g++` toolchain (GitHub Actions runners
have g++ available). Include them in CI so the release artifact has the full
grammar set. Exclusion list lives in `kak-tree-sitter/Makefile` under
`LANGUAGES`.

### ok dev vs. release in bundle

`mise run bundle` checks for `bin/ok`:
- If present (compiled): copies it to `dist/bundle/bin/ok`
- If absent: symlinks `ok` (the repo-root wrapper script) into bundle

In config-only / dev mode, the symlink approach means you edit `src/*.janet`
and changes take effect immediately without recompilation.

---

## Sequencing (what's left)

1. **aarch64 builds** — `make aarch64`, test with qemu binfmt_misc
2. **GitHub forks** — create forks, wire CI in each subrepo
3. **`mise run fetch` task** — download pinned component artifacts instead
   of requiring full subrepo source checkouts (enables config-only mode
   without building from source)
4. **overk bundle CI** — assemble and publish on components.toml bump
5. **Keybindings** — `<space>b` buffers, `<space>f` files (see below)

---

## Keybindings / Convenience Features (priority 3)

### `<space>b` — buffer management

| Key | Action |
|-----|--------|
| `n` | next buffer |
| `p` | previous buffer |
| `d` | delete buffer |
| `b` | buffer picker — virtual `*buflist*` buffer with buffer-local maps |

The `*buflist*` approach (Option B) is preferred over fzf for buffer picking:
no external dep, richer interaction (buffer-local maps for delete, rename,
etc.), composes with kak's selection model. The buffer IS the UI.

### `<space>f` — file management

| Key | Action |
|-----|--------|
| `f` | fuzzy find files in workspace — **must be fzf** |

`fd` or `find` piped to `fzf`, result sent back to kak via `kak -p` as
`edit <path>`. Runs in a terminal pane or inline with `fzf --height`.

### Implementation

Pure kak script emitted from `src/init.janet`. No new `ok --api` subcommands
needed for buffer ops. The fzf file picker uses a `%sh{}` block inline.
