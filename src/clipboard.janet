# clipboard — OSC 52 system clipboard integration

(defn register
  "Kak script that wires y/d/c to pipe selections to: ok --api clipboard copy"
  []
  ``
# ── clipboard ─────────────────────────────────────────────────────────────────
# NormalKey fires before the key acts — selections are exactly what
# y/d/c is about to put into the register.
# Selections are joined with newlines (matching the register) and piped
# to ok via stdin.
hook global NormalKey [ydc] %{
    nop %sh{
        eval set -- "$kak_quoted_selections"
        sep=""; text=""
        for s in "$@"; do text="$text$sep$s"; sep="
"; done
        printf '%s' "$text" | ok --api clipboard copy
    }
}
``)

(defn copy
  "Read stdin and send it to the system clipboard via OSC 52.
  Called from kak: ... | ok --api clipboard copy"
  []
  (let [text (string (file/read stdin :all))]
    (os/execute
      ["sh" "-c"
       `encoded=$(printf '%s' "$1" | base64 | tr -d '\n')
printf '\033]52;c;%s\007' "$encoded" > /dev/tty`
       "ok"
       text]
      :p)))

(defn dispatch [argv]
  (case (get argv 0)
    "copy" (copy)
    (do
      (eprintf "ok --api clipboard: unknown command '%s'\n" (get argv 0 ""))
      (os/exit 1))))
