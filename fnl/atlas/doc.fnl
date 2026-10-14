;; ABOUTME: Renders human-readable help for an operation; the library form is
;; ABOUTME: each op's REPL docstring, and the CLI reuses render for its --help.
(local util (require :atlas.util))
(local negotiate (require :atlas.negotiate))

(fn params-of-kind [op-spec kind]
  (icollect [_ p (ipairs (or op-spec.parameters []))]
    (when (= p.in kind) p)))

(fn template-path-params [path op-spec]
  "Path params in URL template order, with declared details where present."
  (let [declared (collect [_ p (ipairs (params-of-kind op-spec :path))]
                   p.name
                   p)]
    (icollect [_ name (ipairs (util.extract-path-params path))]
      (or (. declared name) {:name name :in "path"}))))

(fn type-name [schema]
  "A schema's type for help: \"string\", \"string | null\" (OpenAPI 3.1 type
arrays), or \"any\"."
  (let [t (?. schema :type)]
    (if (= (type t) :table) (table.concat t " | ") (or t :any))))

(fn param-type [p]
  (type-name p.schema))

(fn param-extras [p required?]
  (let [parts []]
    (when required? (table.insert parts "[required]"))
    (when (?. p :schema :enum)
      (table.insert parts (.. "["
                              (table.concat (icollect [_ v (ipairs p.schema.enum)]
                                              (tostring v))
                                            "|")
                              "]")))
    (when (not= nil (?. p :schema :default))
      (table.insert parts (.. "(default: " (tostring p.schema.default) ")")))
    (when p.description
      (table.insert parts (.. "— " p.description)))
    (if (> (length parts) 0) (.. " " (table.concat parts " ")) "")))

(fn sorted-keys [t]
  (doto (icollect [k (pairs t)] (tostring k))
    (table.sort)))

(fn body-schema [request-body]
  (let [content request-body.content
        media-type (negotiate.pick-media-type content)
        schema (when media-type (?. content media-type :schema))]
    (when (and schema schema.properties)
      (let [required-set {}]
        (each [_ r (ipairs (or schema.required []))]
          (tset required-set r true))
        {:properties schema.properties :required required-set}))))

(fn render [path method op-spec style]
  "Help text for an operation; style supplies the usage line, the query
params heading and an optional body hint, which differ between CLI and library."
  (let [lines []
        add #(table.insert lines $)
        path-params (template-path-params path op-spec)
        query-params (params-of-kind op-spec :query)
        param-line #(string.format "  %-16s %s%s" $1.name (param-type $1)
                                   (param-extras $1 $2))]
    (add (string.format "%s %s" (method:upper) path))
    (let [s (when (and op-spec.summary (not= op-spec.summary ""))
              op-spec.summary)
          d (when (and op-spec.description (not= op-spec.description "")
                       (not= op-spec.description op-spec.summary))
              op-spec.description)]
      (when s (add (.. "\n" s)))
      (when d (add d)))
    (add (.. "\nUsage: "
             (style.usage (util.operation-name method path op-spec) op-spec
                          path-params query-params)))
    (when (> (length path-params) 0)
      (add "\nPath params:")
      (each [_ p (ipairs path-params)]
        (add (param-line p true))))
    (when (> (length query-params) 0)
      (add (.. "\n" style.query-heading))
      (each [_ p (ipairs query-params)]
        (add (param-line p p.required))))
    (when op-spec.requestBody
      (let [rb op-spec.requestBody
            bschema (body-schema rb)]
        (add (string.format "\nBody: %s%s" (if rb.required :required :optional)
                            (if rb.description (.. " — " rb.description) "")))
        (when style.body-hint (add style.body-hint))
        (when bschema
          (each [_ name (ipairs (sorted-keys bschema.properties))]
            (local prop (. bschema.properties name))
            (add (string.format "  %-16s %s%s%s" name (type-name prop)
                                (if (. bschema.required name) " [required]" "")
                                (if prop.description
                                    (.. " — " prop.description)
                                    "")))))))
    (add "\nResponses:")
    (let [responses (or op-spec.responses {})]
      (each [_ code (ipairs (sorted-keys responses))]
        (add (string.format "  %-6s %s" code
                            (or (. responses code :description) "")))))
    (table.concat lines "\n")))

(fn invoke-usage [name op-spec path-params query-params]
  (let [parts []]
    (when (> (length path-params) 0)
      (table.insert parts (.. ":path {"
                              (table.concat (icollect [_ p (ipairs path-params)]
                                              (.. ":" p.name " …"))
                                            " ")
                              "}")))
    (when op-spec.requestBody (table.insert parts ":body …"))
    (when (> (length query-params) 0) (table.insert parts ":query {…}"))
    (if (> (length parts) 0)
        (string.format "(%s.invoke {%s})" name (table.concat parts " "))
        (string.format "(%s.invoke)" name))))

(fn positional-usage [name op-spec path-params query-params]
  (let [sig (icollect [_ p (ipairs path-params)] p.name)]
    (when op-spec.requestBody (table.insert sig :body))
    (when (> (length query-params) 0) (table.insert sig :?opts))
    (if (> (length sig) 0)
        (string.format "(%s %s)" name (table.concat sig " "))
        (string.format "(%s)" name))))

(local library-style
       {:usage (fn [name op-spec path-params query-params]
                 (.. (invoke-usage name op-spec path-params query-params)
                     "\n       "
                     (positional-usage name op-spec path-params query-params)))
        :query-heading "Query params (via {:query {...}}):"})

(fn build [path method op-spec]
  (render path method op-spec library-style))

{: build : render : param-extras}
