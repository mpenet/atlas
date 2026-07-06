;; Arazzo runtime expression evaluator.
;; Handles: $inputs.x, $steps.id.outputs.x, $statusCode,
;;          $response.body#/ptr, $response.header.X,
;;          $request.body#/ptr, $url,
;;          $sourceDescriptions.name.operationId,
;;          template strings "text {$expr} text"

;; ---- JSON Pointer ----

(fn json-pointer [obj ptr]
  "Resolve a JSON Pointer string (/foo/0/bar) into obj."
  (when (and obj ptr (> (length ptr) 0))
    (var cur obj)
    (let [path (if (= (ptr:sub 1 1) "/") (ptr:gsub "^/" "") ptr)]
      (each [seg (path:gmatch "[^/]+")]
        (when cur
          (let [key (-> seg
                        (: :gsub "~1" "/")
                        (: :gsub "~0" "~"))
                n (tonumber key)]
            (set cur (if n (. cur (+ n 1)) (. cur key))))))
      cur)))

;; ---- expression resolution ----

(fn resolve-expr [ctx expr]
  "Resolve a single $... runtime expression to a value."
  (let [e (expr:match "^%$(.+)")]
    (when (not e) (error (.. "not a runtime expression: " expr)))
    (let [parts []]
      (each [p (e:gmatch "[^%.#]+")]
        (table.insert parts p))
      (match (. parts 1)
        :inputs
        (. ctx.inputs (. parts 2))

        :statusCode
        (?. ctx :response :status)

        :url
        (?. ctx :request :url)

        :method
        (?. ctx :request :method)

        :response
        (match (. parts 2)
          :body   (let [ptr (expr:match "#(.+)$")]
                    (json-pointer (?. ctx :response :body) (or ptr "")))
          :header (let [h (. parts 3)]
                    (?. ctx :response :headers h)))

        :request
        (match (. parts 2)
          :body   (let [ptr (expr:match "#(.+)$")]
                    (json-pointer (?. ctx :request :body) (or ptr "")))
          :header (let [h (. parts 3)]
                    (?. ctx :request :headers h)))

        :steps
        (let [step-id (. parts 2)
              field   (. parts 3)]
          (match field
            :outputs (. (or (?. ctx :steps step-id :outputs) {}) (. parts 4))
            :response
            (match (. parts 4)
              :body   (let [ptr (expr:match "#(.+)$")]
                        (json-pointer (?. ctx :steps step-id :response :body) (or ptr "")))
              :header (. (or (?. ctx :steps step-id :response :headers) {}) (. parts 5)))
            :request
            (match (. parts 4)
              :body   (let [ptr (expr:match "#(.+)$")]
                        (json-pointer (?. ctx :steps step-id :request :body) (or ptr "")))
              :header (. (or (?. ctx :steps step-id :request :headers) {}) (. parts 5)))
            _ nil))

        :workflows
        (let [wf-id (. parts 2)]
          (match (. parts 3)
            :outputs (. (or (?. ctx :workflows wf-id :outputs) {}) (. parts 4))
            _ nil))

        :sourceDescriptions
        (let [src-name (. parts 2)
              op-id    (. parts 3)]
          ;; return a sentinel table so the caller can look up the client
          {:__source src-name :__operationId op-id})

        _ nil))))

;; ---- template substitution ----

(fn eval-template [ctx s]
  "Substitute {$expr} occurrences in s."
  (: s :gsub "{(%$[^}]+)}"
     (fn [expr]
       (let [v (resolve-expr ctx expr)]
         (if (= v nil) "" (tostring v))))))

(fn eval [ctx expr]
  "Evaluate an Arazzo expression, template string, or table (recursively)."
  (if (and (= (type expr) :string) (expr:match "^%$"))
      (resolve-expr ctx expr)
      (and (= (type expr) :string) (expr:match "{%$"))
      (eval-template ctx expr)
      (= (type expr) :table)
      (let [result {}]
        (each [k v (pairs expr)]
          (tset result k (eval ctx v)))
        result)
      expr))

;; ---- criterion evaluation ----

(fn coerce-val [s]
  (if (= s "true") true
      (= s "false") false
      (= s "null") nil
      (tonumber s) (tonumber s)
      (s:match "^\"(.*)\"$") (s:match "^\"(.*)\"$")
      s))

