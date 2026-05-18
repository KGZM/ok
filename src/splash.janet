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

(defn- max-line-width [text]
  (reduce (fn [acc line] (max acc (length line)))
          0
          (string/split "\n" text)))

(defn- center [text width]
  (def logo-width (max-line-width text))
  (def pad (max 0 (div (- width logo-width) 2)))
  (def prefix (string/repeat " " pad))
  (string/join
    (map (fn [line] (string prefix line))
         (string/split "\n" text))
    "\n"))

(defn show
  "Emits kak script to open a *splash* scratch buffer with the centered logo.
  argv[0] is the terminal width passed as %val{window_width} from kak."
  [argv]
  (def width (or (scan-number (get argv 0 "")) 80))
  (def content (center logo width))
  (def escaped (string/replace-all "'" "\\'" content))
  (print (string
    "edit -scratch *splash*\n"
    "set-option buffer filetype scratch\n"
    "execute-keys '%<a-d>'\n"
    "set-register '\"' '" escaped "'\n"
    "execute-keys 'P'\n"
    "execute-keys 'gg'\n"
    "set-option buffer readonly true\n")))

(defn dispatch [argv]
  (case (get argv 0)
    "show" (show (array/slice argv 1))
    (do
      (eprintf "ok --api splash: unknown command '%s'\n" (get argv 0 ""))
      (os/exit 1))))
