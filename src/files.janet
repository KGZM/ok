# files — SPC-f: file navigation
#
# Doom equivalents (SPC-f):
#   SPC-f-f  find file (fd/find + fzf)
#   SPC-f-r  recent files (fzf)
#   SPC-f-s  save file
#   SPC-f-R  rename/move current file
#   SPC-f-D  delete current file
#   SPC-f-y  yank file path
#   SPC-f-Y  yank file path relative to project root
#
# SPC-o (open) equivalents also mapped here since kak has no frames:
#   SPC-f-e  file explorer (yazi/ranger/lf) — Doom's SPC-o--
#   SPC-f-t  terminal at current dir       — Doom's SPC-o-T

(import ./fzf)

(defn- find-file [argv]
  (def session (get argv 0))
  (def client  (get argv 1))
  (def dir     (get argv 2 "."))

  (fzf/launch session
    (string
      "cd '" dir "'\n"
      "if command -v fd > /dev/null 2>&1; then\n"
      "  list() { fd --type f --hidden --exclude .git; }\n"
      "else\n"
      "  list() { find . -type f -not -path '*/.git/*'; }\n"
      "fi\n"
      "result=$(list | fzf"
        " --preview 'head -100 {}'"
        " --preview-window 'right:50%:wrap'"
        " --prompt 'file> '"
        " --height 100%)\n"
      "[ -n \"$result\" ] && printf 'evaluate-commands -client %s edit %%{%s/%s}\\n'"
        " '" client "' '" dir "' \"$result\" | kak -p '" session "'\n")
    "find file"))

(defn- recent-files [argv]
  (def session (get argv 0))
  (def client  (get argv 1))
  (def dir     (get argv 2 "."))

  (fzf/launch session
    (string
      "cd '" dir "'\n"
      "# Recent files: git-tracked files sorted by mtime, fallback to find -newer\n"
      "if git rev-parse --git-dir > /dev/null 2>&1; then\n"
      "  list() {\n"
      "    git ls-files -z | xargs -0 ls -t 2>/dev/null | head -100\n"
      "  }\n"
      "else\n"
      "  list() { find . -type f -not -path '*/.git/*' -newer . | head -100; }\n"
      "fi\n"
      "result=$(list | fzf"
        " --preview 'head -100 {}'"
        " --preview-window 'right:50%:wrap'"
        " --prompt 'recent> '"
        " --height 100%)\n"
      "[ -n \"$result\" ] && printf 'evaluate-commands -client %s edit %%{%s/%s}\\n'"
        " '" client "' '" dir "' \"$result\" | kak -p '" session "'\n")
    "recent files"))

(defn- explorer [argv]
  (def session (get argv 0))
  (def client  (get argv 1))
  (def dir     (get argv 2 "."))

  (fzf/launch session
    (string
      "cd '" dir "'\n"
      "if command -v yazi > /dev/null 2>&1; then\n"
      "  chosen=$(mktemp); yazi --chooser-file \"$chosen\"\n"
      "  result=$(cat \"$chosen\" 2>/dev/null); rm -f \"$chosen\"\n"
      "elif command -v ranger > /dev/null 2>&1; then\n"
      "  chosen=$(mktemp); ranger --chooser-file=\"$chosen\"\n"
      "  result=$(cat \"$chosen\" 2>/dev/null); rm -f \"$chosen\"\n"
      "elif command -v lf > /dev/null 2>&1; then\n"
      "  chosen=$(mktemp); lf -selection-path \"$chosen\"\n"
      "  result=$(cat \"$chosen\" 2>/dev/null); rm -f \"$chosen\"\n"
      "fi\n"
      "[ -n \"$result\" ] && printf 'evaluate-commands -client %s edit %%{%s}\\n'"
        " '" client "' \"$result\" | kak -p '" session "'\n")
    "file explorer"))

