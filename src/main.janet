(import ./session)
(import ./init)

(defn- launch
  "Launch kak, injecting ok itself for wiring and connecting to an
  existing session when the windowing system provides one."
  [args]
  (let [session (session/detect)
        cmd     @["kak"]]
    (when session
      (array/concat cmd ["-C" session]))
    (array/concat cmd ["-E" "evaluate-commands %sh{ ok init }"])
    (array/concat cmd args)
    (os/exit (os/execute cmd :p))))

(defn main [& args]
  # args[0] is the script name (interpreted) or binary name (compiled).
  # The real subcommand is always at args[1].
  (let [argv (array/slice args 1)]
    (case (get argv 0)
      "init" (init/run)
      (launch argv))))
