(import ./session)
(import ./init)

# ── API dispatch ──────────────────────────────────────────────────────────────
# Called from within kak via %sh{} blocks — not user-facing.
# ok --api <cmd> [args...]

(defn- api-dispatch [argv]
  (case (get argv 0)
    "init" (init/run)
    (do
      (eprintf "ok --api: unknown command '%s'" (get argv 0 ""))
      (os/exit 1))))

# ── launcher ──────────────────────────────────────────────────────────────────
# ok [files] [kak-flags]
#
# Detects windowing session, injects ok --api init into kak startup,
# passes all remaining args straight through to kak.
#
# -s <name> in user args wins over session detection — explicit beats implicit.

(defn- has-flag? [argv flag]
  (var found false)
  (each a argv (when (= a flag) (set found true)))
  found)

(defn- launch [argv]
  (let [session (if (has-flag? argv "-s")
                  nil                  # user explicitly named a session
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
    (if (= (get argv 0) "--api")
      (api-dispatch (array/slice argv 1))
      (launch argv))))
