# ok — Current Status

Last updated: 2026-05-25

---

## What's working

| Component | Status |
|-----------|--------|
| `kak` | static musl x86_64 + aarch64 ✓ |
| `kak-lsp` | static musl x86_64 + aarch64 ✓, wired via autoload |
| `kak-tree-sitter` | glibc dynamic x86_64 + aarch64 ✓, highlighting + text objects ✓ |
| grammars | 215 flat `.so` files (kgzm/grammars), Source::Bundled ✓ |
| `ok` binary | compiled + stripped via jpm + zig cc ✓ |
| CI release pipeline | x86_64 + aarch64 bundles publishing to GitHub Releases ✓ |
| `mise use -g github:kgzm/ok` | end-user install working ✓ |
| session detection | Zellij → `overk-$ZELLIJ_SESSION_NAME` ✓ |
| splash screen | shows on first client only (`hook -once global ClientCreate`) ✓ |
| clipboard | OSC 52 on y/d/c ✓ |
| LSP user mode | `<space>l` → enter LSP user mode ✓ |
| `:new` in zellij | opens new pane ✓ |
| space leader | Doom-style keybindings (SPC b/f/s/j/c/p) with fzf + easymotion ✓ |
| zellij redirection | floating pane execution stdout/stderr suppressed ✓ |
| DSL try-block quoting | try-block expressions automatically wrapped in block ✓ |
| FZF callback refactoring | interactive pick- callbacks in multiplexer panes ✓ |
| multiplexer env forwarding | path and runtime environment variables forwarded to panes ✓ |
| DSL native expansions | support for val/opt/reg/dq primitives in DSL to prevent quoting errors ✓ |
| integration test suite | mock-based E2E path-level integration test suite ✓ |
| user kakrc | `~/.config/kak/kakrc` sourced correctly ✓ |
| XDG_RUNTIME_DIR | fallback via mktemp if unset (containers etc.) ✓ |
| DEPENDENCIES.txt | shipped with every release ✓ |
| jump error suppression | suppress nothing selected error in ok-jump-word/char when no matches exist ✓ |
| jump on-key block wrapping | wrap on-key commands in block to prevent argument count errors ✓ |

---

## Architecture notes

**Grammars are decoupled from kak-tree-sitter.**
kts uses `Source::Bundled` — looks for flat `.so` files at
`$XDG_DATA_HOME/kak-tree-sitter/grammars/{lang}.so`. Since the kak
wrapper sets `XDG_DATA_HOME=$BUNDLE/share`, grammars from `kgzm/grammars`
land exactly there. kts no longer compiles or ships grammars.

**Three operating modes:**
- Mode 1 (source/dev): subrepos checked out, `make` + `mise run bundle`
- Mode 2 (release): `mise use -g github:kgzm/ok` — pre-built bundle
- Mode 3 (openface): ok repo checked out, `DIST_TARGET=... mise run fetch` + `mise run bundle`

---

## LSP state

lsp.kak + servers.kak in autoload — all LSP commands available automatically.

**Per-buffer activation:** `:lsp-enable-window<ret>`

**Navigate LSP commands:** `<space>l` → enter LSP user mode

**Auto-activation (add to `~/.config/kak/kakrc`):**
```kak
hook global WinSetOption filetype=(rust|python|go) %{
    lsp-enable-window
}
```

---

## Startup sequence

```
ok [file]
  └── session.janet: detect ZELLIJ_SESSION_NAME → overk-<name>
  └── kak wrapper: sets KAKOUNE_RUNTIME, XDG_DATA_HOME, KAK_TREE_SITTER_RUNTIME,
  │               XDG_RUNTIME_DIR (fallback if unset), PATH
        └── kak-real starts server
              1. colorscheme default
              2. autoload/ (kak rc + lsp.kak + servers.kak)
              3. kakrc.local  ← kts init ($kak_session available here)
              4. ~/.config/kak/kakrc  ← user colors, lsp hooks
              5. -E: ok --api init [--splash]
                   ← modelinefmt, <space>l LSP mapping, clipboard
                   ← if --splash: hook -once global ClientCreate → splash on first client only
```

---

## Build commands

```sh
# Install jpm (one-time — not bundled with janet release)
git clone --depth=1 https://github.com/janet-lang/jpm /tmp/jpm-src
JANET_BASE=$(mise where github:janet-lang/janet)
cp -r /tmp/jpm-src/jpm "$JANET_BASE/lib/janet/"
cp /tmp/jpm-src/configs/linux_config.janet "$JANET_BASE/lib/janet/jpm/default-config.janet"

# Rebuild ok binary (jpm generates ok.c; link step fails expectedly; we relink)
mise run build-ok

# Assemble bundle (Mode 1 — from local subrepo builds)
mise run bundle

# Assemble bundle (Mode 3 — from GitHub release artifacts)
DIST_TARGET=x86_64-linux mise run fetch
mise run bundle

# Release: cut and push tags
scripts/cut-release.sh   # in ok repo (jj)
# in subrepos (git):
scripts/cut-release.sh
```

---

## Release pipeline

Each subrepo has its own CI + `scripts/cut-release.sh`. After cutting subrepo
releases, update `components.toml` release fields, then cut an ok release.

**Release order:**
1. Cut kak, kak-lsp, kak-tree-sitter, grammars releases
2. Wait for CI
3. Update `components.toml` with new tags
4. Cut ok release — CI fetches all components, builds ok binary, assembles bundle

Each release ships `DEPENDENCIES.txt` with full cargo tree for Rust components.

---

## Security audit

Grammar scanner.c files audited 2026-05-21:
- No socket/network calls
- No exec/popen/system calls (hits were in comments/identifiers only)
- No fork/process calls
- No file write calls (hits were parser function names like `scan_string_open`)
- No dlopen/dlsym calls

Rust deps audited indirectly via cargo tree in DEPENDENCIES.txt per release.

---

## Pending work

### 🙋 Me
- [ ] Repo curation before public — see `tmp/GITHUB_SETUP.md` checklist
- [ ] Push master on subrepos + ok to GitHub after session

### 🤖 Claude
- [ ] **Systemd filetype fix** — match `.service`/`.timer` by extension not path
- [x] **Keybindings** — `<space>b` buffer menu, `<space>f` fzf file picker (see PLAN.md)
- [ ] **`scripts/update-grammar.sh`** — pull one grammar from upstream with diff review
- [ ] **`scripts/verify-parser.sh`** — regen parser.c from grammar.js and diff for audit
- [x] Integration test suite
- [ ] macOS support (deeply backburnered)
