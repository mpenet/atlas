(local util (require :atlas.util))

(fn params-of-kind [op-spec kind]
  (icollect [_ p (ipairs (or op-spec.parameters []))]
    (when (= p.in kind) p)))

(fn param-type [p]
  (or (?. p :schema :type) :any))

(fn param-extras [p required?]
  (let [parts []]
    (when required? (table.insert parts "[required]"))
    (when (?. p :schema :enum)
      (table.insert parts (.. "[" (table.concat p.schema.enum "|") "]")))
    (when (?. p :schema :default)
      (table.insert parts (.. "(default: " (tostring p.schema.default) ")")))
    (when p.description
      (table.insert parts (.. "— " p.description)))
    (if (> (length parts) 0) (.. " " (table.concat parts " ")) "")))

(fn body-schema [request-body]
  (let [content request-body.content
        schema (or (?. content :application/json :schema)
                   (?. content :application/x-www-form-urlencoded :schema)
                   (let [(k) (next (or content {}))]
                     (when k (?. content k :schema))))]
    (when (and schema schema.properties)
      (let [required-set {}]
        (each [_ r (ipairs (or schema.required []))]
          (tset required-set r true))
        {:properties schema.properties :required required-set}))))

(fn build-cli [path method op-spec]
  (let [lines []
        add #(table.insert lines $)
        path-params (params-of-kind op-spec :path)
        query-params (params-of-kind op-spec :query)
        has-body? (not= nil op-spec.requestBody)]
    (add (string.format "%s %s" (method:upper) path))
    (when op-spec.summary
      (add (.. "\n" op-spec.summary)))
    (when (and op-spec.description
               (not= op-spec.description op-spec.summary))
      (add op-spec.description))
    (let [parts [(util.camel->kebab op-spec.operationId)]]
      (each [_ p (ipairs path-params)]
        (table.insert parts (.. "<" p.name ">")))
      (when has-body? (table.insert parts "[-d JSON|@file|@-]"))
      (when (> (length query-params) 0) (table.insert parts "[--query.KEY=VAL ...]"))
      (add (string.format "\nUsage: atlas <profile-or-schema> %s" (table.concat parts " "))))
    (when (> (length path-params) 0)
      (add "\nPath params:")
      (each [_ p (ipairs path-params)]
        (add (string.format "  %-16s %s%s" p.name (param-type p) (param-extras p true)))))
    (when (> (length query-params) 0)
      (add "\nQuery params (--query.KEY=VAL):")
      (each [_ p (ipairs query-params)]
        (add (string.format "  %-16s %s%s" p.name (param-type p) (param-extras p p.required)))))
    (when op-spec.requestBody
      (let [rb op-spec.requestBody
            bschema (body-schema rb)]
        (add (string.format "\nBody: %s%s"
                            (if rb.required :required :optional)
                            (if rb.description (.. " — " rb.description) "")))
        (add "  Use -d JSON, --body=@file, --body=@- for stdin, or --body.KEY=VAL for individual fields")
        (when bschema
          (each [name prop (pairs bschema.properties)]
            (add (string.format "  %-16s %s%s%s"
                                name
                                (or prop.type :any)
                                (if (. bschema.required name) " [required]" "")
                                (if prop.description (.. " — " prop.description) "")))))))
    (add "\nResponses:")
    (each [code resp (pairs (or op-spec.responses {}))]
      (add (string.format "  %-6s %s" (tostring code) (or resp.description ""))))
    (table.concat lines "\n")))

(fn build [path method op-spec]
  (let [lines []
        add #(table.insert lines $)
        path-params (params-of-kind op-spec :path)
        query-params (params-of-kind op-spec :query)
        has-body? (not= nil op-spec.requestBody)]
    (add (string.format "%s %s" (method:upper) path))
    (when op-spec.summary
      (add (.. "\n" op-spec.summary)))
    (when (and op-spec.description
               (not= op-spec.description op-spec.summary))
      (add op-spec.description))
    (let [sig []]
      (each [_ p (ipairs path-params)] (table.insert sig p.name))
      (when has-body? (table.insert sig :body))
      (when (> (length query-params) 0) (table.insert sig :?opts))
      (add (string.format "\nUsage: (%s %s)"
                          (util.camel->kebab op-spec.operationId)
                          (table.concat sig " "))))
    (when (> (length path-params) 0)
      (add "\nPath params:")
      (each [_ p (ipairs path-params)]
        (add (string.format "  %-16s %s%s"
                            p.name
                            (param-type p)
                            (param-extras p true)))))
    (when (> (length query-params) 0)
      (add "\nQuery params (via {:query {...}}):")
      (each [_ p (ipairs query-params)]
        (add (string.format "  %-16s %s%s"
                            p.name
                            (param-type p)
                            (param-extras p p.required)))))
    (when op-spec.requestBody
      (let [rb op-spec.requestBody
            bschema (body-schema rb)]
        (add (string.format "\nBody: %s%s"
                            (if rb.required :required :optional)
                            (if rb.description (.. " — " rb.description) "")))
        (when bschema
          (each [name prop (pairs bschema.properties)]
            (add (string.format "  %-16s %s%s%s"
                                name
                                (or prop.type :any)
                                (if (. bschema.required name) " [required]" "")
                                (if prop.description (.. " — " prop.description) "")))))))
    (add "\nResponses:")
    (each [code resp (pairs (or op-spec.responses {}))]
      (add (string.format "  %-6s %s" (tostring code) (or resp.description ""))))
    (table.concat lines "\n")))

{: build : build-cli}
