# src/kak.janet — Janet-to-Kakscript DSL compiler

(defn q [str]
  "Escape single quotes for Kakscript."
  (string "'" (string/replace-all "'" "''" str) "'"))

(def quote q)

(defn parse-quoted-list [s]
  "Parse a space-separated list of single-quoted strings (Kakoune's quoted lists)."
  (def result @[])
  (var current @[])
  (var in-quotes false)
  (var i 0)
  (while (< i (length s))
    (def c (get s i))
    (if in-quotes
      (if (= c 39) # 39 is ascii code for single quote "'"
        (if (and (< (+ i 1) (length s)) (= (get s (+ i 1)) 39))
          (do
            (array/push current 39)
            (set i (+ i 2)))
          (do
            (set in-quotes false)
            (array/push result (string/from-bytes ;current))
            (array/clear current)
            (++ i)))
        (do
          (array/push current c)
          (++ i)))
      (if (= c 39)
        (do
          (set in-quotes true)
          (++ i))
        (++ i))))
  result)

(var compile-expr nil)
(var compile-arg nil)
(var compile-cmd nil)
(var compile-block nil)

(def- switch-flags
  {:override true
   :readonly true
   :existing true
   :scratch true
   :menu true
   :buffer-completion true
   :file-completion true
   :client-completion true
   :shell-completion true
   :shell-script-completion true
   :hidden true
   :once true
   :always true
   :add true
   :remove true
   :draft true
   :no-hooks true
   :itersel true})

(def- switch-options
  {:docstring true
   :params true
   :shell-script-candidates true
   :group true
   :client true
   :save-regs true
   :buffer true
   :try-client true})

(defn- switch? [k]
  (or (get switch-flags k)
      (get switch-options k)))

(defn- flag? [k]
  (get switch-flags k))

(set compile-arg (fn [arg]
  (cond
    (nil? arg) ""
    (string? arg) (q arg)
    (keyword? arg) (string arg)
    (symbol? arg) (string arg)
    (number? arg) (string arg)
    (boolean? arg) (string arg)
    (indexed? arg) (compile-expr arg)
    (error (string "Unsupported AST node: " (type arg) " - " (describe arg))))))

(set compile-cmd (fn [cmd-name args]
  (def switches @[])
  (def pos-args @[])
  (var i 0)
  (while (< i (length args))
    (def item (get args i))
    (cond
      (and (keyword? item) (switch? item))
      (if (flag? item)
        (do
          (array/push switches (string "-" item))
          (++ i))
        (do
          (array/push switches (string "-" item))
          (if (< (+ i 1) (length args))
            (do
              (def val (get args (+ i 1)))
              (array/push switches (compile-arg val))
              (set i (+ i 2)))
            (error (string "Keyword switch " item " is missing a value")))))
      # Not a switch keyword: it's a positional argument!
      (do
        (array/push pos-args (compile-arg item))
        (++ i))))
  
  (def parts @[cmd-name])
  (when (not (empty? switches))
    (array/concat parts switches))
  (when (not (empty? pos-args))
    (array/concat parts pos-args))
  (string/join parts " ")))

(set compile-block (fn [exprs]
  (def parts @[])
  (each expr exprs
    (array/push parts (compile-expr expr)))
  (string/join parts "\n")))

(set compile-expr (fn [expr]
  (cond
    (indexed? expr)
    (if (empty? expr)
      ""
      (let [head (first expr)
            head-kw (cond
                      (keyword? head) head
                      (symbol? head) (keyword head)
                      nil)]
        (case head-kw
          :sh
          (let [args (slice expr 1)
                processed-args @[]]
            (each arg args
              (array/push processed-args (if (string? arg) [:raw arg] arg)))
            (string "%sh{\n" (compile-block processed-args) "\n}"))
          
          :try
          (let [args (slice expr 1)
                process-try-arg (fn [arg]
                                  (if (and (indexed? arg)
                                           (not (empty? arg))
                                           (let [head (first arg)
                                                 head-kw (cond
                                                           (keyword? head) head
                                                           (symbol? head) (keyword head)
                                                           nil)]
                                             (not (get {:block true :sh true :raw true} head-kw))))
                                    [:block arg]
                                    arg))
                arg0 (process-try-arg (get args 0))
                arg1 (if (= (length args) 2) (process-try-arg (get args 1)) nil)]
            (case (length args)
              1 (string "try " (compile-arg arg0))
              2 (string "try " (compile-arg arg0) " catch " (compile-arg arg1))
              (error "try form takes 1 or 2 arguments")))
          
          :block
          (string "%{\n" (compile-block (slice expr 1)) "\n}")
          
          :raw
          (if (= (length expr) 2)
            (get expr 1)
            (error "raw form takes exactly 1 argument"))
          
          :sh-var
          (if (= (length expr) 2)
            (string "\"$" (string (get expr 1)) "\"")
            (error "sh-var form takes exactly 1 argument"))
          
          :sh-call
          (if (= (length expr) 2)
            (let [val (get expr 1)]
              (string "\"$(" (if (string? val) val (compile-expr val)) ")\""))
            (error "sh-call form takes exactly 1 argument"))

          :val
          (if (= (length expr) 2)
            (string "%val{" (string (get expr 1)) "}")
            (error "val form takes exactly 1 argument"))

          :opt
          (if (= (length expr) 2)
            (string "%opt{" (string (get expr 1)) "}")
            (error "opt form takes exactly 1 argument"))

          :reg
          (if (= (length expr) 2)
            (string "%reg{" (string (get expr 1)) "}")
            (error "reg form takes exactly 1 argument"))

          :dq
          (if (= (length expr) 2)
            (let [val (get expr 1)]
              (string "\"" (if (string? val) val (compile-expr val)) "\""))
            (error "dq form takes exactly 1 argument"))
          
          # default command call
          (let [cmd-name (cond
                           (keyword? head) (string head)
                           (symbol? head) (string head)
                           (string? head) head
                           (error "Command name must be a keyword, symbol, or string"))]
            (compile-cmd cmd-name (slice expr 1))))))
    (compile-arg expr))))

(defn eval-sh [code]
  "Generate evaluate-commands %sh{ ... }."
  (compile-expr [:evaluate-commands [:sh (if (string? code) [:raw code] code)]]))

(defn map [scope mode key action &keys {:docstring docstring}]
  "Create mapping string."
  (def ast @[:map])
  (if docstring
    (array/concat ast [:docstring docstring]))
  (array/concat ast [scope mode key action])
  (compile-expr ast))

(defn defcmd [name docstring body]
  "Define custom Kakoune command."
  (compile-expr [:define-command name :docstring docstring [:block (if (string? body) [:raw body] body)]]))

(defn declare-user-mode [mode]
  "Declare user mode."
  (compile-expr [:declare-user-mode (if (string? mode) (keyword mode) mode)]))

(defn enter-user-mode [mode]
  "Enter user mode."
  (compile-expr [:enter-user-mode (if (string? mode) (keyword mode) mode)]))

(defn api-cmd [module action & args]
  "Correctly builds the ok --api command string using the AST compiler."
  (def ast @['ok '--api (symbol module) (symbol action)])
  (each arg args
    (cond
      (= arg :pwd) (array/push ast [:sh-var "PWD"])
      (keyword? arg) (array/push ast [:sh-var (string "kak_" arg)])
      (array/push ast arg)))
  (compile-expr ast))

(defn defcmd-api [cmd-name docstring module action args]
  "High-level command definition linking directly to ok API."
  (def cmd (api-cmd module action ;args))
  (def body [:evaluate-commands [:sh [:raw cmd]]])
  (defcmd (string cmd-name) docstring body))

