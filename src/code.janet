# code — SPC-c: code intelligence (LSP)
#
# Doom equivalents (SPC-c):
#   SPC-c-a  code actions
#   SPC-c-d  jump to definition
#   SPC-c-D  jump to references
#   SPC-c-f  format buffer/region
#   SPC-c-i  find implementations
#   SPC-c-k  hover documentation
#   SPC-c-r  rename symbol
#   SPC-c-t  find type definition
#   SPC-c-x  list errors (diagnostics)
#   SPC-c-s  workspace symbol search (fzf)
#
# Note: these require lsp-enable-window for the current buffer.

(defn register []
  ``
# ── code / LSP (SPC-c) ────────────────────────────────────────────────────────
declare-user-mode code

map global code a ': lsp-code-actions<ret>'        -docstring 'code actions'
map global code d ': lsp-definition<ret>'          -docstring 'definition'
map global code D ': lsp-references<ret>'          -docstring 'references'
map global code f ': lsp-formatting<ret>'          -docstring 'format'
map global code i ': lsp-implementation<ret>'      -docstring 'implementations'
map global code k ': lsp-hover<ret>'               -docstring 'hover docs'
map global code r ': lsp-rename<ret>'              -docstring 'rename symbol'
map global code t ': lsp-type-definition<ret>'     -docstring 'type definition'
map global code x ': lsp-diagnostics<ret>'         -docstring 'diagnostics'
map global code s ': lsp-workspace-symbol<ret>'    -docstring 'workspace symbol'
map global code e ': lsp-enable-window<ret>'       -docstring 'enable LSP'
map global code E ': lsp-disable-window<ret>'      -docstring 'disable LSP'

map global user c ': enter-user-mode code<ret>' -docstring 'code'
``)
