# search — SPC-s: search commands

(import ./kak)
(import ./env)
(import ./fzf)

(defn- search-buffer [argv]
  (def session     (get argv 0))
  (def client      (get argv 1))
  (def buffile     (get argv 2 ""))
  (def cursor-line (get argv 3 "1"))

  (when (= buffile "")
    (print "fail 'ok-search-buffer: no file (scratch buffers not supported)'")
    (os/exit 0))

  (fzf/launch session client "searching buffer" :search :buffer buffile cursor-line))

(defn- pick-buffer [argv]
  (def session     (get argv 0))
  (def client      (get argv 1))
  (def buffile     (get argv 2 ""))
  (def cursor-line (get argv 3 "1"))

  (def list-cmd ["grep" "-n" "" buffile])
  (def fzf-args ["--delimiter" ":"
                 "--nth" "2.."
                 "--preview" (string "line={1}; start=$((line - 15)); [ $start -lt 1 ] && start=1; sed -n \"$start,+30p\" " (fzf/sh-quote buffile))
                 "--preview-window" "right:50%:wrap"
                 "--prompt" "line> "
                 "--query" ""
                 "--height" "100%"])
  (def result (fzf/run-fzf "." list-cmd fzf-args))
  (when (and result (not= result ""))
    (def line (first (string/split ":" result)))
    (when (and line (not= line ""))
      (def goto-cmd (string "evaluate-commands -client " (kak/quote client) " execute-keys " (kak/quote (string line "g")) "\n"))
      (fzf/send-to-kak session goto-cmd))))

(defn- search-project [argv]
  (def session (get argv 0))
  (def client  (get argv 1))
  (def dir     (get argv 2 "."))
  (def query   (get argv 3 ""))
  (fzf/launch session client "searching project" :search :project dir query))

(defn- pick-project [argv]
  (def session (get argv 0))
  (def client  (get argv 1))
  (def dir     (get argv 2 "."))
  (def query   (get argv 3 ""))

  (def has-rg (env/bin-exists? "rg"))
  (def list-cmd
    (if has-rg
      ["rg" "--line-number" "--color=always" "--smart-case" ""]
      ["grep" "-rnH" "--exclude-dir=.git" "" "."]))

  (def fzf-args ["--ansi"
                 "--delimiter" ":"
                 "--nth" "1,3.."
                 "--preview" "line={2}; start=$((line - 15)); [ $start -lt 1 ] && start=1; sed -n \"$start,+30p\" \"{1}\""
                 "--preview-window" "right:50%:wrap"
                 "--prompt" "project> "
                 "--query" query
                 "--height" "100%"])

  (def result (fzf/run-fzf dir list-cmd fzf-args))
  (when (and result (not= result ""))
    (def parts (string/split ":" result))
    (when (>= (length parts) 2)
      (def file (get parts 0))
      (def line (get parts 1))
      (def edit-cmd (string "evaluate-commands -client " (kak/quote client) " %{edit " (kak/quote file) "; execute-keys " (kak/quote (string line "g")) "}\n"))
      (fzf/send-to-kak session edit-cmd))))

(defn dispatch [argv]
  (case (get argv 0)
    "buffer"       (search-buffer  (array/slice argv 1))
    "project"      (search-project (array/slice argv 1))
    "pick-buffer"  (pick-buffer    (array/slice argv 1))
    "pick-project" (pick-project   (array/slice argv 1))
    (do (eprintf "ok --api search: unknown command '%s'\n" (get argv 0 ""))
        (os/exit 1))))

(defn register []
  (string
    "# ── search (SPC-s) ────────────────────────────────────────────────────────────\n"
    (kak/declare-user-mode :search) "\n"

    (kak/defcmd-api "ok-search-buffer" "search buffer lines with fzf, jump to selection" :search :buffer [:session :client :buffile :cursor-line]) "\n"
    (kak/defcmd-api "ok-search-project" "search project with ripgrep + fzf" :search :project [:session :client :pwd]) "\n"
    (kak/defcmd-api "ok-search-word" "search project for word under cursor" :search :project [:session :client :pwd :selection]) "\n"
    (kak/defcmd-api "ok-search-dir" "search current directory with ripgrep + fzf" :search :project [:session :client :pwd]) "\n"

    (kak/map :global :search "s" ":ok-search-buffer<ret>" :docstring "search buffer") "\n"
    (kak/map :global :search "S" ":ok-search-word<ret>" :docstring "search buffer for word") "\n"
    (kak/map :global :search "p" ":ok-search-project<ret>" :docstring "search project") "\n"
    (kak/map :global :search "d" ":ok-search-dir<ret>" :docstring "search directory") "\n"
    (kak/map :global :search "w" ":ok-search-word<ret>" :docstring "search word at point") "\n"
    (kak/map :global :search "n" ":execute-keys //<ret>" :docstring "search forward") "\n"
    (kak/map :global :search "N" ":execute-keys <lt>a-/><lt>a-/><ret>" :docstring "search backward") "\n"

    (kak/map :global :user "s" ":enter-user-mode search<ret>" :docstring "search") "\n"
    (kak/map :global :user "/" ":ok-search-project<ret>" :docstring "search project") "\n"
    (kak/map :global :user "*" ":ok-search-word<ret>" :docstring "search word at point") "\n"
  ))
