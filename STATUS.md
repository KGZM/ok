# kak-emporium — Current Status

Last updated: 2026-05-18

---

## IMMEDIATE NEXT ACTION

**Rebuild kak-tree-sitter as a glibc dynamic binary:**

```sh
# From repo root — top-level make handles staging to dist/x86_64-linux/
make kak-tree-sitter DIST_TARGET=x86_64-linux
mise run bundle
kill $(cat /tmp/kak-runtime/kak-tree-sitter/pid 2>/dev/null); ok
```

Note: `cd kak-tree-sitter && make package` only stages to `kak-tree-sitter/dist/`,
NOT to the repo-level `dist/`. Always use the top-level `make` target.

Then verify: `cat /tmp/kak-runtime/kak-tree-sitter/stderr.txt` — should show grammars loading, no DlOpen errors.

---

## Root cause of current kts failure

The kts binary in `dist/` is from **2026-05-17** and is `x86_64-unknown-linux-musl` (static).
musl static builds stub out `dlopen` → grammars cannot load.

```
[ERROR]: cannot load grammar: DlOpen { desc: "Dynamic loading not supported" }
```

`kak-tree-sitter/target/` contains only musl builds:
- `x86_64-unknown-linux-musl/release/kak-tree-sitter` (May 17)
- `aarch64-unknown-linux-musl/release/kak-tree-sitter` (May 17)

No `x86_64-unknown-linux-gnu` build exists. The kts Makefile was updated to target
glibc (`CARGO_TARGET_x86_64-linux = x86_64-unknown-linux-gnu`) but was never rerun.

---

## Critical constraints

### kak-tree-sitter MUST be glibc (dynamic), not musl (static)
- Grammars are `.so` files loaded via `dlopen` at runtime
- musl static stubs out `dlopen`
- Target: `x86_64-unknown-linux-gnu`
- Feature flag: `--features kak-tree-sitter/direct-unix-socket` (already in Makefile)

### kts init MUST happen from kakrc.local
- `$kak_session` is NOT available in `%sh{}` during `-E` server init
- `$kak_session` IS available in `%sh{}` sourced from the runtime kakrc
- Bundle task writes `kakrc.local` to `$BUNDLE/share/kak/kakrc.local`
- Content: kills stale daemon, then `kak-tree-sitter -dks --init "$kak_session" ...`

---

## Component status

| Component | Binary | Status |
|-----------|--------|--------|
| `kak` | static musl x86_64 | ✓ working |
| `kak-lsp` | static musl x86_64 | ✓ working |
| `kak-tree-sitter` | **static musl x86_64 (WRONG)** | ✗ dlopen fails |
| grammars | 215 `.so` files staged | ✓ (need glibc kts to load them) |
| `ok` (Janet) | runs from source | ✓ working |

---

## ok program — what it does

`ok` wraps `kak` with:
- Session detection via `$ZELLIJ_SESSION_NAME` → `overk-$name` kak session name
- Splash screen on startup (no file arg) with session metrics
- OSC 52 clipboard on y/d/c (reads via stdin, writes to `/dev/tty`)
- Server init via `-E "evaluate-commands %sh{ ok --api init }"`:
  - Emits: `colorscheme default`, `modelinefmt`, clipboard NormalKey hook
  - kts init is NOT here — it's in `kakrc.local` (see above)

```
src/main.janet      — entrypoint, launcher, --api dispatch
src/init.janet      — server-init kak script emission
src/splash.janet    — splash screen + session metrics
src/clipboard.janet — OSC52 clipboard
src/session.janet   — Zellij session detection
```

---

## Bundle layout

```
dist/bundle/
├── bin/
│   ├── kak              ← wrapper: sets env vars, execs kak-real
│   ├── kak-real         ← actual kak binary
│   ├── kak-lsp
│   ├── kak-tree-sitter  ← MUST BE GLIBC DYNAMIC (currently musl static — broken)
│   ├── ktsctl
│   └── ok               ← symlink to repo/ok (dev)
└── share/
    ├── kak/
    │   ├── kakrc        ← vanilla kak runtime
    │   ├── kakrc.local  ← kts init (written by `mise run bundle`)
    │   ├── autoload/    ← kak rc + kak-lsp rc
    │   └── doc/
    └── kak-tree-sitter/
        ├── grammars/    ← 215 .so files
        └── queries/
```

kak wrapper env vars (set for all child processes including kts):
- `KAKOUNE_RUNTIME=$BUNDLE/share/kak`
- `KAK_TREE_SITTER_RUNTIME=$BUNDLE/share/kak-tree-sitter`
- `XDG_DATA_HOME=$BUNDLE/share`
- `XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-/tmp/kak-runtime}`

---

## Pending work

- [ ] **Rebuild kts as glibc dynamic binary** ← do this first
- [ ] Verify kts highlighting + text objects work after rebuild
- [ ] aarch64 kts build (glibc cross-compile via zigbuild)
- [ ] GitHub forks (`gh auth login` → fork kak, kak-lsp, kak-tree-sitter)
- [ ] Fix CI workflows — kts workflow must target glibc, not musl
- [ ] ok: more features (LSP wiring, keybindings)
- [ ] ok: integration test suite

---

## How to verify kts after rebuild

```sh
# 1. Check socket exists
ls /tmp/kak-runtime/kak-tree-sitter/

# 2. Check for errors
cat /tmp/kak-runtime/kak-tree-sitter/stderr.txt

# 3. In kak, check FIFO path (should NOT be /dev/null)
# :set-register dquote %opt{tree_sitter_buf_fifo_path}<ret>"p

# 4. Test text objects in a rust file
# <a-i>f  — select inside function
```
