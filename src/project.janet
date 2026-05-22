# project — SPC-p: project-level operations
#
# Doom equivalents (SPC-p):
#   SPC-p-f  find file in project (from git root)
#   SPC-p-b  switch to project buffer
#   SPC-p-p  switch project (pick a git repo with fzf)
#   SPC-p-k  kill all project buffers
#   SPC-p-s  save all project buffers
#   SPC-p-!  run shell command in project root
#
# Project root: detected via `git rev-parse --show-toplevel`, fallback to cwd.

(import ./fzf)

(defn- project-root [cwd]
  (def result @"")
  (def proc (os/spawn
    ["git" "-C" cwd "rev-parse" "--show-toplevel"]
    :p {:out :pipe :err :pipe}))
  (ev/read (proc :out) math/int-max result)
  (:wait proc)
  (def root (string/trimr (string result)))
  (if (= root "") cwd root))

(defn- find-in-project [argv]
  (def session (get argv 0))
  (def client  (get argv 1))
  (def cwd     (get argv 2 "."))
  (def root    (project-root cwd))

  (fzf/launch session
    (string
      "cd '" root "'\n"
      "if command -v fd > /dev/null 2>&1; then\n"
      "  list() { fd --type f --hidden --exclude .git; }\n"
      "else\n"
      "  list() { find . -type f -not -path '*/.git/*'; }\n"
      "fi\n"
      "result=$(list | fzf"
        " --preview 'head -100 {}'"
        " --preview-window 'right:50%:wrap'"
        " --prompt 'project> '"
        " --height 100%)\n"
      "[ -n \"$result\" ] && printf 'evaluate-commands -client %s edit %%{%s/%s}\\n'"
        " '" client "' '" root "' \"$result\" | kak -p '" session "'\n")
    "find in project"))

(defn- switch-project [argv]
  (def session (get argv 0))
  (def client  (get argv 1))

  # Search common project parent dirs for git repos
  (fzf/launch session
    (string
      "dirs=\"$HOME/projects $HOME/src $HOME/work $HOME/packages\"\n"
      "result=$(for d in $dirs; do\n"
      "  [ -d \"$d\" ] && find \"$d\" -maxdepth 3 -name '.git' -type d 2>/dev/null"
        " | sed 's|/.git$||'\n"
      "done | fzf --prompt 'project> ' --height 100%)\n"
      "[ -n \"$result\" ] && printf 'evaluate-commands -client %s change-directory %%{%s}\\n'"
        " '" client "' \"$result\" | kak -p '" session "'\n")
    "switch project"))

(defn dispatch [argv]
  (case (get argv 0)
    "find"   (find-in-project (array/slice argv 1))
    "switch" (switch-project  (array/slice argv 1))
    (do (eprintf "ok --api project: unknown command '%s'\n" (get argv 0 ""))
        (os/exit 1))))

(defn register []
  ``
# ── project (SPC-p) ───────────────────────────────────────────────────────────
declare-user-mode project

define-command ok-project-root -docstring 'print project root to status line' %{
  evaluate-commands %sh{
    root=$(git -C "$(pwd)" rev-parse --show-toplevel 2>/dev/null || pwd)
    printf 'echo -markup %%{{Information}project: %s}\n' "$root"
  }
}

define-command ok-project-find \
  -docstring 'find file in project root (fd/find + fzf)' %{
  evaluate-commands %sh{
    ok --api project find "$kak_session" "$kak_client" "$(pwd)"
  }
}

define-command ok-project-switch \
  -docstring 'switch project (fzf over known git repos)' %{
  evaluate-commands %sh{
    ok --api project switch "$kak_session" "$kak_client"
  }
}

define-command ok-project-kill-buffers \
  -docstring 'kill all buffers in current project' %{
  evaluate-commands %sh{
    root=$(git -C "$(pwd)" rev-parse --show-toplevel 2>/dev/null || pwd)
    for buf in $kak_opt_buflist; do
      case "$buf" in
        "$root"*) printf 'try %%{ delete-buffer %%{%s} }\n' "$buf" ;;
      esac
    done
  }
}

define-command ok-project-save-buffers \
  -docstring 'save all modified buffers in current project' %{
  evaluate-commands %sh{
    root=$(git -C "$(pwd)" rev-parse --show-toplevel 2>/dev/null || pwd)
    for buf in $kak_opt_buflist; do
      case "$buf" in
        "$root"*) printf 'try %%{ write %%{%s} }\n' "$buf" ;;
      esac
    done
  }
}

define-command ok-project-shell \
  -docstring 'run shell command in project root' %{
  evaluate-commands %sh{
    root=$(git -C "$(pwd)" rev-parse --show-toplevel 2>/dev/null || pwd)
    printf 'terminal sh -c %%{cd %s && exec "$SHELL"}\n' "$root"
  }
}

map global project f ': ok-project-find<ret>'         -docstring 'find file'
map global project p ': ok-project-switch<ret>'       -docstring 'switch project'
map global project r ': ok-project-root<ret>'         -docstring 'show project root'
map global project k ': ok-project-kill-buffers<ret>' -docstring 'kill buffers'
map global project s ': ok-project-save-buffers<ret>' -docstring 'save buffers'
map global project ! ': ok-project-shell<ret>'        -docstring 'shell at root'

map global user p ': enter-user-mode project<ret>' -docstring 'project'
``)
