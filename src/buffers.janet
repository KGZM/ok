# buffers — SPC-b: buffer management
#
# Pure kak — no fzf, no ok --api dispatch.
# Doom equivalents:
#   SPC-b-b  switch buffer (prompt with completion)
#   SPC-b-d  delete buffer
#   SPC-b-n  next buffer
#   SPC-b-p  previous buffer
#   SPC-b-s  save buffer
#   SPC-b-l  list all open buffers in scratch buffer

(defn register []
  ``
# ── buffers (SPC-b) ───────────────────────────────────────────────────────────
declare-user-mode buffers

define-command ok-buffers-switch \
  -docstring 'switch to buffer by name (fuzzy completion)' %{
  prompt -menu buffer: -buffer-completion %{ buffer %val{text} }
}

define-command ok-buffers-list \
  -docstring 'list open buffers in a scratch buffer' %{
  edit -scratch *buflist*
  set-option buffer filetype scratch
  evaluate-commands %sh{
    printf 'set-register dquote %%{%s}\n' \
      "$(printf '%s\n' $kak_opt_buflist | grep -v '^\*')"
  }
  execute-keys '%<a-d>P'
  execute-keys 'gg'
  map buffer normal <ret> %{
    evaluate-commands %sh{
      printf 'buffer %%{%s}\n' "$kak_selection"
    }
  }
  map buffer normal d %{
    evaluate-commands %sh{
      buf=$kak_selection
      printf 'delete-buffer %%{%s}\n' "$buf"
      printf 'delete-buffer *buflist*\n'
      printf 'ok-buffers-list\n'
    }
  }
}

map global buffers b ': ok-buffers-switch<ret>'    -docstring 'switch buffer'
map global buffers d ': delete-buffer<ret>'        -docstring 'delete buffer'
map global buffers n ': buffer-next<ret>'          -docstring 'next buffer'
map global buffers p ': buffer-previous<ret>'      -docstring 'prev buffer'
map global buffers s ': write<ret>'               -docstring 'save buffer'
map global buffers l ': ok-buffers-list<ret>'      -docstring 'list buffers'

map global user b ': enter-user-mode buffers<ret>' -docstring 'buffers'
``)
