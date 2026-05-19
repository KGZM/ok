# kak-emporium — Current Status

Last updated: 2026-05-19

---

## What's working

| Component | Status |
|-----------|--------|
| `kak` | static musl x86_64 ✓ |
| `kak-lsp` | static musl x86_64 ✓, wired via autoload |
| `kak-tree-sitter` | glibc dynamic x86_64 ✓, highlighting + text objects ✓ |
| grammars | 215 compiled `.so` files ✓ |
| `ok` binary | compiled via jpm ✓ |
| session detection | Zellij → `overk-$ZELLIJ_SESSION_NAME` ✓ |
| splash screen | shows on first client only (`hook -once global ClientCreate`) ✓ |
| clipboard | OSC 52 on y/d/c ✓ |
| LSP user mode | `<space>l` → enter LSP user mode ✓ |
| `:new` in zellij | opens new pane ✓ |
| user kakrc | `~/.config/kak/kakrc` sourced correctly ✓ |

---

## LSP state

lsp.kak + servers.kak in autoload — all LSP commands available automatically.

**Per-buffer activation:**
`:lsp-enable-window<ret>`

**Navigate LSP commands:**
`<space>l` → enter LSP user mode

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
  └── kak wrapper: sets KAKOUNE_RUNTIME, XDG_DATA_HOME, KAK_TREE_SITTER_RUNTIME, PATH
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
# Rebuild ok binary
JANET_BASE=~/.local/share/mise/installs/github-janet-lang-janet/1.41.2
rm -rf build/
JANET_PATH="$JANET_BASE/usr/local/lib/janet" \
JANET_HEADERPATH="$JANET_BASE/include" \
  "$JANET_BASE/bin/janet" "$JANET_BASE/usr/local/lib/janet/jpm/cli.janet" build
cp build/ok bin/ok

# Assemble bundle
mise run bundle

# Rebuild kts (glibc target — do NOT use musl, dlopen required for grammars)
make kak-tree-sitter DIST_TARGET=x86_64-linux
```

---

## Pending work (priority order)

1. [ ] **aarch64 kts** — glibc dynamic build for arm (same dlopen constraint applies)
2. [ ] **Deployment** — GitHub forks, CI workflows (kts must target glibc not musl), mise distribution
3. [ ] **Keybindings / convenience features** — see PLAN.md; `<space>b` buffers, `<space>f` files
4. [ ] Integration test suite
