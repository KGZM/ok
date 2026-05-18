(import ./session)
(import ./init)
(import ./clipboard)

# ── --api dispatch ────────────────────────────────────────────────────────────
# Kak-facing API. Called from kak %sh{} blocks, never by users.
# ok --api init
# ok --api <module> <cmd> [args...]

(defn- api-dispatch [argv]
  (case (get argv 0)
    "init"      (init/run)
    "clipboard" (clipboard/dispatch (array/slice argv 1))
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

(defn- has-flag? [argv flag]
  (var found false)
  (each a argv (when (= a flag) (set found true)))
  found)

(defn- launch [argv]
  (let [session (if (has-flag? argv "-s")
                  nil
                  (session/detect))
        cmd @["kak"]]
    (when session
      (array/concat cmd ["-C" session]))
    (array/concat cmd ["-E" "evaluate-commands %sh{ ok --api init }"])
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
