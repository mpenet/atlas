;; ABOUTME: Evaluates Arazzo runtime expressions, templates and criteria
;; ABOUTME: against a workflow execution context.
;; Arazzo runtime expression evaluator.
;; Handles: $inputs.x, $steps.id.outputs.x, $statusCode,
;;          $response.body#/ptr, $response.header.X,
;;          $request.body#/ptr, $url,
;;          $sourceDescriptions.name.operationId,
;;          template strings "text {$expr} text"
(local util (require :atlas.util))
(local json (require :atlas.json))

;; ---- JSON Pointer ----

(fn json-pointer [obj ptr]
  "Resolve a JSON Pointer string (/foo/0/bar) into obj; nil for an empty pointer."
  (when (and obj ptr (> (length ptr) 0))
    (util.json-pointer obj ptr)))

;; ---- expression resolution ----

(fn with-pointer [value expr]
  "Apply the #/json/pointer suffix of expr to value, when present."
  (let [ptr (expr:match "#(.+)$")]
    (if ptr (json-pointer value ptr) value)))

(fn named [entries parts from kind expr]
  "The entry of entries named by parts from index from on, rejoined with dots
(names may contain dots), with expr's #/pointer applied. When no entry has
that name but one is named by its first part, the expression most likely
meant a JSON pointer into it: raise saying so."
  (let [name (table.concat parts "." from)
        value (?. entries name)]
    (when (and (= nil value) (> (length parts) from)
               (not= nil (?. entries (. parts from))))
      (error (string.format "%s: there is no %s '%s'; for a value inside '%s' use $%s#/%s"
                            expr kind name (. parts from)
                            (table.concat parts "." 1 from)
                            (table.concat parts "/" (+ from 1))) 0))
    (with-pointer value expr)))

(fn message-value [msg parts expr]
  "Resolve body or header access on a request/response; parts = [body|header name]."
  (match (. parts 1)
    :body (with-pointer (?. msg :body) expr)
    :header (util.header (?. msg :headers) (or (. parts 2) ""))
    :query (?. msg :query (. parts 2))
    :path (?. msg :path (. parts 2))))

(fn find-in [ctx resolve find-body]
  "$find(array-expr, match-field, match-value[, return-field])"
  (let [args (icollect [a (find-body:gmatch "[^,]+")] (a:match "^%s*(.-)%s*$"))
        [arr-expr mfield mval-raw rfield] args
        arr (resolve ctx arr-expr)
        mval (if (and mval-raw (mval-raw:match "^%$")) (resolve ctx mval-raw)
                 (and mval-raw (mval-raw:match "^(['\"]).*%1$")) (mval-raw:sub 2
                                                                               -2)
                 mval-raw)]
    (when (= (type arr) :table)
      (let [found (accumulate [found nil _ item (ipairs arr) &until found]
                    (when (and (= (type item) :table) (not= item json.null)
                               (= (tostring (or (. item mfield) ""))
                                  (tostring (or mval ""))))
                      item))]
        (if (and found rfield) (. found rfield) found)))))

