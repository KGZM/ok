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
  (case (get args 0)
    "init" (init/run)
    (launch (array/slice args 0))))
