# Diagnostic script — run with: janet test/debug-clipboard.janet

(defn osc52-payload [raw]
  (when-let [start (string/find "52;c;" raw)
             end   (string/find "\x07" raw (+ start 5))]
    (string/slice raw (+ start 5) end)))

(defn b64decode [s]
  (def tmp (string "/tmp/ok-b64-" (os/time)))
  (os/execute ["sh" "-c" (string "printf '%s' '" s "' | base64 -d > " tmp)] :p)
  (def result (slurp tmp))
  (os/rm tmp)
  result)

(print "--- step 1: basic base64 roundtrip ---")
(def tmp1 "/tmp/ok-diag-1")
(os/execute ["sh" "-c" (string "printf '%s' 'hello world' | base64 | tr -d '\\n' > " tmp1)] :p)
(def enc1 (string/trimr (slurp tmp1)))
(os/rm tmp1)
(print "encoded: " enc1)
(print "decoded: " (b64decode enc1))

(print "\n--- step 2: OSC 52 sequence construction ---")
(def tmp2 "/tmp/ok-diag-2")
(os/execute ["sh" "-c" (string
  "enc=$(printf '%s' 'hello world' | base64 | tr -d '\\n'); "
  "printf '\\033]52;c;%s\\007' \"$enc\" > " tmp2)] :p)
(def raw2 (slurp tmp2))
(print "raw length: " (length raw2))
(print "payload: " (osc52-payload raw2))
(when-let [p (osc52-payload raw2)]
  (print "decoded: " (b64decode p)))

(print "\n--- step 3: eval set with kak-style quoting ---")
(def tmp3 "/tmp/ok-diag-3")
(def kqs "'hello world'")
(os/execute ["sh" "-c" (string
  "eval set -- " kqs "; "
  "printf 'argc: %d\\n' $# >> " tmp3 "; "
  "printf 'arg1: %s\\n' \"$1\" >> " tmp3)] :p)
(print (slurp tmp3))
(os/rm tmp3)

(print "\n--- step 4: full pipeline with kak-style quoting ---")
(def tmp4 "/tmp/ok-diag-4")
(def script (string
  "eval set -- 'hello world'\n"
  "joined=\"\"\n"
  "sep=\"\"\n"
  "while [ $# -gt 0 ]; do\n"
  "    joined=\"${joined}${sep}${1}\"\n"
  "    sep='\n'\n"
  "    shift\n"
  "done\n"
  "encoded=$(printf '%s' \"$joined\" | base64 | tr -d '\\n')\n"
  "printf '\\033]52;c;%s\\007' \"$encoded\" > " tmp4 "\n"))
(os/execute ["sh" "-c" script] :p)
(def raw4 (slurp tmp4))
(print "raw length: " (length raw4))
(print "payload: " (osc52-payload raw4))
(when-let [p (osc52-payload raw4)]
  (print "decoded: " (b64decode p)))
(os/rm tmp4)
