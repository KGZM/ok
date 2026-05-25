# files — SPC-f: file navigation

(import ./kak)
(import ./env)
(import ./fzf)

(defn- git-repo? [dir]
  (with-dyns [:err (fn [&]) :out (fn [&])]
    (try
      (let [p (os/spawn ["git" "-C" dir "rev-parse" "--git-dir"] :px {:out :null :err :null})]
        (= 0 (:wait p)))
      ([_] false))))

(defn- find-file [argv]
  (def session (get argv 0))
  (def client  (get argv 1))
  (def dir     (get argv 2 "."))
  (fzf/launch session client "find file" :files :find dir))

(defn- pick-find [argv]
  (def session (get argv 0))
  (def client  (get argv 1))
  (def dir     (get argv 2 "."))

  (def find-parts (env/file-find-cmd :exclude ".git"))
  (def fzf-args ["--preview" "head -100 {}"
                 "--preview-window" "right:50%:wrap"
                 "--prompt" "file> "
                 "--height" "100%"])
  (def result (fzf/run-fzf dir find-parts fzf-args))
  (when (and result (not= result ""))
    (def edit-cmd (string "evaluate-commands -client " (kak/quote client) " edit " (kak/quote (string dir "/" result)) "\n"))
    (fzf/send-to-kak session edit-cmd)))

(defn- recent-files [argv]
  (def session (get argv 0))
  (def client  (get argv 1))
  (def dir     (get argv 2 "."))
  (fzf/launch session client "recent files" :files :recent dir))

(defn- pick-recent [argv]
  (def session (get argv 0))
  (def client  (get argv 1))
  (def dir     (get argv 2 "."))

  (def list-cmd
    (if (git-repo? dir)
      "(git status --porcelain | cut -c4-; git log -n 100 --pretty=format: --name-only) | grep -v '^[[:space:]]*$' | awk '!visited[$0]++' | head -100"
      "find . -type f -not -path '*/.git/*' -exec stat -c '%Y %n' {} + 2>/dev/null | sort -rn | cut -d' ' -f2- | head -100"))
  (def fzf-args ["--preview" "head -100 {}"
                 "--preview-window" "right:50%:wrap"
                 "--prompt" "recent> "
                 "--height" "100%"])
  (def result (fzf/run-fzf dir list-cmd fzf-args))
  (when (and result (not= result ""))
    (def edit-cmd (string "evaluate-commands -client " (kak/quote client) " edit " (kak/quote (string dir "/" result)) "\n"))
    (fzf/send-to-kak session edit-cmd)))

(defn- explorer [argv]
  (def session (get argv 0))
  (def client  (get argv 1))
  (def dir     (get argv 2 "."))
  (fzf/launch session client "file explorer" :files :explorer dir))

(defn- pick-explorer [argv]
  (def session (get argv 0))
  (def client  (get argv 1))
  (def dir     (get argv 2 "."))

  (def temp-f (string "/tmp/ok-explorer-chosen-" (os/getpid) ".txt"))

  (def explorer-bin
    (cond
      (env/bin-exists? "yazi")   "yazi"
      (env/bin-exists? "ranger") "ranger"
      (env/bin-exists? "lf")     "lf"
      (error "No supported file explorer (yazi, ranger, lf) found")))

  (def explorer-args
    (case explorer-bin
      "yazi"   ["--chooser-file" temp-f]
      "ranger" [(string "--chooser-file=" temp-f)]
      "lf"     ["-selection-path" temp-f]))

  (def cmd-str
    (string "cd " (fzf/sh-quote dir) " && "
            (string/join (map fzf/sh-quote [explorer-bin ;explorer-args]) " ")))

  (os/execute ["sh" "-c" cmd-str] :p)

  (def result (try (slurp temp-f) ([_] nil)))
  (os/execute ["rm" "-f" temp-f] :p)

  (when (and result (not= result ""))
    (def trimmed (string/trimr result))
    (when (not= trimmed "")
      (def edit-cmd (string "evaluate-commands -client " (kak/quote client) " edit " (kak/quote trimmed) "\n"))
      (fzf/send-to-kak session edit-cmd))))

(defn- open-terminal [argv]
  (def session (get argv 0))
  (def client  (get argv 1))
  (def dir     (get argv 2 "."))
  (def cmd (env/open-pane-cmd ["sh" "-c" (string "cd " (kak/quote dir) " && exec \"$SHELL\"")]))
  (def devnull (file/open "/dev/null" :w))
  (def p (os/spawn cmd :p {:out devnull :err devnull}))
  (when p (:wait p))
  (file/close devnull))

(defn- rename-prompt [argv]
  (def session (get argv 0))
  (def client  (get argv 1))
  (def buffile (get argv 2))
  (if (or (nil? buffile) (empty? buffile))
    (print (kak/compile-expr [:fail "no file"]))
    (print (kak/compile-expr
             [:prompt "rename to: " :init buffile
              [:block
               [:evaluate-commands
                [:sh (kak/api-cmd :files :rename session client buffile [:dq [:val :text]])]]]]))))

(defn- rename-file [argv]
  (def session (get argv 0))
  (def client  (get argv 1))
  (def old-path (get argv 2))
  (def new-path (get argv 3))
  (when (or (nil? old-path) (empty? old-path) (nil? new-path) (empty? new-path))
    (os/exit 0))
  (if (= 0 (os/execute ["mv" old-path new-path] :p))
    (print (kak/compile-expr [:block
                              [:edit new-path]
                              [:delete-buffer old-path]]))
    (print (kak/compile-expr [:fail "Rename failed"]))))

