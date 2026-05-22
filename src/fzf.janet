# fzf — common fzf launch helper used by files, search, jump modules
#
# Windowing strategy:
#   zellij: floating pane via `zellij run --floating --close-on-exit` (async)
#   tmux:   popup via `tmux popup -E` (blocks until done)
#   other:  emit kak `terminal` command for kak to handle
#
# In all cases the fzf script sends its result back to kak via `kak -p session`.

(defn- tmpfile []
  (string "/tmp/ok-fzf-" (os/getpid) "-" (% (os/time) 99999) ".sh"))

(defn launch
  `Run script-body in an fzf pane appropriate for the current windowing env.
  session: kak session name (for kak -p calls inside the script)
  script-body: shell script content — must end by calling kak -p internally
  hint: short status string shown in zellij case (e.g. 'searching files')
  Returns kak commands to print (status echo etc), or nothing for tmux.`
  [session script-body hint]
  (def f (tmpfile))
  (spit f (string "#!/bin/sh\n" script-body "\nrm -f '" f "'\n"))
  (os/execute ["chmod" "+x" f] :p)

  (cond
    (os/getenv "ZELLIJ_SESSION_NAME")
    (do
      # async — floating pane opens, user picks, kak -p sends result back
      (os/execute
        ["zellij"
         "--session" (os/getenv "ZELLIJ_SESSION_NAME")
         "run" "--floating" "--close-on-exit" "--" "sh" f]
        :p)
      (print (string "echo -markup '{Information}fzf: " hint "'")))

    (os/getenv "TMUX")
    # blocking — tmux popup runs fzf, script calls kak -p, popup closes, we return
    (os/execute ["sh" "-c" (string "tmux popup -w 85% -h 85% -E 'sh " f "'")] :p)

    # fallback — emit kak `terminal` command; kak opens a terminal for us
    (print (string "terminal sh '" f "'"))))
