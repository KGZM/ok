# clipboard — OSC 52 system clipboard integration
#
# register: returns kak script wiring y/d/c to ok --api clipboard copy
# copy:     reads kak selections from environment, sends via OSC 52
#
# OSC 52 works through zellij, kitty, wezterm, and over SSH —
# no xclip or wl-clipboard required on the host.

(defn register
  "Kak script fragment that wires this module into the editor.
  Emitted once at startup by ok --api init."
  []
  ``
# ── clipboard ─────────────────────────────────────────────────────────────────
# NormalKey fires before the key acts — selections are exactly what
# y/d/c is about to put into the register.
hook global NormalKey [ydc] %{
    nop %sh{ ok --api clipboard copy }
}
``)

(defn copy
  "Send all current kak selections to the system clipboard via OSC 52.
  Called from kak: nop %sh{ ok --api clipboard copy }
  Reads $kak_quoted_selections from the environment (set by kak in %sh{})."
  []
  # $kak_quoted_selections is shell-quoted by kak — use a sh subprocess to
  # safely parse it (handles selections containing spaces, newlines, quotes).
  # Join all selections with newlines, matching what kak puts in the register.
  (os/execute
    ["sh" "-c"
     ```
eval set -- $kak_quoted_selections
joined=""
sep=""
while [ $# -gt 0 ]; do
    joined="${joined}${sep}${1}"
    sep="
"
    shift
done
encoded=$(printf '%s' "$joined" | base64 | tr -d '\n')
printf '\033]52;c;%s\007' "$encoded" > /dev/tty
```]
    :p))

(defn dispatch [argv]
  (case (get argv 0)
    "copy" (copy)
    (do
      (eprintf "ok --api clipboard: unknown command '%s'\n" (get argv 0 ""))
      (os/exit 1))))
