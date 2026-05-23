# project — SPC-p: project-level operations

(import ./kak)
(import ./env)
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
  (fzf/launch session client "find in project" :project :find root))

(defn- pick-find [argv]
  (def session (get argv 0))
  (def client  (get argv 1))
  (def root    (get argv 2 "."))

  (def find-parts (env/file-find-cmd :exclude ".git"))
  (def fzf-args ["--preview" "head -100 {}"
                 "--preview-window" "right:50%:wrap"
                 "--prompt" "project> "
                 "--height" "100%"])
  (def result (fzf/run-fzf root find-parts fzf-args))
  (when (and result (not= result ""))
    (def edit-cmd (string "evaluate-commands -client " (kak/quote client) " edit " (kak/quote (string root "/" result)) "\n"))
    (fzf/send-to-kak session edit-cmd)))

(defn- expand-home [path]
  (if (string/has-prefix? "~" path)
    (string (os/getenv "HOME" "/home") (string/slice path 1))
    path))

(defn- scan-projects [dirs]
  (def repos @[])
  (each d dirs
    (def dir (expand-home d))
    (with-dyns [:err (fn [&]) :out (fn [&])]
      (try
        (let [p (os/spawn ["find" dir "-maxdepth" "3" "-name" ".git" "-type" "d"] :px {:out :pipe :err :null})]
          (def out (:read (get p :out) :all))
          (:wait p)
          (each line (string/split "\n" out)
            (def trimmed (string/trim line))
            (when (and (not= trimmed "") (string/has-suffix? "/.git" trimmed))
              (array/push repos (string/slice trimmed 0 (- (length trimmed) 5))))))
        ([_] nil))))
  repos)

(defn- switch-project [argv]
  (def session (get argv 0))
  (def client  (get argv 1))
  (def quoted-paths (get argv 2 ""))
  (fzf/launch session client "switch project" :project :switch quoted-paths))

(defn- pick-switch [argv]
  (def session (get argv 0))
  (def client  (get argv 1))
  (def quoted-paths (get argv 2 ""))

  # Parse paths or use default paths
  (def dirs
    (if (and quoted-paths (not= quoted-paths ""))
      (kak/parse-quoted-list quoted-paths)
      ["~/projects" "~/src" "~/work" "~/packages"]))

  # Scan for git repos
  (def repos (scan-projects dirs))

  (when (empty? repos)
    (fzf/send-to-kak session "echo -markup '{Error}No git repositories found'\n")
    (os/exit 0))

  (def list-cmd ["printf" "%s\n" ;repos])
  (def fzf-args ["--prompt" "project> " "--height" "100%"])

  (def result (fzf/run-fzf "." list-cmd fzf-args))
  (when (and result (not= result ""))
    (def change-cmd (string "evaluate-commands -client " (kak/quote client) " change-directory " (kak/quote result) "\n"))
    (fzf/send-to-kak session change-cmd)))

(defn- show-root [argv]
  (def pwd (get argv 0 "."))
  (def root (project-root pwd))
  (print (kak/compile-expr [:echo :markup (string "{Information}project: " root)])))

(defn- kill-buffers [argv]
  (def pwd (get argv 0 "."))
  (def quoted-buflist (get argv 1 ""))
  (def root (project-root pwd))
  (def buflist (kak/parse-quoted-list quoted-buflist))
  (def cmds @[])
  (each buf buflist
    (when (or (= buf root) (string/has-prefix? (string root "/") buf))
      (array/push cmds [:try [:delete-buffer buf]])))
  (print (kak/compile-expr [:block ;cmds])))

(defn- save-buffers [argv]
  (def pwd (get argv 0 "."))
  (def quoted-buflist (get argv 1 ""))
  (def root (project-root pwd))
  (def buflist (kak/parse-quoted-list quoted-buflist))
  (def cmds @[])
  (each buf buflist
    (when (or (= buf root) (string/has-prefix? (string root "/") buf))
      (array/push cmds [:try [:write buf]])))
  (print (kak/compile-expr [:block ;cmds])))

(defn- run-shell [argv]
  (def pwd (get argv 0 "."))
  (def root (project-root pwd))
  (print (kak/compile-expr [:terminal "sh" "-c" (string "cd " (kak/q root) " && exec \"$SHELL\"")])))

(defn dispatch [argv]
  (case (get argv 0)
    "find"         (find-in-project (array/slice argv 1))
    "switch"       (switch-project  (array/slice argv 1))
    "pick-find"    (pick-find       (array/slice argv 1))
    "pick-switch"  (pick-switch     (array/slice argv 1))
    "show-root"    (show-root       (array/slice argv 1))
    "kill-buffers" (kill-buffers    (array/slice argv 1))
    "save-buffers" (save-buffers    (array/slice argv 1))
    "shell"        (run-shell       (array/slice argv 1))
    (do (eprintf "ok --api project: unknown command '%s'\n" (get argv 0 ""))
        (os/exit 1))))

(defn register []
  (string
    "# ── project (SPC-p) ───────────────────────────────────────────────────────────\n"
    (kak/declare-user-mode :project) "\n"
    "declare-option -docstring 'list of paths to search for projects' str-list ok_project_paths\n\n"

    (kak/defcmd-api :ok-project-root "print project root to status line" :project :show-root [:pwd]) "\n"
    (kak/defcmd-api :ok-project-find "find file in project root (fd/find + fzf)" :project :find [:session :client :pwd]) "\n"
    (kak/defcmd-api :ok-project-switch "switch project (fzf over known git repos)" :project :switch [:session :client :quoted_opt_ok_project_paths]) "\n"
    (kak/defcmd-api :ok-project-kill-buffers "kill all buffers in current project" :project :kill-buffers [:pwd :quoted_buflist]) "\n"
    (kak/defcmd-api :ok-project-save-buffers "save all modified buffers in current project" :project :save-buffers [:pwd :quoted_buflist]) "\n"
    (kak/defcmd-api :ok-project-shell "run shell command in project root" :project :shell [:pwd]) "\n"

    (kak/map :global :project "f" ":ok-project-find<ret>" :docstring "find file") "\n"
    (kak/map :global :project "p" ":ok-project-switch<ret>" :docstring "switch project") "\n"
    (kak/map :global :project "r" ":ok-project-root<ret>" :docstring "show project root") "\n"
    (kak/map :global :project "k" ":ok-project-kill-buffers<ret>" :docstring "kill buffers") "\n"
    (kak/map :global :project "s" ":ok-project-save-buffers<ret>" :docstring "save buffers") "\n"
    (kak/map :global :project "!" ":ok-project-shell<ret>" :docstring "shell at root") "\n"

    (kak/map :global :user "p" ":enter-user-mode project<ret>" :docstring "project") "\n"
  ))
