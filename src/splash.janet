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

# ── metrics ───────────────────────────────────────────────────────────────────

(defn- kts-running? []
  # kak-tree-sitter creates a single socket at $XDG_RUNTIME_DIR/kak-tree-sitter/socket.
  # Checking this is more reliable than pgrep (process name varies after daemonize).
  (let [runtime (or (os/getenv "XDG_RUNTIME_DIR") "/tmp/kak-runtime")
        socket  (string runtime "/kak-tree-sitter/socket")]
    (not (nil? (os/stat socket)))))

(defn- proc-running? [pattern]
  (= 0 (os/execute ["sh" "-c" (string "pgrep -f '" pattern "' > /dev/null 2>&1")] :p)))

(defn- dir-count [path]
  (length (try (os/dir path) ([_] @[]))))

(defn- windowing []
  (cond
    (os/getenv "ZELLIJ_SESSION_NAME")
      (string "zellij  (" (os/getenv "ZELLIJ_SESSION_NAME") ")")
    (os/getenv "TMUX")
      "tmux"
    (os/getenv "WAYLAND_DISPLAY")
      (string "wayland (" (os/getenv "WAYLAND_DISPLAY") ")")
    (os/getenv "DISPLAY")
      (string "x11     (" (os/getenv "DISPLAY") ")")
    "none detected"))

(defn- gather [session]
  (def xdg-data (or (os/getenv "XDG_DATA_HOME")
                    (string (os/getenv "HOME") "/.local/share")))
  (def grammar-dir (string xdg-data "/kak-tree-sitter/grammars"))
  (def grammar-count (dir-count grammar-dir))
  (def kts-ok (kts-running?))
  (def lsp-ok (= 0 (os/execute ["sh" "-c" "command -v kak-lsp > /dev/null 2>&1"] :p)))

  @{:session    (or session (os/getenv "kak_session") "unknown")
    :windowing  (windowing)
    :kts-ok     kts-ok
    :kts-detail (if kts-ok
                  (string "✓  running   (" grammar-count " grammars)")
                  "✗  not running")
    :lsp-ok     lsp-ok
    :lsp-detail (if lsp-ok "✓  available" "✗  not found")
    :arch       (or (os/getenv "KAK_ARCH") (do
                  (def tmp "/tmp/ok-arch")
                  (os/execute ["sh" "-c" (string "uname -m > " tmp)] :p)
                  (string/trimr (string (slurp tmp)))))})

(defn- metric-lines [m]
  (def w 14) # label column width
  (def fmt (fn [label val] (string/format (string "  %-" w "s  %s") label val)))
  @[(fmt "session"     (m :session))
    (fmt "windowing"   (m :windowing))
    (fmt "tree-sitter" (m :kts-detail))
    (fmt "kak-lsp"     (m :lsp-detail))
    (fmt "arch"        (m :arch))])

# ── layout ────────────────────────────────────────────────────────────────────

(defn- max-line-width [text]
  (reduce (fn [acc l] (max acc (length l))) 0 (string/split "\n" text)))

(defn- center [text width]
  (def lw (max-line-width text))
  (def pad (max 0 (div (- width lw) 2)))
  (def prefix (string/repeat " " pad))
  (string/join
    (map (fn [l] (string prefix l)) (string/split "\n" text))
    "\n"))

# ── kak script emission ───────────────────────────────────────────────────────

(defn show [argv]
  (def width   (or (scan-number (get argv 0 "")) 80))
  (def session (get argv 1))
  (def metrics (gather session))
  (def mlines (metric-lines metrics))

  # Assemble full buffer content: centered logo + blank line + centered metrics
  (def metrics-block (string/join mlines "\n"))
  (def content (string
    (center logo width)
    "\n\n"
    (center metrics-block width)
    "\n"))

  # kak string quoting: escape single quotes
  (def escaped (string/replace-all "'" "\\'" content))

  (print (string
    "edit -scratch *splash*\n"
    "set-option buffer filetype scratch\n"
    "execute-keys '%<a-d>'\n"
    "set-register '\"' '" escaped "'\n"
    "execute-keys 'P'\n"
    "execute-keys 'gg'\n"
    # Faces — all use kak built-in theme-aware names.
    # Labels (e.g. "session") → keyword face
    "add-highlighter buffer/ok_labels  regex '^\\s+([\\w-]+)\\s{2,}' 1:keyword\n"
    # ✓ → Information (green in most themes), ✗ → Error (red)
    "add-highlighter buffer/ok_good    regex '✓[^\\n]*' 0:Information\n"
    "add-highlighter buffer/ok_bad     regex '✗[^\\n]*' 0:Error\n"
    # "overk" name in logo → function face
    "add-highlighter buffer/ok_name    regex 'overk' 0:function\n"
    # The art bar at top → comment face (muted, decorative)
    "add-highlighter buffer/ok_bar     regex '_+' 0:comment\n"
    "set-option buffer readonly true\n")))

(defn dispatch [argv]
  (case (get argv 0)
    "show" (show (array/slice argv 1))
    (do
      (eprintf "ok --api splash: unknown command '%s'\n" (get argv 0 ""))
      (os/exit 1))))