(fn resolve-value [ctx expr-str]
  "Resolve a $expr to a Lua value; return nil on error."
  (let [(ok v) (pcall resolve-expr ctx expr-str)]
    (when ok v)))

(fn substitute [ctx condition]
  "Replace $expr tokens in condition with quoted Lua-comparable literals."
  (condition:gsub "%$[%w%.#/_%-]+"
    (fn [expr-tok]
      (let [v (resolve-value ctx expr-tok)]
        (if (= v nil) "null"
            (= (type v) :boolean) (tostring v)
            (= (type v) :number)  (tostring v)
            (= (type v) :string)  (.. "\"" v "\"")
            "null")))))

(fn try-compare [s]
  "Try operators longest-first. Returns (lhs op rhs) or nil."
  (let [(l r) (s:match "^(.-)%s*==%s*(.+)$")]
    (if l (values l "==" r)
        (let [(l r) (s:match "^(.-)%s*!=%s*(.+)$")]
          (if l (values l "!=" r)
              (let [(l r) (s:match "^(.-)%s*<=%s*(.+)$")]
                (if l (values l "<=" r)
                    (let [(l r) (s:match "^(.-)%s*>=%s*(.+)$")]
                      (if l (values l ">=" r)
                          (let [(l r) (s:match "^(.-)%s*<%s*(.+)$")]
                            (if l (values l "<" r)
                                (let [(l r) (s:match "^(.-)%s*>%s*(.+)$")]
                                  (when l (values l ">" r))))))))))))))

(fn eval-part [s]
  (let [s (s:match "^%s*(.-)%s*$")]
    (if (= s "") true
        (s:match "^!")
        (not (eval-part (s:sub 2)))
        (let [(lhs op rhs) (try-compare s)]
          (if (and lhs op rhs)
              (let [l (coerce-val (lhs:match "^%s*(.-)%s*$"))
                    r (coerce-val (rhs:match "^%s*(.-)%s*$"))]
                (match op
                  "==" (= l r)
                  "!=" (not= l r)
                  "<"  (and (= (type l) :number) (= (type r) :number) (< l r))
                  "<=" (and (= (type l) :number) (= (type r) :number) (<= l r))
                  ">"  (and (= (type l) :number) (= (type r) :number) (> l r))
                  ">=" (and (= (type l) :number) (= (type r) :number) (>= l r))
                  _    false))
              (let [v (coerce-val s)]
                (and (not= v nil) (not= v false))))))))

(fn split-on [s sep]
  "Split string s on literal sep, return list of parts."
  (let [parts []]
    (var pos 1)
    (while (<= pos (length s))
      (let [i (s:find sep pos true)]
        (if i
            (do (table.insert parts (s:sub pos (- i 1)))
                (set pos (+ i (length sep))))
            (do (table.insert parts (s:sub pos))
                (set pos (+ (length s) 1))))))
    parts))

(fn eval-simple-condition [ctx condition]
  "Evaluate a simple Arazzo condition string."
  (let [resolved (substitute ctx condition)]
    (var result false)
    (each [_ or-part (ipairs (split-on resolved "||"))]
      (when (not result)
        (var and-result true)
        (each [_ and-part (ipairs (split-on or-part "&&"))]
          (when and-result
            (set and-result (eval-part and-part))))
        (when and-result (set result true))))
    result))

(fn eval-criterion [ctx criterion]
  "Evaluate one Criterion Object. Returns true if it passes."
  (let [typ (or criterion.type :simple)]
    (match typ
      :simple (eval-simple-condition ctx criterion.condition)
      :regex  (let [v (eval ctx criterion.context)
                    s (if (= (type v) :string) v (tostring v))]
                (not= nil (s:match criterion.condition)))
      _ (error (.. "unsupported criterion type: " typ)))))

(fn eval-criteria [ctx criteria]
  "Evaluate all criteria (AND logic). Returns true if all pass."
  (if (or (not criteria) (= (length criteria) 0))
      true
      (do
        (var ok true)
        (each [_ c (ipairs criteria)]
          (when ok (set ok (eval-criterion ctx c))))
        ok)))

{: eval : eval-template : resolve-expr : eval-criterion : eval-criteria : json-pointer}