(defn dispatch [argv]
  (case (get argv 0)
    "find"    (find-file    (array/slice argv 1))
    "recent"  (recent-files (array/slice argv 1))
    "explorer" (explorer   (array/slice argv 1))
    (do (eprintf "ok --api files: unknown command '%s'\n" (get argv 0 ""))
        (os/exit 1))))

(defn register []
  ``
# ── files (SPC-f) ─────────────────────────────────────────────────────────────
declare-user-mode files

define-command ok-files-find \
  -docstring 'fuzzy find file and open it (fd/find + fzf)' %{
  evaluate-commands %sh{
    ok --api files find "$kak_session" "$kak_client" "$(pwd)"
  }
}

define-command ok-files-recent \
  -docstring 'find recent file (fzf over git-tracked files by mtime)' %{
  evaluate-commands %sh{
    ok --api files recent "$kak_session" "$kak_client" "$(pwd)"
  }
}

define-command ok-files-explorer \
  -docstring 'open file explorer (yazi/ranger/lf)' %{
  evaluate-commands %sh{
    ok --api files explorer "$kak_session" "$kak_client" "$(pwd)"
  }
}

define-command ok-files-terminal \
  -docstring 'open terminal in current directory' %{
  terminal sh -c %sh{ printf 'cd %s && exec "$SHELL"' "$(pwd)" }
}

define-command ok-files-rename \
  -docstring 'rename/move current file' %{
  evaluate-commands %sh{
    old=$kak_buffile
    if [ -z "$old" ]; then echo "fail 'no file'"; exit; fi
    printf 'prompt %%{rename to: } %%{evaluate-commands %%sh{\n'
    printf '  new="%%val{text}"\n'
    printf '  mv "%s" "$new" && printf "edit %%s\\\\ndelete-buffer\\\\n" "$new"\n' "$old"
    printf '}}\n'
  }
}

define-command ok-files-delete \
  -docstring 'delete current file and close buffer' %{
  evaluate-commands %sh{
    file=$kak_buffile
    if [ -z "$file" ]; then echo "fail 'no file'"; exit; fi
    printf 'prompt -init no %%{delete %s? [yes/no]: } %%{\n' "$file"
    printf '  evaluate-commands %%sh{\n'
    printf '    [ "%%val{text}" = yes ] && rm -f "%s" && echo "delete-buffer"\n' "$file"
    printf '  }\n'
    printf '}\n'
  }
}

define-command ok-files-yank-path \
  -docstring 'yank absolute path of current file' %{
  evaluate-commands %sh{
    printf 'set-register dquote %%{%s}\n' "$kak_buffile"
    printf 'echo -markup %%{{Information}yanked: %s}\n' "$kak_buffile"
  }
}

define-command ok-files-yank-relative \
  -docstring 'yank path of current file relative to project root' %{
  evaluate-commands %sh{
    root=$(git -C "$(pwd)" rev-parse --show-toplevel 2>/dev/null || pwd)
    rel="${kak_buffile#$root/}"
    printf 'set-register dquote %%{%s}\n' "$rel"
    printf 'echo -markup %%{{Information}yanked: %s}\n' "$rel"
  }
}

map global files f ': ok-files-find<ret>'         -docstring 'find file'
map global files r ': ok-files-recent<ret>'       -docstring 'recent files'
map global files s ': write<ret>'                 -docstring 'save file'
map global files R ': ok-files-rename<ret>'       -docstring 'rename file'
map global files D ': ok-files-delete<ret>'       -docstring 'delete file'
map global files y ': ok-files-yank-path<ret>'    -docstring 'yank path'
map global files Y ': ok-files-yank-relative<ret>' -docstring 'yank relative path'
map global files e ': ok-files-explorer<ret>'     -docstring 'file explorer'
map global files t ': ok-files-terminal<ret>'     -docstring 'terminal here'

map global user f ': enter-user-mode files<ret>' -docstring 'files'
``)
