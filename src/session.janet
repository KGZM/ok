(defn detect
  "Returns a kak session name derived from the current windowing context,
  or nil if no multiplexer is detected.

  Session names are namespaced with 'overk-' to avoid colliding with
  manually created kak sessions.

  Supported (in detection order):
    zellij  — $ZELLIJ_SESSION_NAME"
  []
  (if-let [name (os/getenv "ZELLIJ_SESSION_NAME")]
    (string "overk-" name)))

(defn exists?
  "Returns true if a kak session with the given name is currently running.
  Uses `kak -l` so the kak wrapper resolves XDG_RUNTIME_DIR consistently —
  avoids mismatches when the wrapper uses a fallback tmpdir that differs
  from the caller's environment."
  [session]
  (def buf @"")
  (def proc (os/spawn ["kak" "-l"] :p {:out :pipe :err :pipe}))
  (ev/read (proc :out) 4096 buf)
  (:wait proc)
  (var found false)
  (each line (string/split "\n" (string/trimr (string buf)))
    (when (= line session) (set found true)))
  found)
