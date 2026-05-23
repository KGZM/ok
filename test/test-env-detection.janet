(import ../src/env)

# Helper to check if a command contains a word/arguments, supporting both string and indexed (array/tuple) commands
(defn- contains-word? [cmd word]
  (cond
    (indexed? cmd) (not (nil? (find |(= $ word) cmd)))
    (string? cmd)  (not (nil? (string/find word cmd)))
    (error "Expected string or indexed collection for command")))

# ── Binary detection & Fallbacks ──────────────────────────────────────────────

(print "Testing binary existence checks...")
# Setup custom mock functions for testing, assuming they are defined as vars
(var original-bin-exists? env/bin-exists?)

(defer (set env/bin-exists? original-bin-exists?)
  # Case 1: binaries are present
  (set env/bin-exists? (fn [name]
                         (case name
                           "fd" true
                           "rg" true
                           "bat" true
                           false)))

  (assert (env/bin-exists? "fd") "mock fd present")
  (assert (env/bin-exists? "rg") "mock rg present")
  (assert (env/bin-exists? "bat") "mock bat present")

  (let [find-cmd (env/file-find-cmd)
        grep-cmd (env/grep-cmd "my-pattern")
        prev-cmd (env/preview-cmd "file.txt")]
    (assert (contains-word? find-cmd "fd") "uses fd when present")
    (assert (contains-word? grep-cmd "rg") "uses rg when present")
    (assert (contains-word? grep-cmd "my-pattern") "grep-cmd contains pattern")
    (assert (contains-word? prev-cmd "bat") "uses bat when present")
    (assert (contains-word? prev-cmd "file.txt") "preview-cmd contains file name"))

  # Case 2: binaries are absent
  (set env/bin-exists? (fn [name] false))

  (assert (not (env/bin-exists? "fd")) "mock fd absent")
  (assert (not (env/bin-exists? "rg")) "mock rg absent")
  (assert (not (env/bin-exists? "bat")) "mock bat absent")

  (let [find-cmd (env/file-find-cmd)
        grep-cmd (env/grep-cmd "my-pattern")
        prev-cmd (env/preview-cmd "file.txt")]
    (assert (contains-word? find-cmd "find") "falls back to find when fd absent")
    (assert (contains-word? grep-cmd "grep") "falls back to grep when rg absent")
    (assert (contains-word? grep-cmd "my-pattern") "fallback grep-cmd contains pattern")
    (assert (or (contains-word? prev-cmd "cat")
                (contains-word? prev-cmd "less")) "falls back to cat/less when bat absent")
    (assert (contains-word? prev-cmd "file.txt") "fallback preview-cmd contains file name")))

# ── Window/Pane command generation under different multiplexers ───────────────

(print "Testing windowing / pane command generation...")
(var original-environ env/environ)

(defer (set env/environ original-environ)
  # Case 1: Zellij active
  (set env/environ (fn [] @{"ZELLIJ" "1" "ZELLIJ_SESSION_NAME" "my-session"}))
  (let [cmd (env/open-pane-cmd ["ok" "--api" "foo"])]
    (assert (contains-word? cmd "zellij") "Zellij: command contains zellij")
    (assert (contains-word? cmd "foo") "Zellij: command contains target command"))

  # Case 2: Tmux active
  (set env/environ (fn [] @{"TMUX" "/tmp/tmux-1000/default,1234,0"}))
  (let [cmd (env/open-pane-cmd ["ok" "--api" "foo"])]
    (assert (contains-word? cmd "tmux") "Tmux: command contains tmux")
    (assert (contains-word? cmd "foo") "Tmux: command contains target command"))

  # Case 3: Default GUI Terminal active (neither Zellij nor Tmux)
  (set env/environ (fn [] @{"DISPLAY" ":0" "TERM" "alacritty"}))
  (let [cmd (env/open-pane-cmd ["ok" "--api" "foo"])]
    # It should fall back to a terminal emulator, or a default terminal shell command.
    (assert (or (contains-word? cmd "alacritty")
                (contains-word? cmd "kitty")
                (contains-word? cmd "wezterm")
                (contains-word? cmd "xterm")
                (contains-word? cmd "gnome-terminal")
                (contains-word? cmd "term")
                (contains-word? cmd "sh"))
            "Default GUI: launches a terminal emulator or shell fallback")
    (assert (contains-word? cmd "foo") "Default GUI: command contains target command"))

  # Case 4: Headless environment (no multiplexer, no GUI display)
  (set env/environ (fn [] @{}))
  (let [cmd (env/open-pane-cmd ["ok" "--api" "foo"])]
    (assert (not (nil? cmd)) "Headless: returns a fallback command or execute in-place")
    (assert (contains-word? cmd "foo") "Headless: command contains target command")))

(print "\nAll env detection tests passed.")
