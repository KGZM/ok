(import ../src/kak)
(import ../src/jump)
(import ../src/buffers)
(import ../src/files)

# Helper to check if a string contains another string
(defn- contains? [str substr]
  (not (nil? (string/find substr str))))

# ── kak/quote ─────────────────────────────────────────────────────────────────
(print "Testing kak/quote...")
(assert (= "''" (kak/quote "")) "quote empty string")
(assert (= "'foo'" (kak/quote "foo")) "quote simple string")
(assert (= "'foo''bar'" (kak/quote "foo'bar")) "quote string with internal single quote")
(assert (= "'''foo''bar'''" (kak/quote "'foo'bar'")) "quote string with starting and ending single quotes")
(assert (= "'a''b''c'" (kak/quote "a'b'c")) "quote string with multiple single quotes")

# ── kak/eval-sh ───────────────────────────────────────────────────────────────
(print "Testing kak/eval-sh...")
(let [sh-cmd (kak/eval-sh "echo 'hello'")]
  (assert (contains? sh-cmd "evaluate-commands") "eval-sh: contains evaluate-commands")
  (assert (contains? sh-cmd "%sh{") "eval-sh: contains %sh{")
  (assert (contains? sh-cmd "echo 'hello'") "eval-sh: contains the code"))

# ── kak/map ───────────────────────────────────────────────────────────────────
(print "Testing kak/map...")
# Signature: (kak/map scope mode key action &keys {:docstring docstring})
(let [m1 (kak/map :global :normal "f" ":file-picker<ret>" :docstring "File picker")
      m2 (kak/map :buffer :insert "<c-o>" "<esc>")]
  (assert (contains? m1 "map") "map: starts with map")
  (assert (contains? m1 "global") "map: global scope")
  (assert (contains? m1 "normal") "map: normal mode")
  (assert (contains? m1 "f") "map: key binding")
  (assert (contains? m1 ":file-picker<ret>") "map: action")
  (assert (contains? m1 "-docstring") "map: docstring switch")
  (assert (contains? m1 "'File picker'") "map: docstring value")

  (assert (contains? m2 "map") "map buffer: starts with map")
  (assert (contains? m2 "buffer") "map buffer: buffer scope")
  (assert (contains? m2 "insert") "map buffer: insert mode")
  (assert (not (contains? m2 "-docstring")) "map buffer: no docstring switch if omitted"))

# ── kak/defcmd ────────────────────────────────────────────────────────────────
(print "Testing kak/defcmd...")
# Signature: (kak/defcmd name docstring body)
(let [cmd (kak/defcmd "my-cmd" "A test command" "echo 'hello'")]
  (assert (contains? cmd "define-command") "defcmd: define-command present")
  (assert (contains? cmd "my-cmd") "defcmd: command name present")
  (assert (contains? cmd "-docstring") "defcmd: -docstring switch present")
  (assert (contains? cmd "'A test command'") "defcmd: docstring content present")
  (assert (contains? cmd "echo 'hello'") "defcmd: command body present"))

# ── kak/declare-user-mode & enter-user-mode ──────────────────────────────────
(print "Testing kak/declare-user-mode & kak/enter-user-mode...")
(assert (= "declare-user-mode my-mode" (kak/declare-user-mode :my-mode)) "declare-user-mode keyword")
(assert (= "declare-user-mode my-mode" (kak/declare-user-mode "my-mode")) "declare-user-mode string")
(assert (= "enter-user-mode my-mode" (kak/enter-user-mode :my-mode)) "enter-user-mode keyword")
(assert (= "enter-user-mode my-mode" (kak/enter-user-mode "my-mode")) "enter-user-mode string")

# ── kak/api-cmd ───────────────────────────────────────────────────────────────
(print "Testing kak/api-cmd...")
# Signature: (kak/api-cmd module action & args)
(let [c1 (kak/api-cmd :clipboard :copy :session :client "literal val")
      c2 (kak/api-cmd :files :find :pwd :buffile)]
  (assert (= "ok --api clipboard copy \"$kak_session\" \"$kak_client\" 'literal val'" c1) "api-cmd: keyword, session, client, literal")
  
  (def expected-pwd-ok1 "ok --api files find \"$PWD\" \"$kak_buffile\"")
  (def expected-pwd-ok2 "ok --api files find \"$kak_opt_ok_pwd\" \"$kak_buffile\"")
  (assert (or (= expected-pwd-ok1 c2) (= expected-pwd-ok2 c2))
          "api-cmd: handles :pwd and other variable conversions"))

