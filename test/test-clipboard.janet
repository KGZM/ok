(import ../src/clipboard)

# ── clipboard/register ────────────────────────────────────────────────────────

(def reg (clipboard/register))

(assert (string/find "NormalKey" reg)
        "register: contains NormalKey hook")
(assert (string/find "[ydc]" reg)
        "register: hooks y, d, and c")
(assert (string/find "ok --api clipboard copy" reg)
        "register: calls ok --api clipboard copy")

(print "clipboard/register: OK")

# ── helpers ───────────────────────────────────────────────────────────────────

(defn b64decode [s]
  (def tmp (string "/tmp/ok-test-b64-" (os/time)))
  (os/execute ["sh" "-c" (string "printf '%s' '" s "' | base64 -d > " tmp)] :p)
  (def result (string (slurp tmp)))
  (os/rm tmp)
  result)

(defn osc52-payload [raw]
  # Extract base64 payload from ESC]52;c;<payload>BEL
  (when-let [start (string/find "52;c;" raw)
             end   (string/find "\x07" raw (+ start 5))]
    (string/slice raw (+ start 5) end)))

(defn kak-quote [s]
  # Produce a shell-quoted word as kak would: wrap in single quotes,
  # escaping any embedded single quotes.
  (string "'" (string/replace-all "'" "'\\''" s) "'"))

(defn run-copy-with-selections [& selections]
  # Simulate kak_quoted_selections: a space-joined list of shell-quoted words.
  # Set it as an env var so eval inside the script re-parses it correctly —
  # the same mechanism kak uses. Do NOT inline the quotes into the script.
  (def kqs (string/join (map kak-quote selections) " "))
  (def tmp (string "/tmp/ok-test-osc52-" (os/time)))
  (def env (merge (os/environ) {"kak_quoted_selections" kqs}))
  (os/execute ["sh" "-c"
    (string
      "eval set -- \"$kak_quoted_selections\"\n"
      "joined=\"\"\n"
      "sep=\"\"\n"
      "while [ $# -gt 0 ]; do\n"
      "    joined=\"${joined}${sep}${1}\"\n"
      "    sep='\n'\n"
      "    shift\n"
      "done\n"
      "encoded=$(printf '%s' \"$joined\" | base64 | tr -d '\\n')\n"
      "printf '\\033]52;c;%s\\007' \"$encoded\" > " tmp "\n")]
    :pe env)
  (def raw (slurp tmp))
  (os/rm tmp)
  raw)

# ── tests ─────────────────────────────────────────────────────────────────────

(let [raw (run-copy-with-selections "hello world")
      payload (osc52-payload raw)]
  (assert payload "single selection: OSC 52 sequence present")
  (assert (= "hello world" (b64decode payload))
          "single selection: decoded payload matches"))
(print "clipboard/copy single selection: OK")

(let [raw (run-copy-with-selections "foo" "bar" "baz")
      payload (osc52-payload raw)]
  (assert payload "multi selection: OSC 52 sequence present")
  (assert (= "foo\nbar\nbaz" (b64decode payload))
          "multi selection: all selections joined with newlines"))
(print "clipboard/copy multiple selections: OK")

(let [raw (run-copy-with-selections "it's a test")
      payload (osc52-payload raw)]
  (assert payload "quoted selection: OSC 52 sequence present")
  (assert (= "it's a test" (b64decode payload))
          "quoted selection: single quotes survive shell quoting"))
(print "clipboard/copy quoted selection: OK")

(print "\nAll clipboard tests passed.")
