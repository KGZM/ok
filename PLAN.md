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

### Mode 1 — Source / development (= CI)

Build everything from source. This is the same workflow CI uses — no
distinction between local dev and the CI build pipeline.

- All subrepos checked out (`kak/`, `kak-lsp/`, `kak-tree-sitter/`)
- `make [DIST_TARGET=aarch64-linux]` builds all components from source
- `mise run bundle` assembles the runnable bundle
- Changes to kak scripts → commit to `kak/` fork; pulled in at bundle time
- Changes to ok config runtime → commit here; no recompile needed (Janet is interpreted)
- `bin/ok` absent in dev → bundle symlinks repo-root `ok` wrapper → runs `janet src/main.janet` directly

### Mode 2 — Release (end-user)

```sh
mise use -g github:kgzm/ok
```

One command. Installs the pre-built bundle tarball published by this repo's
CI. Contains all binaries (kak, kak-lsp, kak-tree-sitter, ok), all kak
scripts, and all grammars. No source checkout, no compiler, no janet runtime
needed — `ok` in the release tarball is a compiled native binary.

Iterating on janet config in release mode: clone the repo, edit `src/*.janet`,
point your shell at the cloned `ok` wrapper instead of the mise-installed one.
The wrapper runs `janet src/main.janet` if no compiled `bin/ok` is present.

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

A single workflow in this repo builds everything from source and publishes
the bundle. Same as running `make && mise run bundle` locally.

```yaml
# .github/workflows/release.yml
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
            os: ubuntu-latest   # zig cross-compiles; no hardware needed
    steps:
      - checkout (with subrepos)
      - install zig, rust, cargo-zigbuild, janet
      - make DIST_TARGET=${{ matrix.target }}
      - build ok binary (jpm or zig cc for cross)
      - mise run bundle DIST_TARGET=${{ matrix.target }}
      - upload ok-{version}-{target}.tar.gz
  release:
    needs: build
    steps:
      - create GitHub release with both target artifacts
```

### End-user install

```sh
mise use -g github:kgzm/ok
```

Asset names: `ok-{version}-x86_64-linux.tar.gz`, `ok-{version}-aarch64-linux.tar.gz`.
mise's `ubi` heuristic matches on `x86_64`/`aarch64` + `linux` tokens.

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
2. **GitHub forks** — create kgzm/ok (this repo) + subrepo forks for upstream tracking
3. **CI workflow** — single workflow here builds from source and publishes `ok` release
4. **Keybindings / Space Leader System** — Doom-style Space Leader keybindings (SPC b/f/s/j/c/p) with fzf + easymotion ✓ (Completed)
5. **FZF Callback Refactoring / API Callbacks** — Transitioned interactive launchers to unified CLI callback subcommands ✓ (Completed)
6. **Multiplexer Environment Forwarding & Mock-Based Integration Testing** — Solved PTY/daemon PATH forwarding issues and implemented end-to-end mock-based integration verification ✓ (Completed)
7. **Janet DSL expansions (:val, :opt, :reg, :dq)** — Expanded DSL to support native Kakoune expansion and quoting syntax cleanly ✓ (Completed)

---

## Keybindings / Convenience Features (Completed)

The Space Leader System has been implemented in Janet under `src/` and fully refactored. It aligns with the **Doom Emacs** blueprint, structuring key mappings into distinct user-modes.

### 1. Implemented Modules and Mapping Structure

*   **`<space>b` (Buffers)**:
    *   `b`: Switch buffer (fuzzy completion menu)
    *   `[` / `p`: Previous buffer
    *   `]` / `n`: Next buffer
    *   `d` / `k`: Kill buffer
    *   `K`: Kill all buffers
    *   `O`: Kill other buffers
    *   `l`: Last (alternate) buffer
    *   `N`: New scratch buffer
    *   `r`: Revert buffer
    *   `s` / `S`: Save buffer / Save all buffers
    *   `x`: Scratch buffer
    *   `i`: List buffers (virtual `*buflist*` buffer with local keymaps: `<ret>` to switch, `d` to delete)
*   **`<space>f` (Files)**:
    *   `f`: Find file in current directory via `fd`/`find` + `fzf`
    *   `r`: Recent files (fzf over git-tracked files by mtime or fallback `find` by mtime)
    *   `s`: Save file
    *   `R`: Rename/move current file and update buffer cleanly
    *   `D`: Delete current file on disk and close buffer
    *   `y`: Yank absolute path of current file to `dquote` register
    *   `Y`: Yank relative path (from project root) of current file to `dquote` register
    *   `e`: File explorer (`yazi`, `ranger`, or `lf` launcher in Zellij float, Tmux popup, or Kak terminal fallback)
    *   `t`: Terminal here (launches shell in current buffer directory)
*   **`<space>s` (Search)**:
    *   `s`: Search current buffer lines via `fzf`
    *   `S` / `w` / `<space>*`: Search project for word under cursor via `rg` + `fzf`
    *   `p` / `<space>/`: Search project via `rg` + `fzf`
    *   `d`: Search current directory via `rg` + `fzf`
    *   `n` / `N`: Search forward/backward (Kakoune native)
*   **`<space>j` (Jump / Easymotion)**:
    *   `c`: Jump to char (viewport-scoped easymotion with replacements `[1-9]`)
    *   `w`: Jump to word (viewport-scoped easymotion with replacements `[1-9]`)
    *   `l`: Jump to line (fzf swiper-style picker)