# ── kak/defcmd-api ────────────────────────────────────────────────────────────
(print "Testing kak/defcmd-api...")
# Signature: (kak/defcmd-api cmd-name docstring module action args)
(let [cmd (kak/defcmd-api :my-cmd "My command doc" :clipboard :copy [:session :client])]
  (assert (contains? cmd "define-command") "defcmd-api: defines a command")
  (assert (contains? cmd "my-cmd") "defcmd-api: has command name")
  (assert (contains? cmd "-docstring") "defcmd-api: has -docstring")
  (assert (contains? cmd "'My command doc'") "defcmd-api: has docstring content")
  (assert (contains? cmd "evaluate-commands") "defcmd-api: has evaluate-commands")
  (assert (contains? cmd "%sh{") "defcmd-api: has %sh{")
  (assert (contains? cmd "ok --api clipboard copy") "defcmd-api: runs ok --api clipboard copy")
  (assert (contains? cmd "$kak_session") "defcmd-api: passes session")
  (assert (contains? cmd "$kak_client") "defcmd-api: passes client"))

# ── kak/compile-expr ──────────────────────────────────────────────────────────
(print "Testing kak/compile-expr AST features...")
(assert (= "%sh{\necho 'hello'\n}" (kak/compile-expr [:sh [:echo "hello"]])) "compile-expr: sh block")
(assert (= "try %{\ndelete-buffer 'foo'\n} catch %{\necho 'failed'\n}" 
           (kak/compile-expr [:try [:delete-buffer "foo"] [:echo "failed"]])) "compile-expr: try catch")
(assert (= "try %{\ndelete-buffer 'foo'\n}" 
           (kak/compile-expr [:try [:delete-buffer "foo"]])) "compile-expr: try only")
(assert (= "try %{\ndelete-buffer 'foo'\n}" 
           (kak/compile-expr [:try [:block [:delete-buffer "foo"]]])) "compile-expr: try already block")
(assert (= "try %sh{\necho 'hello'\n}" 
           (kak/compile-expr [:try [:sh "echo 'hello'"]])) "compile-expr: try already sh")
(assert (= "try delete-buffer 'foo'" 
           (kak/compile-expr [:try [:raw "delete-buffer 'foo'"]])) "compile-expr: try already raw")
(assert (= "try %{\nremove-highlighter 'foo'\n}"
           (kak/compile-expr [:try [:remove-highlighter "foo"]])) "compile-expr: try remove-highlighter")
(assert (= "%{\necho 'foo'\necho 'bar'\n}" 
           (kak/compile-expr [:block [:echo "foo"] [:echo "bar"]])) "compile-expr: block")
(assert (= "hello" (kak/compile-expr [:raw "hello"])) "compile-expr: raw")
(assert (= "\"$my_var\"" (kak/compile-expr [:sh-var "my_var"])) "compile-expr: sh-var")
(assert (= "\"$(date +%s)\"" (kak/compile-expr [:sh-call "date +%s"])) "compile-expr: sh-call")
(assert (= "%val{timestamp}" (kak/compile-expr [:val :timestamp])) "compile-expr: val")
(assert (= "%opt{my_opt}" (kak/compile-expr [:opt :my_opt])) "compile-expr: opt")
(assert (= "%reg{a}" (kak/compile-expr [:reg :a])) "compile-expr: reg")
(assert (= "\"%val{text}\"" (kak/compile-expr [:dq [:val :text]])) "compile-expr: dq with nested val")
(assert (= "\"hello\"" (kak/compile-expr [:dq "hello"])) "compile-expr: dq with string")
(assert (= "define-command -docstring 'Open a file' -params 1 my-cmd %{\nhello\n}" 
           (kak/compile-expr [:define-command :my-cmd :docstring "Open a file" :params 1 [:block [:raw "hello"]]]))
        "compile-expr: keyword gathering for command switches")

# ── kak/parse-quoted-list ─────────────────────────────────────────────────────
(print "Testing kak/parse-quoted-list...")
(def parsed (kak/parse-quoted-list "'buf1' 'buf2' 'buf''3'"))
(assert (= 3 (length parsed)) "parse-quoted-list: length is 3")
(assert (= "buf1" (get parsed 0)) "parse-quoted-list: buf1")
(assert (= "buf2" (get parsed 1)) "parse-quoted-list: buf2")
(assert (= "buf'3" (get parsed 2)) "parse-quoted-list: buf'3")
# ── Regression checks for single-quoted expansions ────────────────────────────
(print "Testing registration output for regressions...")
(let [jump-reg (jump/register)
      buffers-reg (buffers/register)
      files-reg (files/register)]
  (assert (not (contains? jump-reg "'%val{timestamp}'")) "jump register: no quoted timestamp")
  (assert (not (contains? jump-reg "'$1'")) "jump register: no quoted $1")
  (assert (not (contains? jump-reg "'%val{key}'")) "jump register: no quoted key")
  (assert (not (contains? buffers-reg "'%val{text}'")) "buffers register: no quoted text")
  (assert (not (contains? files-reg "'%val{text}'")) "files register: no quoted text"))

(print "\nAll kak DSL tests passed.")
