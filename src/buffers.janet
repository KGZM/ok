# buffers — SPC-b: buffer management
#
# Doom equivalents (SPC-b):
#   SPC-b-b / ,   switch buffer
#   SPC-b-[/]     previous/next buffer (also SPC-b-p/n)
#   SPC-b-d       kill buffer
#   SPC-b-k       kill buffer (alias)
#   SPC-b-K       kill all buffers
#   SPC-b-l       switch to last buffer
#   SPC-b-n       next buffer
#   SPC-b-N       new empty scratch buffer
#   SPC-b-O       kill other buffers
#   SPC-b-p       previous buffer
#   SPC-b-r       revert buffer
#   SPC-b-s       save buffer
#   SPC-b-S       save all buffers
#   SPC-b-x       scratch buffer (toggle)

(defn register []
  ``
# ── buffers (SPC-b) ───────────────────────────────────────────────────────────
declare-user-mode buffers

define-command ok-buffers-switch \
  -docstring 'switch to buffer by name (fuzzy completion)' %{
  prompt -menu buffer: -buffer-completion %{ buffer %val{text} }
}

define-command ok-buffers-last \
  -docstring 'switch to last (alternate) buffer' %{
  evaluate-commands %sh{
    # kak_opt_buflist: first entry after current is the alternate
    current=$kak_bufname
    last=""
    for buf in $kak_opt_buflist; do
      [ "$buf" != "$current" ] && [ -z "$last" ] && last=$buf
    done
    [ -n "$last" ] && printf 'buffer %%{%s}\n' "$last"
  }
}

define-command ok-buffers-new \
  -docstring 'open a new empty scratch buffer' %{
  evaluate-commands %sh{
    printf 'edit -scratch *scratch-%s*\n' "$(date +%s)"
  }
}

define-command ok-buffers-kill-others \
  -docstring 'kill all buffers except the current one' %{
  evaluate-commands %sh{
    current=$kak_bufname
    for buf in $kak_opt_buflist; do
      [ "$buf" != "$current" ] && printf 'try %%{ delete-buffer %%{%s} }\n' "$buf"
    done
  }
}

define-command ok-buffers-kill-all \
  -docstring 'kill all buffers' %{
  evaluate-commands %sh{
    for buf in $kak_opt_buflist; do
      printf 'try %%{ delete-buffer %%{%s} }\n' "$buf"
    done
  }
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
    evaluate-commands %sh{ printf 'buffer %%{%s}\n' "$kak_selection" }
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

map global buffers b ': ok-buffers-switch<ret>'      -docstring 'switch buffer'
map global buffers <[> ': buffer-previous<ret>'      -docstring 'previous buffer'
map global buffers <]> ': buffer-next<ret>'          -docstring 'next buffer'
map global buffers d ': delete-buffer<ret>'          -docstring 'kill buffer'
map global buffers k ': delete-buffer<ret>'          -docstring 'kill buffer'
map global buffers K ': ok-buffers-kill-all<ret>'    -docstring 'kill all buffers'
map global buffers l ': ok-buffers-last<ret>'        -docstring 'last buffer'
map global buffers n ': buffer-next<ret>'            -docstring 'next buffer'
map global buffers N ': ok-buffers-new<ret>'         -docstring 'new scratch buffer'
map global buffers O ': ok-buffers-kill-others<ret>' -docstring 'kill other buffers'
map global buffers p ': buffer-previous<ret>'        -docstring 'previous buffer'
map global buffers r ': edit!<ret>'                  -docstring 'revert buffer'
map global buffers s ': write<ret>'                  -docstring 'save buffer'
map global buffers S ': write-all<ret>'              -docstring 'save all buffers'
map global buffers x ': edit -scratch *scratch*<ret>' -docstring 'scratch buffer'
map global buffers i ': ok-buffers-list<ret>'        -docstring 'list buffers'

map global user b ': enter-user-mode buffers<ret>' -docstring 'buffers'
``)
