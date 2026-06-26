(local util (require :anis.util))

(fn params-of-kind [op-spec kind]
  (icollect [_ p (ipairs (or op-spec.parameters []))]
    (when (= p.in kind) p)))

(fn param-type [p]
  (or (?. p :schema :type) :any))

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
        (add (string.format "  %-14s %s%s"
                            p.name
                            (param-type p)
                            (if p.description (.. " — " p.description) "")))))
    (when (> (length query-params) 0)
      (add "\nQuery params:")
      (each [_ p (ipairs query-params)]
        (add (string.format "  %-14s %s%s%s"
                            p.name
                            (param-type p)
                            (if p.required " [required]" "")
                            (if p.description (.. " — " p.description) "")))))
    (when op-spec.requestBody
      (add (string.format "\nBody: %s%s"
                          (if op-spec.requestBody.required :required :optional)
                          (if op-spec.requestBody.description
                              (.. " — " op-spec.requestBody.description) ""))))
    (add "\nResponses:")
    (each [code resp (pairs (or op-spec.responses {}))]
      (add (string.format "  %-6s %s" (tostring code) (or resp.description ""))))
    (table.concat lines "\n")))

{: build}
