# buffers — SPC-b: buffer management

(import ./kak)

# ── Janet API Handlers ────────────────────────────────────────────────────────

(defn- last-buffer [bufname quoted-buflist]
  (def buflist (kak/parse-quoted-list (or quoted-buflist "")))
  (var last nil)
  (each buf buflist
    (when (and (not= buf bufname) (nil? last))
      (set last buf)))
  (when last
    (print (kak/compile-expr [:buffer last]))))

(defn- new-buffer []
  (def name (string "*scratch-" (os/time) "*"))
  (print (kak/compile-expr [:edit :scratch name])))

(defn- kill-others [bufname quoted-buflist]
  (def buflist (kak/parse-quoted-list (or quoted-buflist "")))
  (def cmds @[])
  (each buf buflist
    (when (not= buf bufname)
      (array/push cmds [:try [:delete-buffer buf]])))
  (print (kak/compile-expr [:block ;cmds])))

(defn- kill-all [quoted-buflist]
  (def buflist (kak/parse-quoted-list (or quoted-buflist "")))
  (def cmds @[])
  (each buf buflist
    (array/push cmds [:try [:delete-buffer buf]]))
  (print (kak/compile-expr [:block ;cmds])))

(defn- list-buffers [quoted-buflist]
  (def buflist (kak/parse-quoted-list (or quoted-buflist "")))
  (def filtered-bufs @[])
  (each buf buflist
    (unless (string/has-prefix? "*" buf)
      (array/push filtered-bufs buf)))
  (def bufs-str (string (string/join filtered-bufs "\n") "\n"))
  (def cmds
    [[:edit :scratch "*buflist*"]
     [:set-option :buffer :filetype "scratch"]
     [:set-register "\"" bufs-str]
     [:execute-keys "%<a-d>Pgg"]
     [:map :buffer :normal "<ret>"
      (kak/compile-expr [:evaluate-commands
                         [:sh (kak/api-cmd :buffers :list-select :selection)]])]
     [:map :buffer :normal "d"
      (kak/compile-expr [:evaluate-commands
                         [:sh (kak/api-cmd :buffers :list-delete :selection :quoted_buflist)]])]])
  (print (kak/compile-expr [:block ;cmds])))

(defn- list-select [selection]
  (print (kak/compile-expr [:buffer selection])))

(defn- list-delete [selection quoted-buflist]
  (def cmds
    [[:try [:delete-buffer selection]]
     [:try [:delete-buffer "*buflist*"]]
     [:evaluate-commands [:sh (kak/api-cmd :buffers :list :quoted_buflist)]]])
  (print (kak/compile-expr [:block ;cmds])))

# ── API Dispatch ──────────────────────────────────────────────────────────────

(defn dispatch [argv]
  (case (get argv 0)
    "last"        (last-buffer (get argv 1) (get argv 2))
    "new"         (new-buffer)
    "kill-others" (kill-others (get argv 1) (get argv 2))
    "kill-all"    (kill-all (get argv 1))
    "list"        (list-buffers (get argv 1))
    "list-select" (list-select (get argv 1))
    "list-delete" (list-delete (get argv 1) (get argv 2))
    (do
      (eprintf "ok --api buffers: unknown action '%s'\n" (get argv 0 ""))
      (os/exit 1))))

# ── Kakoune Setup Registration ────────────────────────────────────────────────

(defn register []
  (string
    "# ── buffers (SPC-b) ───────────────────────────────────────────────────────────\n"
    (kak/declare-user-mode :buffers) "\n"

    (kak/compile-expr
      [:define-command :ok-buffers-switch :docstring "switch to buffer by name (fuzzy completion)"
       [:block
        [:prompt :menu "buffer: " :buffer-completion [:block [:raw "buffer %val{text}"]]]]]) "\n"

    (kak/defcmd-api :ok-buffers-last "switch to last (alternate) buffer" :buffers :last [:bufname :quoted_buflist]) "\n"
    (kak/defcmd-api :ok-buffers-new "open a new empty scratch buffer" :buffers :new []) "\n"
    (kak/defcmd-api :ok-buffers-kill-others "kill all buffers except the current one" :buffers :kill-others [:bufname :quoted_buflist]) "\n"
    (kak/defcmd-api :ok-buffers-kill-all "kill all buffers" :buffers :kill-all [:quoted_buflist]) "\n"
    (kak/defcmd-api :ok-buffers-list "list open buffers in a scratch buffer" :buffers :list [:quoted_buflist]) "\n"

    (kak/map :global :buffers "b" ":ok-buffers-switch<ret>" :docstring "switch buffer") "\n"
    (kak/map :global :buffers "[" ":buffer-previous<ret>" :docstring "previous buffer") "\n"
    (kak/map :global :buffers "]" ":buffer-next<ret>" :docstring "next buffer") "\n"
    (kak/map :global :buffers "d" ":delete-buffer<ret>" :docstring "kill buffer") "\n"
    (kak/map :global :buffers "k" ":delete-buffer<ret>" :docstring "kill buffer") "\n"
    (kak/map :global :buffers "K" ":ok-buffers-kill-all<ret>" :docstring "kill all buffers") "\n"
    (kak/map :global :buffers "l" ":ok-buffers-last<ret>" :docstring "last buffer") "\n"
    (kak/map :global :buffers "n" ":buffer-next<ret>" :docstring "next buffer") "\n"
    (kak/map :global :buffers "N" ":ok-buffers-new<ret>" :docstring "new scratch buffer") "\n"
    (kak/map :global :buffers "O" ":ok-buffers-kill-others<ret>" :docstring "kill other buffers") "\n"
    (kak/map :global :buffers "p" ":buffer-previous<ret>" :docstring "previous buffer") "\n"
    (kak/map :global :buffers "r" ":edit!<ret>" :docstring "revert buffer") "\n"
    (kak/map :global :buffers "s" ":write<ret>" :docstring "save buffer") "\n"
    (kak/map :global :buffers "S" ":write-all<ret>" :docstring "save all buffers") "\n"
    (kak/map :global :buffers "x" ":edit -scratch *scratch*<ret>" :docstring "scratch buffer") "\n"
    (kak/map :global :buffers "i" ":ok-buffers-list<ret>" :docstring "list buffers") "\n"

    (kak/map :global :user "b" ":enter-user-mode buffers<ret>" :docstring "buffers") "\n"
  ))
