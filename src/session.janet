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
