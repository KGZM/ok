# splash — startup screen shown when ok is opened without a file

(def- logo
  ``
     ___________________
           |
           |      /
           |     /
           |    /
           |---<
           |    \
           |     \
           |      \

             overk
  ``)

(defn show
  "Emits kak script to open a *splash* scratch buffer with the logo.
  Called via: -e 'evaluate-commands %sh{ ok --api splash show }'"
  []
  # Escape single quotes in the logo for kak string embedding.
  (def escaped (string/replace-all "'" "\\'" logo))
  (print (string
    "edit -scratch *splash*\n"
    "set-option buffer readonly true\n"
    "set-option buffer filetype scratch\n"
    "execute-keys '%<a-d>'\n"
    "set-register '\"' '" escaped "'\n"
    "execute-keys 'P'\n"
    "execute-keys 'gg'\n")))

(defn dispatch [argv]
  (case (get argv 0)
    "show" (show)
    (do
      (eprintf "ok --api splash: unknown command '%s'\n" (get argv 0 ""))
      (os/exit 1))))
