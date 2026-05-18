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
  (os/execute
    ["sh" "-c"
     `
LOG=/tmp/ok-clip.log
printf '\n=== ok clipboard copy ===\n' >> "$LOG"
printf 'kak_quoted_selections: %s\n' "$kak_quoted_selections" >> "$LOG"
printf 'tty: %s\n' "$(ls -la /dev/tty 2>&1)" >> "$LOG"
printf 'tty writable: %s\n' "$(echo x > /dev/tty 2>&1 && echo yes || echo no)" >> "$LOG"

eval set -- "$kak_quoted_selections"
printf 'selection count: %d\n' "$#" >> "$LOG"

joined=""
sep=""
while [ $# -gt 0 ]; do
    joined="${joined}${sep}${1}"
    sep="
"
    shift
done
printf 'joined length: %d\n' "${#joined}" >> "$LOG"

encoded=$(printf '%s' "$joined" | base64 | tr -d '\n')
printf 'encoded: %s\n' "$encoded" >> "$LOG"

printf '\033]52;c;%s\007' "$encoded" > /dev/tty 2>> "$LOG"
printf 'osc52 exit: %d\n' "$?" >> "$LOG"
`]
    :p))

(defn dispatch [argv]
  (case (get argv 0)
    "copy" (copy)
    (do
      (eprintf "ok --api clipboard: unknown command '%s'\n" (get argv 0 ""))
      (os/exit 1))))
