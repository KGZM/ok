# kak-emporium — Current Status

Last updated: 2026-05-17 (end of day 2)

---

## What works right now

The bundle at `dist/bundle/` runs kak with tree-sitter highlighting and text objects working.
Syntax highlighting and `<a-i>f` / `<a-a>f` / `]f` / `[f` (function, type, argument, test)
all function. `tree-sitter` user mode (structural AST navigation) is wired but not yet
bound to a key — that's anima's job.

```sh
# Run it:
dist/bundle/bin/kak somefile.rs
```

---

## Directory layout

```
kak-emporium/
├── mise.toml                  # zig 0.16.0, rust stable, cargo-zigbuild
├── Makefile                   # top-level: make / make run
├── kakrc                      # repo kakrc (sourced by kak via -E)
├── mise/tasks/bundle          # mise run bundle — assemble dist/bundle/
├── mise/tasks/smoke           # mise run smoke — headless startup test
├── kak/                       # kakoune (upstream clone, CI workflow ready)
├── kak-lsp/                   # kak-lsp (upstream clone, CI workflow ready)
├── kak-tree-sitter/           # kak-tree-sitter (sr.ht/~hadronized)
├── dist/bundle/               # self-contained runnable bundle (symlink kak from here)
└── dist/local/                # intermediate build outputs
```

---

## Component status

### kak — DONE locally, pending GitHub fork

- Static musl binaries: x86_64 (2.3MB), aarch64 (2.2MB)
- `make package DIST_TARGET={x86_64,aarch64}-linux` works
- CI workflow: `kak/.github/workflows/release.yml` ready
- **Pending:** `gh auth login` → fork mawww/kakoune → push workflow

### kak-lsp — DONE locally, pending GitHub fork

- Static musl binaries: x86_64 (7.4MB), aarch64 (6.4MB)
- `make package DIST_TARGET={x86_64,aarch64}-linux` works
- CI workflow: `kak-lsp/.github/workflows/release.yml` ready
- **Pending:** fork kakoune-lsp/kakoune-lsp → push workflow

### kak-tree-sitter — WORKING locally (x86_64 only)

**215 grammars compiled and bundled. Highlighting and text objects confirmed working.**

#### Critical constraints discovered this session