(defn- delete-prompt [argv]
  (def session (get argv 0))
  (def client  (get argv 1))
  (def buffile (get argv 2))
  (if (or (nil? buffile) (empty? buffile))
    (print (kak/compile-expr [:fail "no file"]))
    (print (kak/compile-expr
             [:prompt "delete current file? [yes/no]: " :init "no"
              [:block
               [:evaluate-commands
                [:sh
                 [:raw (string "[ " (kak/compile-expr [:dq [:val :text]]) " = \"yes\" ] && "
                               (kak/api-cmd :files :delete session client buffile))]]]]]))))

(defn- delete-file [argv]
  (def session (get argv 0))
  (def client  (get argv 1))
  (def path    (get argv 2))
  (when (or (nil? path) (empty? path))
    (os/exit 0))
  (if (= 0 (os/execute ["rm" "-f" path] :p))
    (print (kak/compile-expr [:delete-buffer path]))
    (print (kak/compile-expr [:fail "Delete failed"]))))

(defn- yank-path [argv]
  (def buffile (get argv 0))
  (if (or (nil? buffile) (empty? buffile))
    (print (kak/compile-expr [:fail "no file"]))
    (print (kak/compile-expr
             [:block
              [:set-register "dquote" buffile]
              [:echo :markup (string "{Information}yanked: " buffile)]]))))

(defn- yank-relative [argv]
  (def buffile (get argv 0))
  (if (or (nil? buffile) (empty? buffile))
    (print (kak/compile-expr [:fail "no file"]))
    (do
      (def pwd (or (os/getenv "PWD") "."))
      (def git-root-raw (with-dyns [:err (fn [&]) :out (fn [&])]
                          (try
                            (let [p (os/spawn ["git" "rev-parse" "--show-toplevel"] :px {:out :pipe :err :null})]
                              (def out (:read (get p :out) :all))
                              (:wait p)
                              (string/trim out))
                            ([_] nil))))
      (def root (if (or (nil? git-root-raw) (empty? git-root-raw))
                  pwd
                  git-root-raw))
      (var rel buffile)
      (when (string/has-prefix? root buffile)
        (set rel (string/slice buffile (length root)))
        (when (string/has-prefix? "/" rel)
          (set rel (string/slice rel 1))))
      (print (kak/compile-expr
               [:block
                [:set-register "dquote" rel]
                [:echo :markup (string "{Information}yanked: " rel)]])))))

(defn dispatch [argv]
  (case (get argv 0)
    "find"          (find-file       (array/slice argv 1))
    "recent"        (recent-files    (array/slice argv 1))
    "explorer"      (explorer        (array/slice argv 1))
    "terminal"      (open-terminal   (array/slice argv 1))
    "rename-prompt" (rename-prompt   (array/slice argv 1))
    "rename"        (rename-file     (array/slice argv 1))
    "delete-prompt" (delete-prompt   (array/slice argv 1))
    "delete"        (delete-file     (array/slice argv 1))
    "yank-path"     (yank-path       (array/slice argv 1))
    "yank-relative" (yank-relative   (array/slice argv 1))
    "pick-find"     (pick-find       (array/slice argv 1))
    "pick-recent"   (pick-recent     (array/slice argv 1))
    "pick-explorer" (pick-explorer   (array/slice argv 1))
    (do (eprintf "ok --api files: unknown command '%s'\n" (get argv 0 ""))
        (os/exit 1))))

(defn register []
  (string
    "# ── files (SPC-f) ─────────────────────────────────────────────────────────────\n"
    (kak/declare-user-mode :files) "\n"

    (kak/defcmd-api "ok-files-find" "fuzzy find file and open it (fd/find + fzf)" :files :find [:session :client :pwd]) "\n"
    (kak/defcmd-api "ok-files-recent" "find recent file (fzf over git-tracked files by mtime)" :files :recent [:session :client :pwd]) "\n"
    (kak/defcmd-api "ok-files-explorer" "open file explorer (yazi/ranger/lf)" :files :explorer [:session :client :pwd]) "\n"
    (kak/defcmd-api "ok-files-terminal" "open terminal in current directory" :files :terminal [:session :client :pwd]) "\n"
    (kak/defcmd-api "ok-files-rename" "rename/move current file" :files :rename-prompt [:session :client :buffile]) "\n"
    (kak/defcmd-api "ok-files-delete" "delete current file and close buffer" :files :delete-prompt [:session :client :buffile]) "\n"
    (kak/defcmd-api "ok-files-yank-path" "yank absolute path of current file" :files :yank-path [:buffile]) "\n"
    (kak/defcmd-api "ok-files-yank-relative" "yank path of current file relative to project root" :files :yank-relative [:buffile]) "\n"

    (kak/map :global :files "f" ":ok-files-find<ret>" :docstring "find file") "\n"
    (kak/map :global :files "r" ":ok-files-recent<ret>" :docstring "recent files") "\n"
    (kak/map :global :files "s" ":write<ret>" :docstring "save file") "\n"
    (kak/map :global :files "R" ":ok-files-rename<ret>" :docstring "rename file") "\n"
    (kak/map :global :files "D" ":ok-files-delete<ret>" :docstring "delete file") "\n"
    (kak/map :global :files "y" ":ok-files-yank-path<ret>" :docstring "yank path") "\n"
    (kak/map :global :files "Y" ":ok-files-yank-relative<ret>" :docstring "yank relative path") "\n"
    (kak/map :global :files "e" ":ok-files-explorer<ret>" :docstring "file explorer") "\n"
    (kak/map :global :files "t" ":ok-files-terminal<ret>" :docstring "terminal here") "\n"

    (kak/map :global :user "f" ":enter-user-mode files<ret>" :docstring "files") "\n"
  ))
