# Isolate exactly what the test file does

(import ../src/clipboard)

(defn b64decode [s]
  (def tmp (string "/tmp/ok-test-b64-" (os/time)))
  (os/execute ["sh" "-c" (string "printf '%s' '" s "' | base64 -d > " tmp)] :p)
  (def result (slurp tmp))
  (os/rm tmp)
  result)

(defn osc52-payload [raw]
  (when-let [start (string/find "52;c;" raw)
             end   (string/find "\x07" raw (+ start 5))]
    (string/slice raw (+ start 5) end)))

(defn kak-quote [s]
  (string "'" (string/replace-all "'" "'\\''" s) "'"))

(defn run-copy-with-selections [& selections]
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

(def raw (run-copy-with-selections "hello world"))
(def payload (osc52-payload raw))
(print "payload: [" payload "]")
(def decoded (b64decode payload))
(print "decoded: [" decoded "]")
(print "decoded bytes: " (length decoded))
(print "expected bytes: " (length "hello world"))
(print "equal: " (= "hello world" decoded))
