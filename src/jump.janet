# jump — SPC-j: easymotion / avy-style navigation

(import ./kak)
(import ./fzf)

(defn- escape-regex [s]
  (def spec-chars ".[\\^$*+?()|{}]/")
  (def res @[])
  (each c s
    (def char-str (string/from-bytes c))
    (if (string/find char-str spec-chars)
      (do
        (array/push res 92) # backslash
        (array/push res c))
      (array/push res c)))
  (string/from-bytes ;res))

(defn- to-target [argv]
  (def key (get argv 0))
  (def targets (get argv 1))
  (def entries (string/split " " (or targets "")))
  (var found nil)
  (each entry entries
    (def parts (string/split ":" entry))
    (when (and (= (get parts 0) key) (= (length parts) 3))
      (set found parts)))
  (def cmds @[])
  (if found
    (let [[_ line col] found]
      (array/push cmds [:select (string line "." col "," line "." col)]))
    (array/push cmds [:ok-jump-clear]))
  (array/push cmds [:ok-jump-clear])
  (print (kak/compile-expr [:block ;cmds])))

(defn- collect-scope [argv]
  (def cursor-line (get argv 0))
  (def line (scan-number (or cursor-line "1")))
  (def top (if (> line 20) (- line 20) 1))
  (def bot (+ line 20))
  (print (kak/compile-expr [:select (string top ".1," bot ".9999")])))

(defn- collect-search [argv]
  (def pattern (get argv 0))
  (def escaped (escape-regex (or pattern "")))
  (print (kak/compile-expr [:execute-keys (string "s" escaped "<ret>")])))

(defn- collect-process [argv]
  (def timestamp (get argv 0))
  (def selections-desc (get argv 1))
  (def descs (string/split ":" (or selections-desc "")))
  (def ranges @[timestamp])
  (def targets @[])
  (var i 1)
  (each desc descs
    (when (> i 9) (break))
    (def start (first (string/split "," desc)))
    (when (and start (string/find "." start))
      (def parts (string/split "." start))
      (def r (get parts 0))
      (def c (get parts 1))
      (array/push ranges (string r "." c "," r "." c "|{DiagnosticWarning}" i))
      (array/push targets (string i ":" r ":" c))
      (set i (+ i 1))))
  (def ranges-str (string/join ranges " "))
  (def targets-str (string/join targets " "))
  (def cmds
    [[:set-option :window :ok_jump_overlay ranges-str]
     [:set-option :window :ok_jump_targets targets-str]
     [:echo :markup (string "{Information}jump: [1-" (- i 1) "] to pick, <esc> cancel")]])
  (print (kak/compile-expr [:block ;cmds])))

(defn- handle-key [argv]
  (def key (get argv 0))
  (if (and (>= (compare key "1") 0) (<= (compare key "9") 0))
    (print (kak/compile-expr [:ok-jump-to-n]))
    (print (kak/compile-expr [:ok-jump-clear]))))

(defn- jump-line [argv]
  (def session (get argv 0))
  (def client  (get argv 1))
  (def buffile (get argv 2 ""))

  (when (= buffile "")
    (print "fail 'ok-jump-line: no file (scratch buffers not supported)'")
    (os/exit 0))

  (fzf/launch session client "jump to line" :jump :line buffile))

(defn- pick-line [argv]
  (def session (get argv 0))
  (def client  (get argv 1))
  (def buffile (get argv 2 ""))

  (def list-cmd ["grep" "-n" "" buffile])
  (def fzf-args ["--delimiter" ":"
                 "--nth" "2.."
                 "--preview" (string "line={1}; start=$((line - 15)); [ $start -lt 1 ] && start=1; sed -n \"$start,+30p\" " (fzf/sh-quote buffile))
                 "--preview-window" "right:50%:wrap"
                 "--prompt" "jump> "
                 "--height" "100%"])

  (def result (fzf/run-fzf "." list-cmd fzf-args))
  (when (and result (not= result ""))
    (def line (first (string/split ":" result)))
    (when (and line (not= line ""))
      (def goto-cmd (string "evaluate-commands -client " (kak/quote client) " execute-keys " (kak/quote (string line "g")) "\n"))
      (fzf/send-to-kak session goto-cmd))))

(defn dispatch [argv]
  (case (get argv 0)
    "to-target"       (to-target       (array/slice argv 1))
    "collect-scope"   (collect-scope   (array/slice argv 1))
    "collect-search"  (collect-search  (array/slice argv 1))
    "collect-process" (collect-process (array/slice argv 1))
    "handle-key"      (handle-key      (array/slice argv 1))
    "line"            (jump-line       (array/slice argv 1))
    "pick-line"       (pick-line       (array/slice argv 1))
    (do (eprintf "ok --api jump: unknown command '%s'\n" (get argv 0 ""))
        (os/exit 1))))

(defn register []
  (string
    "# ── jump / easymotion (SPC-j) ─────────────────────────────────────────────────\n"
    (kak/declare-user-mode :jump) "\n"

    "declare-option -hidden range-specs ok_jump_overlay\n"
    "declare-option -hidden str         ok_jump_targets\n\n"

    (kak/compile-expr
      [:define-command :ok-jump-clear :hidden
       [:block
        [:try [:remove-highlighter "window/ok-jump"]]
        [:set-option :window :ok_jump_overlay "%val{timestamp}"]
        [:set-option :window :ok_jump_targets ""]]]) "\n"

    (kak/defcmd-api :ok-jump-to-n "jump to specific target" :jump :to-target [:key :opt_ok_jump_targets]) "\n"

    (kak/compile-expr
      [:define-command :ok-jump-collect :hidden :params 1
       [:block
        [:ok-jump-clear]
        [:evaluate-commands :draft
         [:block
          [:evaluate-commands [:sh (kak/api-cmd :jump :collect-scope :cursor_line)]]
          [:evaluate-commands [:sh (kak/api-cmd :jump :collect-search "$1")]]
          [:evaluate-commands [:sh (kak/api-cmd :jump :collect-process :timestamp :selections_desc)]]]]
        [:add-highlighter "window/ok-jump" :replace-ranges :ok_jump_overlay]]]) "\n"

    (kak/compile-expr
      [:define-command :ok-jump-char :docstring "easymotion: highlight visible occurrences of char, [1-9] to jump"
       [:block
        [:on-key
         [:evaluate-commands
          [:block
           [:ok-jump-collect "%val{key}"]
           [:on-key
            [:evaluate-commands [:sh (kak/api-cmd :jump :handle-key :key)]]]]]]]]) "\n"

    (kak/compile-expr
      [:define-command :ok-jump-word :docstring "easymotion: highlight visible word starts, [1-9] to jump"
       [:block
        [:ok-jump-collect "\\b\\w"]
        [:on-key
         [:evaluate-commands [:sh (kak/api-cmd :jump :handle-key :key)]]]]]) "\n"

    (kak/defcmd-api :ok-jump-line "jump to line (fzf swiper)" :jump :line [:session :client :buffile]) "\n"

    (kak/map :global :jump "c" ":ok-jump-char<ret>" :docstring "jump to char [easymotion, 1-9]") "\n"
    (kak/map :global :jump "w" ":ok-jump-word<ret>" :docstring "jump to word [easymotion, 1-9]") "\n"
    (kak/map :global :jump "l" ":ok-jump-line<ret>" :docstring "jump to line [fzf]") "\n"

    (kak/map :global :user "j" ":enter-user-mode jump<ret>" :docstring "jump") "\n"
  ))
