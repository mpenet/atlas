;; ABOUTME: Renders human-readable help for an operation, in CLI or library form.
;; ABOUTME: The text backs --help in the CLI and the docstring of library ops.
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

(fn param-type [p]
  (or (?. p :schema :type) :any))

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
    (add (.. "\nUsage: " (style.usage op-spec path-params query-params)))
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
          (each [name prop (pairs bschema.properties)]
            (add (string.format "  %-16s %s%s%s" name (or prop.type :any)
                                (if (. bschema.required name) " [required]" "")
                                (if prop.description
                                    (.. " — " prop.description)
                                    "")))))))
    (add "\nResponses:")
    (each [code resp (pairs (or op-spec.responses {}))]
      (add (string.format "  %-6s %s" (tostring code) (or resp.description ""))))
    (table.concat lines "\n")))

(local cli-style
       {:usage (fn [op-spec path-params query-params]
                 (let [parts [(util.camel->kebab op-spec.operationId)]]
                   (each [_ p (ipairs path-params)]
                     (table.insert parts (.. "<" p.name ">")))
                   (when op-spec.requestBody
                     (table.insert parts "[-d JSON|@file|@-]"))
                   (when (> (length query-params) 0)
                     (table.insert parts "[--q.KEY=VAL ...]"))
                   (.. "atlas op <profile-or-schema> " (table.concat parts " "))))
        :query-heading "Query params (--q.KEY=VAL):"
        :body-hint "  Use -d JSON, --body=@file, --body=@- for stdin, or --b.KEY=VAL for individual fields"})

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
       {:usage (fn [op-spec path-params query-params]
                 (let [name (util.camel->kebab op-spec.operationId)]
                   (.. (invoke-usage name op-spec path-params query-params)
                       "\n       "
                       (positional-usage name op-spec path-params query-params))))
        :query-heading "Query params (via {:query {...}}):"})

(fn build-cli [path method op-spec]
  (render path method op-spec cli-style))

(fn build [path method op-spec]
  (render path method op-spec library-style))

(fn step-target [step]
  "What a workflow step calls, for display."
  (if step.operationId (tostring step.operationId)
      step.workflowId (.. "workflow " step.workflowId)
      step.operationPath (let [ptr (or (step.operationPath:match "#/paths/(.+)$")
                                       "")
                               (path method) (ptr:match "^(.+)/([^/]+)$")]
                           (if path
                               (.. (method:upper) " "
                                   (util.unescape-pointer path))
                               step.operationPath))
      "?"))

(fn build-workflow [wf inputs-schema positional]
  "Help text for an Arazzo workflow. inputs-schema is the workflow's resolved
inputs JSON Schema; positional lists inputs that may be passed positionally."
  (let [lines []
        add #(table.insert lines $)
        required (collect [_ r (ipairs (or (?. inputs-schema :required) []))]
                   r
                   true)
        props (or (?. inputs-schema :properties) {})
        names (icollect [name (pairs props)] name)]
    (table.sort names (fn [a b]
                        (if (= (. required a) (. required b)) (< a b)
                            (= true (. required a)))))
    (add wf.workflowId)
    (when (and wf.summary (not= wf.summary "")) (add (.. "\n" wf.summary)))
    (when (and wf.description (not= wf.description "")
               (not= wf.description wf.summary))
      (add wf.description))
    (add (.. "\nUsage: atlas az <name-or-file> " wf.workflowId
             (table.concat (icollect [_ n (ipairs positional)] (.. " <" n ">")))
             " [-i KEY=VAL ...]"))
    (if (= 0 (length names))
        (add "\nInputs: none")
        (do
          (add "\nInputs:")
          (each [_ name (ipairs names)]
            (let [prop (. props name)]
              (add (string.format "  %-16s %s%s" name (or prop.type :any)
                                  (param-extras {:schema prop
                                                 :description prop.description}
                                                (. required name))))))))
    (let [steps (or wf.steps [])
          width (accumulate [w 0 _ s (ipairs steps)]
                  (math.max w (length (tostring s.stepId))))]
      (when (> (length steps) 0)
        (add "\nSteps:")
        (each [i step (ipairs steps)]
          (add (string.format (.. "  %d. %-" (+ width 2) "s %s") i
                              (tostring step.stepId) (step-target step))))))
    (table.concat lines "\n")))

{: build : build-cli : build-workflow}
