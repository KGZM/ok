# files — SPC-f: file navigation
#
# Doom equivalents:
#   SPC-f-f  find file (fd/find + fzf)
#   SPC-f-s  save file
#   SPC-f-e  file explorer (yazi/ranger/lf in new pane)
#   SPC-f-t  terminal at current directory

(import ./fzf)

(defn- find-file [argv]
  # argv: [session client dir]
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
      "[ -n \"$result\" ] && printf 'evaluate-commands -client %s edit %%{%s}\\n'"
        " '" client "' \"$result\" | kak -p '" session "'\n")
    "pick a file"))

(defn- explorer [argv]
  # argv: [session client dir]
  (def session (get argv 0))
  (def client  (get argv 1))
  (def dir     (get argv 2 "."))

  (fzf/launch session
    (string
      "cd '" dir "'\n"
      "if command -v yazi > /dev/null 2>&1; then\n"
      "  chosen=$(mktemp)\n"
      "  yazi --chooser-file \"$chosen\"\n"
      "  result=$(cat \"$chosen\" 2>/dev/null); rm -f \"$chosen\"\n"
      "elif command -v ranger > /dev/null 2>&1; then\n"
      "  chosen=$(mktemp)\n"
      "  ranger --chooser-file=\"$chosen\"\n"
      "  result=$(cat \"$chosen\" 2>/dev/null); rm -f \"$chosen\"\n"
      "elif command -v lf > /dev/null 2>&1; then\n"
      "  chosen=$(mktemp)\n"
      "  lf -selection-path \"$chosen\"\n"
      "  result=$(cat \"$chosen\" 2>/dev/null); rm -f \"$chosen\"\n"
      "fi\n"
      "[ -n \"$result\" ] && printf 'evaluate-commands -client %s edit %%{%s}\\n'"
        " '" client "' \"$result\" | kak -p '" session "'\n")
    "file explorer"))

(defn dispatch [argv]
  (case (get argv 0)
    "find"     (find-file (array/slice argv 1))
    "explorer" (explorer  (array/slice argv 1))
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

map global files f ': ok-files-find<ret>'      -docstring 'find file'
map global files s ': write<ret>'             -docstring 'save file'
map global files e ': ok-files-explorer<ret>'  -docstring 'file explorer'
map global files t ': ok-files-terminal<ret>'  -docstring 'terminal here'

map global user f ': enter-user-mode files<ret>' -docstring 'files'
``)
