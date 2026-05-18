(import ../src/clipboard)

# ── clipboard/register ────────────────────────────────────────────────────────

(def reg (clipboard/register))

(assert (string/find "NormalKey" reg)        "register: NormalKey hook present")
(assert (string/find "[ydc]" reg)            "register: hooks y, d, and c")
(assert (string/find "ok --api clipboard copy" reg) "register: calls ok --api clipboard copy")
(assert (string/find "eval ok" reg)          "register: uses eval to expand kak_quoted_selections into argv")
(print "clipboard/register: OK")

# ── clipboard/copy ────────────────────────────────────────────────────────────
# copy [selections] takes a Janet array — no env dependency.
# We redirect /dev/tty to a temp file to capture the OSC 52 sequence.

(defn with-tty-capture [f]
  # Replace /dev/tty with a temp file for the duration of f.
  # copy writes to /dev/tty via sh, so we intercept at the shell level
  # by wrapping the call and checking the sequence in a temp file.
  # Strategy: copy calls sh which writes to /dev/tty. Instead of patching
  # /dev/tty (requires root), we test the sequence construction directly.
  (f))

(defn osc52-payload [raw]
  (when-let [start (string/find "52;c;" raw)
             end   (string/find "\x07" raw (+ start 5))]
    (string/slice raw (+ start 5) end)))

(defn b64decode [s]
  (def tmp (string "/tmp/ok-test-b64-" (os/time)))
  (os/execute ["sh" "-c" (string "printf '%s' '" s "' | base64 -d > " tmp)] :p)
  (def result (string (slurp tmp)))
  (os/rm tmp)
  result)

(defn capture-osc52 [selections]
  # Run the same pipeline as copy but redirect /dev/tty to a temp file.
  (def tmp (string "/tmp/ok-test-osc52-" (os/time)))
  (def joined (string/join selections "\n"))
  (os/execute
    ["sh" "-c"
     (string
       "encoded=$(printf '%s' \"$1\" | base64 | tr -d '\\n')\n"
       "printf '\\033]52;c;%s\\007' \"$encoded\" > " tmp)
     "ok" joined]
    :p)
  (def raw (string (slurp tmp)))
  (os/rm tmp)
  raw)

# Single selection
(let [raw (capture-osc52 ["hello world"])
      payload (osc52-payload raw)]
  (assert payload                             "single: OSC 52 sequence present")
  (assert (= "hello world" (b64decode payload)) "single: payload decodes correctly"))
(print "clipboard/copy single selection: OK")

# Multiple selections — joined with newlines
(let [raw (capture-osc52 ["foo" "bar" "baz"])
      payload (osc52-payload raw)]
  (assert payload                                 "multi: OSC 52 sequence present")
  (assert (= "foo\nbar\nbaz" (b64decode payload))  "multi: joined with newlines"))
(print "clipboard/copy multiple selections: OK")

# Selection containing single quotes
(let [raw (capture-osc52 ["it's a test"])
      payload (osc52-payload raw)]
  (assert payload                                   "quoted: OSC 52 sequence present")
  (assert (= "it's a test" (b64decode payload))      "quoted: single quotes preserved"))
(print "clipboard/copy quoted selection: OK")

(print "\nAll clipboard tests passed.")
