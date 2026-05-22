# search — SPC-s: search commands
#
# Doom equivalents:
#   SPC-s-s  search buffer lines (fzf, jump to line)
#   SPC-s-p  search project with ripgrep + fzf
#   SPC-s-w  search project for word under cursor
#   SPC-s-n  search forward (kak native)
#   SPC-s-N  search backward (kak native)

(import ./fzf)

(defn- search-buffer [argv]
  # argv: [session client buffile cursor-line]
  (def session     (get argv 0))
  (def client      (get argv 1))
  (def buffile     (get argv 2 ""))
  (def cursor-line (get argv 3 "1"))

  (when (= buffile "")
    (print "fail 'ok-search-buffer: no file (scratch buffers not supported)'")
    (os/exit 0))

  (fzf/launch session
    (string
      "result=$(grep -n '' '" buffile "' \\\n"
      "  | fzf"
        " --delimiter ':'"
        " --nth '2..'"
        " --preview 'grep -n \"\" '" buffile "' | sed -n \"{1},$((1+30))p\"'"
        " --preview-window 'right:50%:wrap'"
        " --prompt 'line> '"
        " --query ''"
        " --height 100%)\n"
      "if [ -n \"$result\" ]; then\n"
      "  line=$(printf '%s' \"$result\" | cut -d: -f1)\n"
      "  printf 'evaluate-commands -client %s execute-keys %%{%sg}\\n'"
        " '" client "' \"$line\" | kak -p '" session "'\n"
      "fi\n")
    "searching buffer"))

(defn- search-project [argv]
  # argv: [session client dir query]
  (def session (get argv 0))
  (def client  (get argv 1))
  (def dir     (get argv 2 "."))
  (def query   (get argv 3 ""))

  (fzf/launch session
    (string
      "cd '" dir "'\n"
      "if ! command -v rg > /dev/null 2>&1; then\n"
      "  echo 'ripgrep (rg) not found'; exit 1\n"
      "fi\n"
      "result=$(rg --line-number --color=always --smart-case '' \\\n"
      "  | fzf --ansi"
           " --delimiter ':'"
           " --nth '1,3..'"
           " --preview 'head -100 {1}'"
           " --preview-window 'right:50%:wrap'"
           " --prompt 'project> '"
           " --query '" query "'"
           " --height 100%)\n"
      "if [ -n \"$result\" ]; then\n"
      "  file=$(printf '%s' \"$result\" | cut -d: -f1)\n"
      "  line=$(printf '%s' \"$result\" | cut -d: -f2)\n"
      "  printf 'evaluate-commands -client %s %%{edit %%{%s}; execute-keys %%{%sg}}\\n'"
        " '" client "' \"$file\" \"$line\" | kak -p '" session "'\n"
      "fi\n")
    "searching project"))

(defn dispatch [argv]
  (case (get argv 0)
    "buffer"  (search-buffer  (array/slice argv 1))
    "project" (search-project (array/slice argv 1))
    (do (eprintf "ok --api search: unknown command '%s'\n" (get argv 0 ""))
        (os/exit 1))))

(defn register []
  ``
# ── search (SPC-s) ────────────────────────────────────────────────────────────
declare-user-mode search

define-command ok-search-buffer \
  -docstring 'search buffer lines with fzf, jump to selection' %{
  evaluate-commands %sh{
    ok --api search buffer \
      "$kak_session" "$kak_client" "$kak_buffile" "$kak_cursor_line"
  }
}

define-command ok-search-project \
  -docstring 'search project with ripgrep + fzf' %{
  evaluate-commands %sh{
    ok --api search project "$kak_session" "$kak_client" "$(pwd)"
  }
}

define-command ok-search-word \
  -docstring 'search project for word under cursor' %{
  evaluate-commands %sh{
    ok --api search project \
      "$kak_session" "$kak_client" "$(pwd)" "$kak_selection"
  }
}

map global search s ': ok-search-buffer<ret>'   -docstring 'search buffer'
map global search p ': ok-search-project<ret>'  -docstring 'search project'
map global search w ': ok-search-word<ret>'     -docstring 'search word'
map global search n ': execute-keys //<ret>'    -docstring 'search forward'
map global search N ': execute-keys <lt>a-/><lt>a-/><ret>' -docstring 'search backward'

map global user s ': enter-user-mode search<ret>' -docstring 'search'
``)
