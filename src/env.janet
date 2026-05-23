# src/env.janet — Tool detection and command fallbacks

# Var/Function to check if a binary exists
(var bin-exists? (fn [name]
  (= 0 (os/execute ["sh" "-c" (string "command -v " name " >/dev/null 2>&1")] :p))))

# Var/Function to get the environment variables
(var environ (fn [] (os/environ)))

(defn file-find-cmd [&keys {:hidden hidden :exclude exclude}]
  "Returns file finding command."
  (if (bin-exists? "fd")
    (do
      (def cmd @["fd" "--type" "f" "--color=never"])
      (if hidden (array/push cmd "--hidden"))
      (if exclude
        (if (indexed? exclude)
          (each x exclude (array/push cmd "--exclude" x))
          (array/push cmd "--exclude" exclude)))
      cmd)
    (do
      (def cmd @["find" "."])
      (unless hidden
        (array/concat cmd ["-not" "-path" "*/.*"]))
      (array/concat cmd ["-type" "f"])
      cmd)))

(defn grep-cmd [pattern &keys {:path path}]
  "Returns grep command."
  (if (bin-exists? "rg")
    (let [cmd @["rg" "--column" "--line-number" "--no-heading" "--color=never" "--smart-case"]]
      (array/push cmd pattern)
      (if path (array/push cmd path))
      cmd)
    (let [cmd @["grep" "-rnH" "--exclude-dir=.git"]]
      (array/push cmd pattern)
      (array/push cmd (or path "."))
      cmd)))

(defn preview-cmd [file]
  "Returns file preview command."
  (if (bin-exists? "bat")
    ["bat" "--style=plain" "--color=always" file]
    ["cat" file]))

(defn open-pane-cmd [cmd-args &keys {:direction direction}]
  "Returns command to run in new pane/split."
  (def env-map (environ))
  (cond
    (or (get env-map "ZELLIJ") (get env-map "ZELLIJ_SESSION_NAME"))
    (let [dir-arg (if (= direction :right) "right" "down")]
      ["zellij" "run" "-d" dir-arg "--" ;cmd-args])

    (get env-map "TMUX")
    (let [dir-flag (if (= direction :right) "-h" "-v")]
      ["tmux" "split-window" dir-flag ;cmd-args])

    (and (get env-map "DISPLAY") (not (empty? (get env-map "DISPLAY"))))
    (let [env-term (get env-map "TERM" "")
          term (cond
                 (string/find "alacritty" env-term) "alacritty"
                 (string/find "kitty" env-term) "kitty"
                 (string/find "wezterm" env-term) "wezterm"
                 (string/find "gnome-terminal" env-term) "gnome-terminal"
                 (string/find "xterm" env-term) "xterm"
                 "xterm")]
      [term "-e" ;cmd-args])

    cmd-args))
