(import ./session)
(import ./init)
(import ./clipboard)
(import ./splash)

# ── --api dispatch ────────────────────────────────────────────────────────────
# Kak-facing API. Called from kak %sh{} blocks, never by users.
# ok --api init
# ok --api <module> <cmd> [args...]

(defn- api-dispatch [argv]
  (case (get argv 0)
    "init"      (init/run (array/slice argv 1))
    "clipboard" (clipboard/dispatch (array/slice argv 1))
    "splash"    (splash/dispatch (array/slice argv 1))
    (do
      (eprintf "ok --api: unknown module '%s'\n" (get argv 0 ""))
      (os/exit 1))))

# ── --ipc dispatch ────────────────────────────────────────────────────────────
# Socket-based IPC from kak to ok daemon. Separate namespace from --api.
# ok --ipc <cmd> [args...]
# Not yet implemented — placeholder for future bidirectional communication.

(defn- ipc-dispatch [argv]
  (eprintf "ok --ipc: not yet implemented\n")
  (os/exit 1))

# ── launcher ──────────────────────────────────────────────────────────────────
# ok [files] [kak-flags]
#
# Detects windowing session, injects ok --api init into kak startup,
# passes all remaining args straight through to kak.
# -s <name> in user args wins over session detection.

(defn- flag-value [argv flag]
  # Returns the value after flag in argv, e.g. ["-s" "work"] -> "work"
  (var result nil)
  (forv i 0 (- (length argv) 1)
    (when (= (get argv i) flag)
      (set result (get argv (+ i 1)))))
  result)

(defn- file-args? [argv]
  # Returns true if argv contains any element that isn't a flag or flag value.
  # A file arg is anything not starting with -, accounting for flags that
  # consume the next element (-s -c -C -e -E -p -f -i -ui -debug).
  (def flag-with-value {"-s" true "-c" true "-C" true "-e" true "-E" true
                        "-p" true "-f" true "-i" true "-ui" true "-debug" true})
  (var skip false)
  (var found false)
  (each a argv
    (cond
      skip          (set skip false)
      (flag-with-value a) (set skip true)
      (string/has-prefix? "-" a) nil
      (set found true)))
  found)

(defn- launch [argv]
  (let [explicit (flag-value argv "-s")
        detected (when (nil? explicit) (session/detect))
        session  (or explicit detected)
        new?     (or (nil? session) (not (session/exists? session)))
        cmd      @["kak"]]
    (when (and session (nil? explicit))
      (array/concat cmd ["-C" session]))
    (when new?
      # %val{session} is expanded by kak before the shell runs — unlike
      # $kak_session which is not set in %sh{} during -E server initialisation.
      (array/concat cmd ["-E" "evaluate-commands %sh{ ok --api init %val{session} }"]))
    # Show splash on client init when no files were given.
    (when (not (file-args? argv))
      # Pass both window width and session name — $kak_session is available
      # during -e (client init) unlike -E, but %val{} expansion is cleaner.
      (array/concat cmd ["-e" "evaluate-commands %sh{ ok --api splash show %val{window_width} %val{session} }"]))
    (array/concat cmd argv)
    (os/exit (os/execute cmd :p))))

# ── entrypoint ────────────────────────────────────────────────────────────────

(defn main [& args]
  # args[0] is script/binary name — skip it.
  (let [argv (array/slice args 1)]
    (case (get argv 0)
      "--api" (api-dispatch (array/slice argv 1))
      "--ipc" (ipc-dispatch (array/slice argv 1))
      (launch argv))))
