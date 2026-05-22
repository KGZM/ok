# jump — SPC-j: easymotion / avy-style navigation
#
# Doom/avy equivalents:
#   SPC-j-l  jump to line (fzf swiper — line numbers + content)
#   SPC-j-c  jump to char: type char, highlights all viewport occurrences,
#             type [1-9] to jump to Nth (ordered top→bottom from cursor)
#   SPC-j-w  jump to word start: same but targets \b\w
#   SPC-j-d  jump to LSP definition
#   SPC-j-r  jump to LSP references
#
# Easymotion notes:
#   kak range-specs color ranges but don't overlay text labels, so we use
#   numbered selection (1-9) rather than lettered labels. The highlighted
#   positions are colored distinctively and numbered by buffer order.
#   Full avy-style text labels require a buffer overlay strategy (future work).

(import ./fzf)

(defn- jump-line [argv]
  # argv: [session client buffile]
  (def session (get argv 0))
  (def client  (get argv 1))
  (def buffile (get argv 2 ""))

  (when (= buffile "")
    (print "fail 'ok-jump-line: no file (scratch buffers not supported)'")
    (os/exit 0))

  (fzf/launch session
    (string
      "result=$(grep -n '' '" buffile "' \\\n"
      "  | fzf"
        " --delimiter ':'"
        " --nth '2..'"
        " --preview 'grep -n \"\" '" buffile
            "' | sed -n \"$(($(echo {} | cut -d: -f1)-5)),$(($(echo {} | cut -d: -f1)+20))p\"'"
        " --preview-window 'right:50%:wrap'"
        " --prompt 'jump> '"
        " --height 100%)\n"
      "if [ -n \"$result\" ]; then\n"
      "  line=$(printf '%s' \"$result\" | cut -d: -f1)\n"
      "  printf 'evaluate-commands -client %s execute-keys %%{%sg}\\n'"
        " '" client "' \"$line\" | kak -p '" session "'\n"
      "fi\n")
    "jump to line"))

(defn dispatch [argv]
  (case (get argv 0)
    "line" (jump-line (array/slice argv 1))
    (do (eprintf "ok --api jump: unknown command '%s'\n" (get argv 0 ""))
        (os/exit 1))))

(defn register []
  ``
# ── jump / easymotion (SPC-j) ─────────────────────────────────────────────────
declare-user-mode jump

declare-option -hidden range-specs ok_jump_overlay
declare-option -hidden str         ok_jump_targets  # "N:line:col ..." space-sep

define-command -hidden ok-jump-clear %{
  try %{ remove-highlighter window/ok-jump }
  set-option window ok_jump_overlay %val{timestamp}
  set-option window ok_jump_targets ''
}

# Jump to the Nth stored position (kak_key should be 1-9)
define-command -hidden ok-jump-to-n %{
  evaluate-commands %sh{
    n=$kak_key
    for entry in $kak_opt_ok_jump_targets; do
      idx="${entry%%:*}"
      rest="${entry#*:}"
      line="${rest%%:*}"
      col="${rest##*:}"
      if [ "$idx" = "$n" ]; then
        printf 'select %s.%s,%s.%s\n' "$line" "$col" "$line" "$col"
        break
      fi
    done
  }
  ok-jump-clear
}

# Find all occurrences of $1 (regex) in viewport (~40 lines around cursor).
# Highlights them with DiagnosticWarning face, stores positions as 1-9.
define-command -hidden ok-jump-collect -params 1 %{
  ok-jump-clear
  evaluate-commands -draft %{
    evaluate-commands %sh{
      regex=$1
      line=$kak_cursor_line
      top=$((line > 20 ? line - 20 : 1))
      bot=$((line + 20))
      printf 'select %d.1,%d.9999\n' "$top" "$bot"
    }
    evaluate-commands %sh{ printf 'execute-keys "s%s<ret>"\n' "$1" }
    evaluate-commands %sh{
      i=1
      ranges="%val{timestamp}"
      targets=""
      for desc in $(printf '%s' "$kak_selections_desc" | tr ':' '\n'); do
        [ "$i" -gt 9 ] && break
        start="${desc%%,*}"
        r="${start%%.*}"
        c="${start##*.}"
        ranges="$ranges ${r}.${c},${r}.${c}|DiagnosticWarning"
        targets="$targets ${i}:${r}:${c}"
        i=$((i+1))
      done
      printf 'set-option window ok_jump_overlay %s\n' "$ranges"
      printf "set-option window ok_jump_targets '%s'\n" "$targets"
      printf 'echo -markup %%{{Information}jump: [1-%d] to pick, <esc> cancel}\n' "$((i-1))"
    }
  }
  add-highlighter window/ok-jump ranges ok_jump_overlay
}

define-command ok-jump-char \
  -docstring 'easymotion: highlight visible occurrences of char, [1-9] to jump' %{
  on-key %{
    evaluate-commands %{
      ok-jump-collect %val{key}
      on-key %{
        evaluate-commands %sh{
          case $kak_key in
            [1-9]) echo 'ok-jump-to-n' ;;
            *)     echo 'ok-jump-clear' ;;
          esac
        }
      }
    }
  }
}

define-command ok-jump-word \
  -docstring 'easymotion: highlight visible word starts, [1-9] to jump' %{
  ok-jump-collect '\b\w'
  on-key %{
    evaluate-commands %sh{
      case $kak_key in
        [1-9]) echo 'ok-jump-to-n' ;;
        *)     echo 'ok-jump-clear' ;;
      esac
    }
  }
}

define-command ok-jump-line \
  -docstring 'jump to line (fzf swiper)' %{
  evaluate-commands %sh{
    ok --api jump line "$kak_session" "$kak_client" "$kak_buffile"
  }
}

map global jump c ': ok-jump-char<ret>'        -docstring 'jump to char [easymotion]'
map global jump w ': ok-jump-word<ret>'        -docstring 'jump to word [easymotion]'
map global jump l ': ok-jump-line<ret>'        -docstring 'jump to line [fzf]'
map global jump d ': lsp-definition<ret>'      -docstring 'definition [LSP]'
map global jump r ': lsp-references<ret>'      -docstring 'references [LSP]'
map global jump D ': lsp-type-definition<ret>' -docstring 'type definition [LSP]'

map global user j ': enter-user-mode jump<ret>' -docstring 'jump'
``)