**1. Must be a glibc binary — NOT static musl.**
kak-tree-sitter loads grammars via `dlopen` at runtime. Static musl stubs out
`dlopen` and always returns "Dynamic loading not supported". kak and kak-lsp
stay static musl (they don't use dlopen); kak-tree-sitter cannot.

Current build: `cargo build --release --features kak-tree-sitter/direct-unix-socket`
(native glibc, host architecture only — cross-compilation for aarch64 not yet done).

For aarch64 cross-compile: use `cargo zigbuild --target aarch64-unknown-linux-gnu`
(glibc, not musl). The CI workflow needs updating for this.

**2. Must use `--features direct-unix-socket`.**
Without it, the daemon spawns `kak -p session` to send responses back to kak.
From a daemonized process, this fails with "Permission denied" because the
daemon's PATH doesn't include the bundle's bin directory. With `direct-unix-socket`,
the daemon connects directly to kak's session socket — no subprocess, no PATH issue.

**3. Grammar .so files compiled as musl work fine with glibc binary.**
Symbol ABI is compatible for simple C parsers. No need to recompile grammars.
Existing musl-compiled .so files in `dist/bundle/share/kak-tree-sitter/grammars/` are correct.

#### Bundle wiring fixes (applied this session)

- `autoload/rc → rc` was a circular symlink (mkdir created the dir first, then ln -sf
  put a relative symlink inside it pointing to itself). Fixed: `autoload/rc → ../rc`.
  Without this, no filetype detection scripts loaded — `filetype` was always empty.
- `2>/dev/null` in kakrc.local replaced with `2>>/tmp/kts-init.log` for visibility.

#### Grammar state

- 215 grammars compiled for x86_64 in `dist/bundle/share/kak-tree-sitter/grammars/`
- aarch64 grammars: 58 compiled in `dist/aarch64-linux/`, full set not done
- `rust-format-args` sub-grammar added to bundle (was missing, causing a non-fatal error)
- Grammar source cache: `kak-tree-sitter/.grammar-build/` — **DO NOT WIPE**
- Grammar config: `kak-tree-sitter/config/grammars.toml` (2548 lines, helix-sourced)

#### Known grammar issues (not blocking, fix when doing CI)

| Grammar | Problem | Fix |
|---------|---------|-----|
| `markdown_inline`, `php-only`, `tsx`, `v`, `wast`, `wat` | need `path =` in grammars.toml | add path override |
| `ocaml` | zig cache race under parallel builds | retry solo |
| `qmljs` | bad compile args | add override |
| `julia` | `-flto=auto` flag | strip in override |

#### CI workflow status

`kak-tree-sitter/.github/workflows/release.yml` was written before the dlopen constraint
was discovered. It compiles with musl and will NOT produce working binaries.
**Must be updated** to:
- Use glibc target for the binary (`x86_64-unknown-linux-gnu`, `aarch64-unknown-linux-gnu`)
- Keep musl for grammar compilation (or switch to gnu — both work)
- Keep `--features kak-tree-sitter/direct-unix-socket`

---

### anima — NOT STARTED

The Janet program. Entry point: `anima init` → prints kak script to stdout.
`try %{ evaluate-commands %sh{ anima init } }` is already in kakrc.local.
Anima will own: key bindings (including entering `tree-sitter` user mode),
hooks, editor settings. The temporary kak-tree-sitter daemon wiring in kakrc.local
should move into anima eventually.

---

## The packaging problem (main task for next session)

The real distribution work hasn't started. Here's what needs to happen:

### Binaries

| Component | Build | Size | Status |
|-----------|-------|------|--------|
| kak x86_64 | static musl | 2.3MB | local only |
| kak aarch64 | static musl | 2.2MB | local only |
| kak-lsp x86_64 | static musl | 7.4MB | local only |
| kak-lsp aarch64 | static musl | 6.4MB | local only |
| kak-tree-sitter x86_64 | **glibc** | ~4MB | local only |
| kak-tree-sitter aarch64 | **glibc** cross | not built | — |

### Grammars

215 `.so` files for x86_64. Currently loose in `dist/bundle/share/kak-tree-sitter/grammars/`.
Shipping strategy TBD: raw .so files (large), `grammars.tar.zst` + extract script, or something else.
40-50MB uncompressed; ~5-8MB compressed for a full set.

### Distribution via mise

The plan was mise's GitHub backend (`gh:`) pointing at release artifacts on GitHub.
Works for kak and kak-lsp (static binaries, self-contained). For kak-tree-sitter
plus 215 grammars this is more complex — likely needs a different artifact structure
or a mise task that fetches and extracts separately.

### GitHub setup (not done)

```sh
gh auth login
gh repo fork mawww/kakoune --clone=false        # then push kak/.github/workflows/
gh repo fork kakoune-lsp/kakoune-lsp --clone=false
gh repo create kak-tree-sitter --public         # push from sr.ht clone
```

---

## How to resume

```sh
cd ~/packages/kak-emporium
mise install                   # zig 0.16.0, rust stable, cargo-zigbuild

# Run the working bundle:
dist/bundle/bin/kak somefile.rs

# Rebuild bundle from scratch (if needed):
mise run bundle

# The kak-tree-sitter binary in the bundle is glibc (not musl).
# The Makefile in kak-tree-sitter/ now builds glibc for both arches.
# Grammar .so files are musl-compiled but work fine.

# GitHub auth (whenever ready):
gh auth login

# Start anima:
mkdir anima && cd anima && janet-based program here
```
