;; ABOUTME: Evaluates Arazzo runtime expressions, templates and criteria
;; ABOUTME: against a workflow execution context.
;; Arazzo runtime expression evaluator.
;; Handles: $inputs.x, $steps.id.outputs.x, $statusCode,
;;          $response.body#/ptr, $response.header.X,
;;          $request.body#/ptr, $url,
;;          $sourceDescriptions.name.operationId,
;;          template strings "text {$expr} text"
(local util (require :atlas.util))

;; ---- JSON Pointer ----

(fn json-pointer [obj ptr]
  "Resolve a JSON Pointer string (/foo/0/bar) into obj."
  (when (and obj ptr (> (length ptr) 0))
    (accumulate [cur obj seg (ptr:gmatch "[^/]+")]
      (when (= (type cur) :table)
        (let [key (pick-values 1
                               (-> seg
                                   (: :gsub "~1" "/")
                                   (: :gsub "~0" "~")))
              n (when (key:match "^%d+$") (tonumber key))]
          (if (and n (= nil (. cur key)))
              (. cur (+ n 1))
              (. cur key)))))))

;; ---- expression resolution ----

(fn with-pointer [value expr]
  "Apply the #/json/pointer suffix of expr to value, when present."
  (let [ptr (expr:match "#(.+)$")]
    (if ptr (json-pointer value ptr) value)))

(fn message-value [msg parts expr]
  "Resolve body or header access on a request/response; parts = [body|header name]."
  (match (. parts 1)
    :body (with-pointer (?. msg :body) expr)
    :header (util.header (?. msg :headers) (or (. parts 2) ""))))

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
                    (when (= (tostring (or (. item mfield) ""))
                             (tostring (or mval "")))
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
              (with-pointer (?. ctx :inputs (. parts 2)) expr)
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
                  :outputs (with-pointer (?. step :outputs (. parts 4)) expr)
                  :response (message-value (?. step :response) (rest-from 4)
                                           expr)
                  :request (message-value (?. step :request) (rest-from 4) expr)))
              :workflows
              (match (. parts 3)
                :outputs (with-pointer (?. ctx :workflows (. parts 2) :outputs
                                           (. parts 4))
                           expr))
              ;; a sentinel table so the caller can look up the client
              :sourceDescriptions
              {:__source (. parts 2) :__operationId (. parts 3)}
              _
              nil))))))

;; ---- template substitution ----

(fn eval-template [ctx s]
  "Substitute {$expr} occurrences in s."
  (pick-values 1 (s:gsub "{(%$[^}]+)}"
                         (fn [expr]
                           (let [v (resolve-expr ctx expr)]
                             (if (= v nil) "" (tostring v)))))))

(fn eval [ctx expr]
  "Evaluate an Arazzo expression, template string, or table (recursively)."
  (if (and (= (type expr) :string) (expr:match "^%$")) (resolve-expr ctx expr)
      (and (= (type expr) :string) (expr:match "{%$")) (eval-template ctx expr)
      (= (type expr) :table) (collect [k v (pairs expr)]
                               k
                               (eval ctx v))
      expr))

;; ---- simple condition language ----
;; Grammar (Arazzo 1.0 "simple" criteria):
;;   or    := and ('||' and)*
;;   and   := unary ('&&' unary)*
;;   unary := '!' unary | cmp
;;   cmp   := value (('=='|'!='|'<'|'<='|'>'|'>=') value)?
;;   value := '(' or ')' | $expr | 'str' | "str" | number | true | false | null | word
;; Runtime expressions are resolved to values and never re-parsed.

(local null {})

(local operators ["==" "!=" "<=" ">=" "&&" "||" "<" ">" "!" "(" ")"])

(fn read-string-literal [s pos]
  "Read a quoted literal starting at pos; returns (text next-pos)."
  (let [delimiter (s:sub pos pos)
        out []]
    (var i (+ pos 1))
    (var done false)
    (while (not done)
      (let [ch (s:sub i i)]
        (if (= ch "") (error (.. "unterminated string in condition: " s))
            (= ch "\\") (do
                         (table.insert out (s:sub (+ i 1) (+ i 1)))
                         (set i (+ i 2)))
            (= ch delimiter) (do
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

(fn equal? [a b]
  (let [(a b) (numeric-pair (normalize a) (normalize b))]
    (= a b)))

(fn ordered [op a b]
  (let [(a b) (numeric-pair (normalize a) (normalize b))
        comparable (or (and (= (type a) :number) (= (type b) :number))
                       (and (= (type a) :string) (= (type b) :string)))]
    (and comparable (match op
                      "<" (< a b)
                      "<=" (<= a b)
                      ">" (> a b)
                      ">=" (>= a b)))))

(fn eval-condition [ctx condition]
  "Evaluate a simple condition string; raises on syntax errors."
  (let [tokens (tokenize condition)
        fail #(error (.. $ " in condition: " condition))]
    (var pos 1)

    (fn peek [] (. tokens pos))

    (fn op? [text]
      (let [t (peek)] (and t (= t.kind :op) (= t.text text))))

    (fn advance [] (set pos (+ pos 1)) (. tokens (- pos 1)))

    (var parse-or nil)

    (fn parse-value []
      (let [t (advance)]
        (if (= t nil) (fail "unexpected end")
            (and (= t.kind :op) (= t.text "("))
            (let [v (parse-or)]
              (if (op? ")") (advance) (fail "missing )"))
              v) (= t.kind :expr) (resolve-expr ctx t.text)
            (= t.kind :literal) t.value (fail (.. "unexpected '" t.text "'")))))

    (fn parse-cmp []
      (let [left (parse-value)
            t (peek)]
        (if (and t (= t.kind :op) (. {"==" true
                                      "!=" true
                                      "<" true
                                      "<=" true
                                      ">" true
                                      ">=" true}
                                     t.text))
            (let [op (. (advance) :text)
                  right (parse-value)]
              (match op
                "==" (equal? left right)
                "!=" (not (equal? left right))
                _ (ordered op left right)))
            left)))

    (fn parse-unary []
      (if (op? "!")
          (do
            (advance)
            (not (truthy? (parse-unary))))
          (parse-cmp)))

    (fn parse-and []
      (var v (truthy? (parse-unary)))
      (while (op? "&&")
        (advance)
        (let [r (truthy? (parse-unary))]
          (set v (and v r))))
      v)

    (set parse-or (fn []
                    (var v (parse-and))
                    (while (op? "||")
                      (advance)
                      (let [r (parse-and)]
                        (set v (or v r))))
                    v))
    (let [result (parse-or)]
      (when (peek)
        (fail (.. "unexpected '" (token-text (peek)) "'")))
      (truthy? result))))

;; ---- criterion evaluation ----

(fn eval-criterion [ctx criterion]
  "Evaluate one Criterion Object. Returns true if it passes."
  (let [typ (or criterion.type :simple)]
    (match typ
      :simple (eval-condition ctx criterion.condition)
      :regex (let [v (eval ctx criterion.context)
                   s (if (= (type v) :string) v (tostring v))]
               (not= nil (s:match criterion.condition)))
      _ (error (.. "unsupported criterion type: " (tostring typ))))))

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
