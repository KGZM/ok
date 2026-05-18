(import ../src/clipboard)

# ── clipboard/register ────────────────────────────────────────────────────────

(def reg (clipboard/register))

(assert (string/find "NormalKey" reg)               "register: NormalKey hook present")
(assert (string/find "[ydc]" reg)                   "register: hooks y, d, and c")
(assert (string/find "ok --api clipboard copy" reg) "register: calls ok --api clipboard copy")
(assert (string/find "printf '%s' \"$text\"" reg)   "register: pipes via stdin (printf to ok)")
(print "clipboard/register: OK")

# ── OSC 52 encoding pipeline ──────────────────────────────────────────────────
# Tests the shell encoding logic independently of stdin/tty.
# copy reads stdin → same pipeline → /dev/tty. The encoding is what matters.

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

(defn encode-osc52 [text]
  # Run the same pipeline as copy but capture output instead of writing to tty.
  (def tmp (string "/tmp/ok-test-osc52-" (os/time)))
  (os/execute
    ["sh" "-c"
     (string
       "encoded=$(printf '%s' \"$1\" | base64 | tr -d '\\n')\n"
       "printf '\\033]52;c;%s\\007' \"$encoded\" > " tmp)
     "ok" text]
    :p)
  (def raw (string (slurp tmp)))
  (os/rm tmp)
  raw)

# Single selection
(let [raw (encode-osc52 "hello world")
      p   (osc52-payload raw)]
  (assert p                               "single: OSC 52 sequence present")
  (assert (= "hello world" (b64decode p)) "single: payload decodes correctly"))
(print "OSC 52 single selection: OK")

# Multiple selections joined with newlines (as the kak hook does)
(let [raw (encode-osc52 "foo\nbar\nbaz")
      p   (osc52-payload raw)]
  (assert p                                   "multi: OSC 52 sequence present")
  (assert (= "foo\nbar\nbaz" (b64decode p))    "multi: newline-joined selections preserved"))
(print "OSC 52 multiple selections: OK")

# Single quotes in content
(let [raw (encode-osc52 "it's a test")
      p   (osc52-payload raw)]
  (assert p                                 "quoted: OSC 52 sequence present")
  (assert (= "it's a test" (b64decode p))   "quoted: single quotes preserved"))
(print "OSC 52 quoted content: OK")

# ── copy reads stdin ──────────────────────────────────────────────────────────
# Smoke test: pipe text to ok --api clipboard copy and confirm it exits 0.
# (Can't check tty output in a test environment — encoding is tested above.)

(def ok-bin (string (os/cwd) "/ok"))
(when (os/stat ok-bin)
  (def exit-code
    (os/execute
      ["sh" "-c" (string "printf '%s' 'hello' | " ok-bin " --api clipboard copy 2>/dev/null")]
      :p))
  (assert (= 0 exit-code) "copy: exits 0 when called with piped stdin"))
(print "clipboard/copy stdin: OK")

(print "\nAll clipboard tests passed.")
