;; ABOUTME: Validates decoded request values against the JSON Schema subset
;; ABOUTME: OpenAPI bodies use, returning readable errors with paths.
(local json (require :atlas.json))

(fn integral? [v]
  (and (= (type v) :number) (= v (math.floor v)) (not= v math.huge)
       (not= v (- math.huge))))

(local null
       ;; stands for an explicit JSON null, which decoding would otherwise drop
       (setmetatable {} {:__tostring #"null"}))

(fn json-type [v]
  "JSON type name of a decoded value; an empty table is an array only when
marked as one."
  (match (if (= v null) :null (type v))
    :null :null
    :nil :null
    :boolean :boolean
    :string :string
    :number (if (integral? v) :integer :number)
    :table (if (json.array? v) :array :object)
    _ (type v)))

(fn type-matches? [expected v]
  (let [actual (json-type v)]
    (or (= expected actual) (and (= expected :number) (= actual :integer)))))

(fn allowed-types [schema]
  "The JSON types schema allows, or [] for any; nullable (OpenAPI 3.0) only
adds null to a declared type."
  (let [t schema.type
        types (if (= (type t) :table) (icollect [_ x (ipairs t)] x)
                  (= nil t) []
                  [t])]
    (when (and schema.nullable (next types)) (table.insert types :null))
    types))

(fn show [v]
  (if (= (type v) :string) (.. "\"" v "\"") (tostring v)))

(var check-value nil)

(fn check-object [schema v path errors]
  (each [_ name (ipairs (or schema.required []))]
    (when (= nil (. v name))
      (table.insert errors (.. path "." name ": required"))))
  (let [names (icollect [k (pairs v)] k)]
    (table.sort names #(< (tostring $1) (tostring $2)))
    (each [_ name (ipairs names)]
      (let [prop (?. schema :properties name)
            sub-path (.. path "." (tostring name))]
        (if (not= nil prop) (check-value prop (. v name) sub-path errors)
            (= false schema.additionalProperties)
            (table.insert errors (.. sub-path ": not allowed"))
            (= (type schema.additionalProperties) :table)
            (check-value schema.additionalProperties (. v name) sub-path errors))))))

(fn check-array [schema v path errors]
  (when (and (= (type schema.minItems) :number) (< (length v) schema.minItems))
    (table.insert errors
                  (string.format "%s: fewer than %d items" path schema.minItems)))
  (when (and (= (type schema.maxItems) :number) (> (length v) schema.maxItems))
    (table.insert errors
                  (string.format "%s: more than %d items" path schema.maxItems)))
  (when schema.items
    (each [i item (ipairs v)]
      (check-value schema.items item (.. path "[" (- i 1) "]") errors))))

(fn check-scalar [schema v path errors]
  (when (= (type v) :string)
    (when (and (= (type schema.minLength) :number)
               (< (or (utf8.len v) (length v)) schema.minLength))
      (table.insert errors
                    (string.format "%s: shorter than %d characters" path
                                   schema.minLength)))
    (when (and (= (type schema.maxLength) :number)
               (> (or (utf8.len v) (length v)) schema.maxLength))
      (table.insert errors
                    (string.format "%s: longer than %d characters" path
                                   schema.maxLength))))
  (when (= (type v) :number)
    (when (and (= (type schema.minimum) :number) (< v schema.minimum))
      (table.insert errors
                    (string.format "%s: less than %s" path
                                   (tostring schema.minimum))))
    (when (and (= (type schema.maximum) :number) (> v schema.maximum))
      (table.insert errors
                    (string.format "%s: greater than %s" path
                                   (tostring schema.maximum))))))

;; ?active: the schemas already being applied to v through allOf/anyOf/oneOf,
;; so a schema composed (directly or not) of itself is applied once
(set check-value
     (fn [schema v path errors ?active]
       ;; OpenAPI 3.1 boolean schemas: true allows anything, false nothing
       (if (= schema true) nil (= schema false)
           (table.insert errors (.. path ": not allowed"))
           (let [types (allowed-types schema)
                 active (doto (collect [k (pairs (or ?active {}))]
                                k
                                true)
                          (tset schema true))
                 compose (fn [sub sub-errors]
                           (when (not (. active sub))
                             (check-value sub v path sub-errors active)))]
             (if (and (> (length types) 0)
                      (not (accumulate [ok false _ t (ipairs types) &until ok]
                             (type-matches? t v))))
                 (table.insert errors
                               (string.format "%s: expected %s, got %s" path
                                              (table.concat types " or ")
                                              (json-type v)))
                 (and schema.enum
                      (not (accumulate [found false _ e (ipairs schema.enum)
                                        &until found]
                             (= e v))))
                 (table.insert errors
                               (string.format "%s: %s is not one of %s" path
                                              (show v)
                                              (table.concat (icollect [_ e (ipairs schema.enum)]
                                                              (tostring e))
                                                            ", ")))
                 (do
                   (each [_ sub (ipairs (or schema.allOf []))]
                     (compose sub errors))
                   (let [alternatives (or schema.anyOf schema.oneOf)]
                     (when (and alternatives
                                (not (accumulate [ok false _ sub (ipairs alternatives)
                                                  &until ok]
                                       (let [sub-errors []]
                                         (compose sub sub-errors)
                                         (= 0 (length sub-errors))))))
                       (table.insert errors
                                     (.. path
                                         ": does not match any of the allowed schemas"))))
                   (match (json-type v)
                     :object (check-object schema v path errors)
                     :array (do
                              (check-array schema v path errors)
                              (when (or schema.properties schema.required)
                                (check-object schema v path errors)))
                     _ (check-scalar schema v path errors))))))))

(fn check [schema value ?path]
  "Errors (a list of \"path: problem\" strings) for value against schema."
  (let [errors []]
    (check-value (or schema {}) value (or ?path "value") errors)
    errors))

{: check : null}
