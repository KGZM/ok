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
  Checks for the session socket at $XDG_RUNTIME_DIR/kakoune/<session>."
  [session]
  (let [runtime (or (os/getenv "XDG_RUNTIME_DIR") "/tmp/kak-runtime")
        socket  (string runtime "/kakoune/" session)]
    (not (nil? (os/stat socket)))))
