# fzf — common fzf launch helper used by files, search, jump modules
#
# Windowing strategy:
#   zellij: floating pane via `zellij run --floating --close-on-exit` (async)
#   tmux:   popup via `tmux popup -E` (blocks until done)
#   other:  emit kak `terminal` command for kak to handle
#
# In all cases the fzf callback is run inside the new pane/popup/terminal,
# and it sends the final result back to kak via `kak -p session`.
#
# XDG_RUNTIME_DIR note: the kak wrapper may override XDG_RUNTIME_DIR for kak's
# own socket, breaking zellij's session lookup. We save the original value in
# OK_OUTER_XDG_RUNTIME_DIR (set by the kak wrapper) and restore it when calling
# zellij so it can find its own session sockets.

(import ./kak)

(defn sh-quote [s]
  "POSIX shell escaping."
  (string "'" (string/replace-all "'" "'\\''" s) "'"))

(defn run-fzf [dir list-cmd fzf-args]
  "Run fzf picker in the specified directory."
  (def list-cmd-str
    (if (string? list-cmd)
      list-cmd
      (string/join (map sh-quote list-cmd) " ")))
  (def cmd-str
    (string "cd " (sh-quote dir) " && "
            list-cmd-str " | SHELL=sh fzf "
            (string/join (map sh-quote fzf-args) " ")
            " | sed 's/\\x1b\\[[0-9;]*[mGKHF]//g'"))
  (def p (os/spawn ["sh" "-c" cmd-str] :px {:out :pipe}))
  (def out (:read (get p :out) :all))
  (def status (:wait p))
  (if (= status 0)
    (string/trimr (or out ""))
    nil))

(defn send-to-kak [session cmd]
  "Send a command back to Kakoune via socket."
  (def p (os/spawn ["kak" "-p" session] :px {:in :pipe}))
  (:write (get p :in) cmd)
  (:close (get p :in))
  (:wait p))

(defn- get-forward-env []
  (def env-map (os/environ))
  (def result @[])
  (eachp [k v] env-map
    (when (and k (not= k "") v)
      (array/push result (string k "=" v))))
  result)

(defn- zellij-run [cmd-args hint]
  (def forwarded-env (get-forward-env))
  (def sess (os/getenv "ZELLIJ_SESSION_NAME"))
  (def orig-xdg (os/getenv "OK_OUTER_XDG_RUNTIME_DIR"))
  (def cur-xdg  (os/getenv "XDG_RUNTIME_DIR"))

  (os/setenv "XDG_RUNTIME_DIR" (if (and orig-xdg (not= orig-xdg "")) orig-xdg nil))

  (def zellij-cmd ["zellij" "--session" sess
                   "run" "--floating" "--close-on-exit" "--"
                   "env" ;forwarded-env ;cmd-args])
  
  (def out-path (or (os/getenv "OK_ZELLIJ_OUT_PATH") "/dev/null"))
  (def err-path (or (os/getenv "OK_ZELLIJ_ERR_PATH") "/dev/null"))
  (def devout (file/open out-path :w))
  (def deverr (file/open err-path :w))
  (def p (os/spawn zellij-cmd :p {:out devout :err deverr}))
  (when p (:wait p))
  (file/close devout)
  (file/close deverr)
  (os/setenv "XDG_RUNTIME_DIR" cur-xdg)
  (print (string "echo -markup '{Information}fzf: " hint "'")))

(defn launch
  `Refactored FZF launcher using structured callback arguments.`
  [session client hint module action & args]
  (def cmd-args ["ok" "--api" (string module) (string "pick-" action) session client ;args])
  (def forwarded-env (get-forward-env))

  (cond
    (os/getenv "ZELLIJ_SESSION_NAME")
    (zellij-run cmd-args hint)

    (os/getenv "TMUX")
    (let [out-path (or (os/getenv "OK_TMUX_OUT_PATH") "/dev/null")
          err-path (or (os/getenv "OK_TMUX_ERR_PATH") "/dev/null")
          devout (file/open out-path :w)
          deverr (file/open err-path :w)
          p (os/spawn ["tmux" "popup" "-w" "85%" "-h" "85%" "-E" "--"
                       "env" ;forwarded-env ;cmd-args]
                      :p {:out devout :err deverr})]
      (when p (:wait p))
      (file/close devout)
      (file/close deverr))

    # fallback — emit kak `terminal` command; kak opens a terminal for us
    (let [fallback-cmd ["env" ;forwarded-env ;cmd-args]]
      (print (string "terminal " (string/join (map kak/q fallback-cmd) " "))))))
