# clipboard — OSC 52 system clipboard integration

(defn register
  "Kak script that wires y/d/c to ok --api clipboard copy.
  Emitted once at startup by ok --api init."
  []
  ``
# ── clipboard ─────────────────────────────────────────────────────────────────
# NormalKey fires before the key acts — selections are exactly what
# y/d/c is about to put into the register.
# eval expands $kak_quoted_selections into proper argv for ok.
hook global NormalKey [ydc] %{
    nop %sh{ eval ok --api clipboard copy "$kak_quoted_selections" }
}
``)

(defn copy
  "Send selections to the system clipboard via OSC 52.
  selections — array of strings from argv (each selection as one element).
  Joined with newlines to match what kak puts in the register."
  [selections]
  (let [joined (string/join selections "\n")]
    # Pass joined text as $1 to avoid shell parsing/quoting issues.
    # printf '%s' "$1" | base64 is safe regardless of content.
    (os/execute
      ["sh" "-c"
       `encoded=$(printf '%s' "$1" | base64 | tr -d '\n')
printf '\033]52;c;%s\007' "$encoded" > /dev/tty`
       "ok"
       joined]
      :p)))

(defn dispatch [argv]
  (case (get argv 0)
    "copy" (copy (array/slice argv 1))
    (do
      (eprintf "ok --api clipboard: unknown command '%s'\n" (get argv 0 ""))
      (os/exit 1))))