(fn resolve-expr [ctx expr]
  "Resolve a single $... runtime expression to a value."
  (let [e (expr:match "^%$(.+)")]
    (when (not e) (error (.. "not a runtime expression: " expr)))
    (let [find-body (e:match "^find%((.+)%)$")]
      (if find-body
          (find-in ctx resolve-expr find-body)
          (let [head (or (e:match "^([^#]+)") "")
                parts (icollect [p (head:gmatch "[^%.]+")] p)
                rest-from #(icollect [i p (ipairs parts)] (when (>= i $) p))]
            (match (. parts 1)
              :inputs
              (named ctx.inputs parts 2 :input expr)
              :statusCode
              (?. ctx :response :status)
              :url
              (?. ctx :request :url)
              :method
              (?. ctx :request :method)
              :response
              (message-value ctx.response (rest-from 2) expr)
              :request
              (message-value ctx.request (rest-from 2) expr)
              :steps
              (let [step (?. ctx :steps (. parts 2))]
                (match (. parts 3)
                  :outputs (named (?. step :outputs) parts 4 :output expr)
                  :response (message-value (?. step :response) (rest-from 4)
                                           expr)
                  :request (message-value (?. step :request) (rest-from 4) expr)))
              :workflows
              (match (. parts 3)
                :outputs (named (?. ctx :workflows (. parts 2) :outputs) parts
                                4 :output expr))
              ;; a sentinel table so the caller can look up the client
              :sourceDescriptions
              ;; source names have no dots, operationIds may
              {:__source (. parts 2) :__operationId (table.concat parts "." 3)}
              _
              (error (.. "unknown runtime expression: " expr) 0)))))))

;; ---- template substitution ----

(fn eval-template [ctx s]
  "Substitute {$expr} occurrences in s."
  (pick-values 1 (s:gsub "{(%$[^}]+)}"
                         (fn [expr]
                           (let [v (resolve-expr ctx expr)]
                             ;; null is no value, like a missing one;
                             ;; structured values as JSON
                             (if (or (= v nil) (= v json.null)) ""
                                 (= (type v) :table) (json.encode v)
                                 (tostring v)))))))

(local roots {:inputs true
              :statusCode true
              :url true
              :method true
              :response true
              :request true
              :steps true
              :workflows true
              :sourceDescriptions true
              :find true})

(fn expression? [s]
  "Whether s is a runtime expression: $ followed by a known root."
  (not= nil (. roots (or (s:match "^%$(%a+)") ""))))

(fn eval [ctx expr]
  "Evaluate an Arazzo expression, template string, or table (recursively).
Text that only starts with $ (\"$5\") is not an expression and stays as is."
  (if (and (= (type expr) :string) (expression? expr)) (resolve-expr ctx expr)
      (and (= (type expr) :string) (expr:match "{%$")) (eval-template ctx expr)
      (= expr json.null) expr
      ;; arrays stay arrays, and an element that resolves to nothing is null,
      ;; so the others keep their place
      (json.array? expr) (json.array (fcollect [i 1 (length expr)]
                                      (match (eval ctx (. expr i))
                                        nil json.null
                                        v v)))
      (= (type expr) :table) (collect [k v (pairs expr)]
                              k
                              (eval ctx v)) expr))

;; ---- simple condition language ----
;; Grammar (Arazzo 1.0 "simple" criteria):
;;   or    := and ('||' and)*
;;   and   := unary ('&&' unary)*
;;   unary := '!' unary | cmp
;;   cmp   := value (('=='|'!='|'<'|'<='|'>'|'>=') value)?
;;   value := '(' or ')' | $expr | 'str' | "str" | number | true | false | null | word
;; Runtime expressions are resolved to values and never re-parsed.

(local null json.null)

(local operators ["==" "!=" "<=" ">=" "&&" "||" "<" ">" "!" "(" ")"])

(fn read-string-literal [s pos]
  "Read a quoted literal starting at pos; returns (text next-pos). As in the
Arazzo spec, a doubled quote stands for the quote itself."
  (let [delimiter (s:sub pos pos)
        out []]
    (var i (+ pos 1))
    (var done false)
    (while (not done)
      (let [ch (s:sub i i)]
        (if (= ch "") (error (.. "unterminated string in condition: " s))
            (and (= ch delimiter) (= (s:sub (+ i 1) (+ i 1)) delimiter))
            (do
              (table.insert out delimiter)
              (set i (+ i 2))) (= ch delimiter)
            (do
              (set done true)
              (set i (+ i 1)))
            (do
              (table.insert out ch)
              (set i (+ i 1))))))
    (values (table.concat out) i)))

(fn tokenize [s]
  (let [tokens []]
    (var pos 1)
    (while (<= pos (length s))
      (let [ws-end (s:match "^%s*()" pos)]
        (set pos ws-end)
        (when (<= pos (length s))
          (let [ch (s:sub pos pos)
                find-expr (s:match "^%$find%b()" pos)
                expr (or find-expr (s:match "^%$[^%s()=!<>&|]+" pos))
                number (s:match "^%-?%d+%.?%d*[eE][%+%-]?%d+" pos)
                number (or number (s:match "^%-?%d+%.?%d*" pos))
                word (s:match "^[%a_][%w_%-%.]*" pos)
                op (accumulate [found nil _ o (ipairs operators) &until found]
                     (when (= (s:sub pos (+ pos (length o) -1)) o)
                       o))]
            (if expr (do
                       (table.insert tokens {:kind :expr :text expr})
                       (set pos (+ pos (length expr))))
                (or (= ch "'") (= ch "\""))
                (let [(text next-pos) (read-string-literal s pos)]
                  (table.insert tokens {:kind :literal :value text})
                  (set pos next-pos)) number
                (do
                  (table.insert tokens
                                {:kind :literal :value (tonumber number)})
                  (set pos (+ pos (length number)))) op
                (do
                  (table.insert tokens {:kind :op :text op})
                  (set pos (+ pos (length op)))) word
                (do
                  (table.insert tokens
                                {:kind :literal
                                 :value (match word "true" true "false" false
                                          "null" null
                                          _ word)})
                  (set pos (+ pos (length word))))
                (error (.. "unexpected character '" ch "' in condition: " s)))))))
    tokens))

(fn numeric-pair [a b]
  "Coerce a numeric string to a number when compared against a number."
  (if (and (= (type a) :number) (= (type b) :string) (tonumber b))
      (values a (tonumber b))
      (and (= (type a) :string) (= (type b) :number) (tonumber a))
      (values (tonumber a) b)
      (values a b)))

(fn token-text [t]
  (if t.text t.text
      (= t.value null) "null"
      (tostring t.value)))

(fn truthy? [v]
  (and (not= v nil) (not= v false) (not= v null)))

(fn normalize [v]
  (if (= v null) nil v))

(fn fold-case [a b]
  "Strings compare case-insensitively, as the Arazzo spec requires."
  (if (and (= (type a) :string) (= (type b) :string))
      (values (a:lower) (b:lower))
      (values a b)))

(fn equal? [a b]
  (let [(a b) (fold-case (numeric-pair (normalize a) (normalize b)))]
    (= a b)))

(fn ordered [op a b]
  (let [(a b) (fold-case (numeric-pair (normalize a) (normalize b)))
        comparable (or (and (= (type a) :number) (= (type b) :number))
                       (and (= (type a) :string) (= (type b) :string)))]
    (and comparable (match op
                      "<" (< a b)
                      "<=" (<= a b)
                      ">" (> a b)
                      ">=" (>= a b)))))

;; The evaluator works on a parser table:
;; {:tokens [...] :pos index :ctx runtime-context :condition source-text}

(local comparison-ops {"==" true
                       "!=" true
                       "<" true
                       "<=" true
                       ">" true
                       ">=" true})

(fn fail [parser message]
  (error (.. message " in condition: " parser.condition)))

(fn peek [parser]
  (. parser.tokens parser.pos))

(fn op? [parser text]
  (let [t (peek parser)]
    (and t (= t.kind :op) (= t.text text))))

(fn advance [parser]
  (set parser.pos (+ parser.pos 1))
  (. parser.tokens (- parser.pos 1)))

(var parse-or nil)

(fn parse-value [parser]
  (let [t (advance parser)]
    (if (= t nil) (fail parser "unexpected end")
        (and (= t.kind :op) (= t.text "("))
        (let [v (parse-or parser)]
          (if (op? parser ")") (advance parser) (fail parser "missing )"))
          v) (= t.kind :expr) (resolve-expr parser.ctx t.text)
        (= t.kind :literal) t.value (fail parser (.. "unexpected '" t.text "'")))))

(fn parse-cmp [parser]
  (let [left (parse-value parser)
        t (peek parser)]
    (if (and t (= t.kind :op) (. comparison-ops t.text))
        (let [op (. (advance parser) :text)
              right (parse-value parser)]
          (match op
            "==" (equal? left right)
            "!=" (not (equal? left right))
            _ (ordered op left right)))
        left)))

(fn parse-unary [parser]
  (if (op? parser "!")
      (do
        (advance parser)
        (not (truthy? (parse-unary parser))))
      (parse-cmp parser)))

(fn parse-and [parser]
  (var v (truthy? (parse-unary parser)))
  (while (op? parser "&&")
    (advance parser)
    (let [r (truthy? (parse-unary parser))]
      (set v (and v r))))
  v)

(set parse-or (fn [parser]
                (var v (parse-and parser))
                (while (op? parser "||")
                  (advance parser)
                  (let [r (parse-and parser)]
                    (set v (or v r))))
                v))

(fn eval-condition [ctx condition]
  "Evaluate a simple condition string; raises on syntax errors."
  (let [parser {:tokens (tokenize condition) :pos 1 : ctx : condition}
        result (parse-or parser)]
    (when (peek parser)
      (fail parser (.. "unexpected '" (token-text (peek parser)) "'")))
    (truthy? result)))

;; ---- criterion evaluation ----

(fn eval-criterion [ctx criterion]
  "Evaluate one Criterion Object. Returns true if it passes."
  (let [typ (or criterion.type :simple)]
    (match typ
      :simple
      (eval-condition ctx criterion.condition)
      ;; a missing value matches nothing
      :regex
      (let [v (eval ctx criterion.context)]
        (and (not= nil v) (not= json.null v)
             (not= nil (: (tostring v) :match criterion.condition))))
      _
      (error (.. "unsupported criterion type: "
                 (tostring (if (= (type typ) :table) typ.type typ)))))))

(fn eval-criteria [ctx criteria]
  "Evaluate all criteria (AND logic). Returns true if all pass."
  (accumulate [ok true _ c (ipairs (or criteria [])) &until (not ok)]
    (eval-criterion ctx c)))

{: eval
 : eval-template
 : resolve-expr
 : eval-criterion
 : eval-criteria
 : json-pointer}