*   **`<space>c` (Code / LSP)**:
    *   `a`: Code actions
    *   `d`: Jump to definition
    *   `D`: Jump to references
    *   `f`: Format buffer/region
    *   `i`: Find implementations
    *   `k`: Hover documentation
    *   `r`: Rename symbol
    *   `t`: Find type definition
    *   `x`: List errors/diagnostics
    *   `s`: Workspace symbol search
    *   `e` / `E`: Enable/disable LSP for the current window
*   **`<space>p` (Project)**:
    *   `f`: Find file in project root
    *   `p`: Switch project (fuzzy pick git repo from directories defined in `ok_project_paths` or defaults)
    *   `r`: Show project root path in status line
    *   `k`: Kill all buffers belonging to current project
    *   `s`: Save all modified buffers belonging to current project
    *   `!`: Open terminal/shell at project root

### 2. Architectural Design & Tool Detection

*   **Decoupled & Modular Core**: Each concern lives in its own Janet module (`src/buffers.janet`, `src/files.janet`, etc.). Mappings are registered cleanly on initialization.
*   **Janet-to-Kakscript DSL (`src/kak.janet`)**: Encapsulates Kakscript syntax generation. Rather than using raw string interpolation, it exposes strongly-typed functions like `kak/map`, `kak/defcmd`, `kak/declare-user-mode`, and `kak/defcmd-api` to keep command formatting consistent and secure.
*   **Environment & Tool Detection API (`src/env.janet`)**: Centrally detects installed command-line utilities (`fd` vs `find`, `rg` vs `grep`, `bat` vs `cat`) and shell multiplexer state (`ZELLIJ_SESSION_NAME` vs `TMUX` vs graphical `DISPLAY`). It automatically adjusts launcher commands to run floating panes, popups, or external terminals accordingly.
*   **E2E FZF Callback Architecture**: Refactored interactive launchers to delegate control to CLI callback subcommands (`ok --api <module> pick-<action> <session> <client> [args...]`). Previously, the system generated complex inline shell commands or temporary files to run `fzf` and capture selections. Now, launchers run a unified callback interface inside the spawned terminal/pane, allowing the Janet program to directly execute and communicate selections back to Kakoune via the session socket (`kak -p <session>`), eliminating escaping bugs.
*   **Consistent Session Resolution (`src/session.janet`)**: Switched from direct `XDG_RUNTIME_DIR/kakoune/<session>` file-stat checks to invoking `kak -l` to fetch active sessions. This ensures consistency when the wrapper and caller resolve the Kak runtime/tmp socket directories.
*   **Multiplexer Environment Forwarding**: Formulated and implemented environment variable serialization to forward path and runtime session variables (e.g. `PATH`, `XDG_RUNTIME_DIR`, `XDG_DATA_HOME`) into multiplexer client pane runs via the `env` binary, bypassing client-server daemon environment loss.
*   **DSL Braced Expansions & Quoting**: Expanded the compiler to natively compile `[:val :key]`, `[:opt :name]`, and `[:reg :a]` expansions unquoted so Kakoune's Kakscript engine parses them dynamically. Introduced the `[:dq ...]` double-quoting form to allow clean variable expansions inside subshell calls while preventing argument split errors.

### 3. Key Bug Fixes Resolved in Refactoring

*   **Space Splitting Bug**: Fixed a bug where buffer paths or directories containing spaces were split incorrectly into multiple arguments when looping or passing lists. Replaced naive `$kak_opt_buflist` iteration in shell commands with robust Kakoune quoted-list parsing (`eval "set -- $kak_quoted_buflist"`) to ensure space-preserved argument lists.
*   **Duplicate Prefixes**: Consolidated user-mode mapping registration and eliminated overlapping prefix bindings between `:jump` and `:code`. Clear namespace separations now map LSP capabilities exclusively under `<space>c` and navigation under `<space>j`.
*   **Rename Deletion Bug**: Resolved an issue where renaming a file opened the new buffer but closed the newly opened buffer instead of the old, renamed buffer. The file rename operations (`ok --api files rename`) now explicitly receive the old buffer path and use `delete-buffer <old_path>` after opening the new path.
*   **Regex Escaping in Easymotion**: Addressed a regex parser crash in easymotion (`ok-jump-collect`) when searching for regex-active characters (like `[`, `*`, or `.`). Added a robust `sed` sanitization pipeline that escapes regex metacharacters before executing Kakoune's `s` (select) command.
*   **Zellij Redirection Leak**: Fixed a bug where spawning a Zellij floating pane printed diagnostic shell output to stdout/stderr, which leaked into Kakoune and triggered `no such command: terminal_XX` errors. Resolved by redirecting the Zellij command output using `>/dev/null 2>&1`.
*   **DSL Try-Block Quoting Bug**: Resolved a `try: wrong argument count` Kakoune error caused when unbracketed nested commands inside a `:try` form compiled to space-separated strings. The `:try` compiler in `src/kak.janet` now automatically wraps nested child commands in a bracketed `%{\n...\n}` block, ensuring correct argument grouping.
*   **%val{timestamp} is not a number**: Resolved a startup crash in `ok-jump-clear` where `%val{timestamp}` was compiled within single quotes (`'%val{timestamp}'`), preventing dynamic evaluation and violating option type constraints. Solved by introducing native unquoted `:val` primitives.
*   **Keypress Capture Quoting**: Fixed a bug where the key parameter passed to `ok-jump-collect` was compiled inside single quotes `'%val{key}'`, causing the literal string `"%val{key}"` to be processed instead of the actual key code. Resolved by compiling it unquoted.
*   **Positional Parameter Expansion ($1)**: Fixed a bug where `$1` argument inside `ok-jump-collect` compiled to single-quoted `'$1'`, preventing the subshell from expanding it. Resolved by using `[:sh-var "1"]` to output double-quoted `"$1"` for correct parameter expansion.
