# kak-emporium — Current Status

Last updated: 2026-05-19

---

## What's working

| Component | Status |
|-----------|--------|
| `kak` | static musl x86_64 ✓ |
| `kak-lsp` | static musl x86_64 ✓, wired via autoload |
| `kak-tree-sitter` | glibc dynamic x86_64 ✓, highlighting + text objects working |
| grammars | 215 compiled `.so` files ✓ |
| `ok` binary | compiled via jpm ✓ |
| session detection | Zellij → `overk-$name` ✓ |
| splash screen | session metrics ✓ |
| clipboard | OSC 52 on y/d/c ✓ |
| user kakrc | `~/.config/kak/kakrc` sourced correctly ✓ |
| user colors | `~/.config/kak/colors/` loaded, ts_* faces themed ✓ |

---

## LSP state

lsp.kak + servers.kak are in autoload — all LSP commands available automatically.

**Per-buffer activation (manual, like M-x eglot):**
`:lsp-enable-window<ret>` in any buffer

**Auto-activation (add to `~/.config/kak/kakrc`):**
```kak
hook global WinSetOption filetype=(rust|python|go) %{
    lsp-enable-window
}
```

**IN PROGRESS** — `map global user l ':enter-user-mode lsp<ret>'` was being
added to `src/init.janet` when connection dropped. Needs rebuild + commit.

---

## RESUME: finish LSP user mode mapping

```sh
cd /var/home/kgzm/packages/kak-emporium

# Rebuild ok binary (src/init.janet has the map global user l change)
JANET=/home/kgzm/.local/share/mise/installs/github-janet-lang-janet/1.41.2/bin/janet
JANET_LIB=/home/kgzm/.local/share/mise/installs/github-janet-lang-janet/1.41.2/usr/local/lib/janet
rm -rf build/
JANET_PATH="$JANET_LIB" \
JANET_HEADERPATH=/home/kgzm/.local/share/mise/installs/github-janet-lang-janet/1.41.2/include \
CC="zig cc" CXX="zig c++" \
  "$JANET" "$JANET_LIB/jpm/cli.janet" build
cp build/ok bin/ok
mise run bundle

# Verify
bin/ok --api init | grep "user l"

# Commit
mise exec -- jj commit -m "feat(lsp): map <space>l to LSP user mode

Provides explicit per-buffer LSP activation surface. User activates
with :lsp-enable-window then uses <space>l to enter lsp user mode."
```

---

## Startup sequence (final)

```
kak wrapper sets: KAKOUNE_RUNTIME, XDG_DATA_HOME, KAK_TREE_SITTER_RUNTIME, PATH
  └── kak-real starts
        └── runtime kakrc evaluates:
              1. colorscheme default
              2. autoload/ (kak rc + lsp.kak + servers.kak)
              3. kakrc.local  ← kts init (needs $kak_session)
              4. ~/.config/kak/kakrc  ← user colors, lsp-enable-window hooks
        └── -E evaluates: ok --api init
              ← modelinefmt, <space>l LSP mapping, clipboard hook
        └── -e evaluates: ok --api splash show (if no file args)
```

---

## Build commands

```sh
# Rebuild kts (if needed — glibc target)
make kak-tree-sitter DIST_TARGET=x86_64-linux

# Rebuild ok binary
rm -rf build/
JANET_PATH=~/.local/share/mise/installs/github-janet-lang-janet/1.41.2/usr/local/lib/janet \
JANET_HEADERPATH=~/.local/share/mise/installs/github-janet-lang-janet/1.41.2/include \
CC="zig cc" \
  ~/.local/share/mise/installs/github-janet-lang-janet/1.41.2/bin/janet \
  ~/.local/share/mise/installs/github-janet-lang-janet/1.41.2/usr/local/lib/janet/jpm/cli.janet build
cp build/ok bin/ok

# Assemble bundle
mise run bundle
```

---

## Pending work

- [ ] Finish LSP user mode mapping commit (was in-progress when connection dropped)
- [ ] GitHub forks (`gh auth login` → fork kak, kak-lsp, kak-tree-sitter)
- [ ] Fix CI workflows — kts must target glibc, not musl
- [ ] aarch64 kts build
- [ ] ok keybindings (beyond LSP user mode)
- [ ] Integration test suite
