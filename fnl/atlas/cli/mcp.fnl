;; ABOUTME: The MCP server of atlas mcp: operations as tools with JSON Schema
;; ABOUTME: 2020-12 inputs, and JSON-RPC over stdio for modern and legacy clients.
(local json (require :atlas.json))

;; ---- schemas ----

;; keywords whose value is a schema, a list of schemas, or a map of them; any
;; other keyword is data (enum, example, default, …) and is copied as is
(local schema-keywords {:items true
                        :additionalItems true
                        :additionalProperties true
                        :contains true
                        :else true
                        :if true
                        :not true
                        :propertyNames true
                        :then true
                        :unevaluatedItems true
                        :unevaluatedProperties true})

(local schema-lists {:allOf true :anyOf true :oneOf true :prefixItems true})

(local schema-maps {:properties true
                    :patternProperties true
                    :dependentSchemas true
                    "$defs" true
                    :definitions true})

(fn openapi-30-keywords [out]
  "out with OpenAPI 3.0's nullable and boolean exclusive bounds written as
JSON Schema 2020-12 has them."
  (when (= out.nullable true)
    (when (= (type out.type) :string)
      (set out.type [out.type :null]))
    (when (json.array? out.enum)
      (table.insert out.enum json.null)))
  (set out.nullable nil)
  (each [_ [bound exclusive] (ipairs [[:minimum :exclusiveMinimum]
                                      [:maximum :exclusiveMaximum]])]
    (when (= (type (. out exclusive)) :boolean)
      (if (and (. out exclusive) (not= nil (. out bound)))
          (do
            (tset out exclusive (. out bound))
            (tset out bound nil))
          (tset out exclusive nil))))
  out)

(fn new-context []
  "Conversion state shared by the schemas of one tool: the $defs written for
recursive schemas, by schema."
  {:defs {} :ids {} :count 0})

(fn convert [schema openapi-30 ctx ancestors]
  (if (or (not= (type schema) :table) (= schema json.null)) schema
      (. ancestors schema)
      ;; a schema inside itself: a reference to its $defs entry
      (let [id (or (. ctx.ids schema)
                   (do
                     (set ctx.count (+ ctx.count 1))
                     (tset ctx.ids schema (.. "s" ctx.count))
                     (. ctx.ids schema)))]
        {"$ref" (.. "#/$defs/" id)})
      (let [out (setmetatable {} (getmetatable schema))
            sub #(convert $ openapi-30 ctx ancestors)]
        (tset ancestors schema true)
        (each [k v (pairs schema)]
          (tset out k (if (and (. schema-keywords k) (json.array? v))
                          (json.array (icollect [_ s (ipairs v)] (sub s)))
                          (. schema-keywords k)
                          (sub v)
                          (and (. schema-lists k) (= (type v) :table))
                          (json.array (icollect [_ s (ipairs v)] (sub s)))
                          (and (. schema-maps k) (= (type v) :table))
                          (collect [name s (pairs v)] name (sub s))
                          ;; data: copied, so the result never shares tables with
                          ;; the spec
                          (and (= (type v) :table) (not= v json.null))
                          (json.decode (json.encode v) true)
                          v)))
        (tset ancestors schema nil)
        (when openapi-30
          (openapi-30-keywords out))
        (let [id (. ctx.ids schema)]
          (when (and id (= nil (. ctx.defs id)))
            ;; a copy: the entry must not hold the $defs it is in
            (tset ctx.defs id (collect [k v (pairs out)] k v))))
        out)))

(fn json-schema [schema openapi-30 ?ctx]
  "schema (an OpenAPI schema with its refs resolved) as JSON Schema 2020-12,
the dialect of MCP tool schemas: OpenAPI 3.0's own keywords when openapi-30,
and recursion as references to $defs. With ?ctx (see new-context), the $defs
are left in it for the caller to place at the root of the document; without,
they are added to the result."
  (let [ctx (or ?ctx (new-context))
        out (convert schema openapi-30 ctx {})]
    (when (and (not ?ctx) (next ctx.defs) (= (type out) :table))
      (tset out "$defs" ctx.defs))
    out))

;; ---- tools ----

(local read-only-methods {:GET true :HEAD true :OPTIONS true})
(local destructive-methods {:DELETE true :PUT true :PATCH true})
(local idempotent-methods {:GET true
                           :HEAD true
                           :OPTIONS true
                           :PUT true
                           :DELETE true})

(fn param-schema [p]
  "A parameter's schema: its schema, or that of its content."
  (or p.schema (when (= (type p.content) :table)
                 (let [(_ media) (next p.content)]
                   (?. media :schema))) {}))

(fn tool-params [op opts]
  "The arguments of op's tool: [{:arg :in :name :schema :required
:description}], path parameters first; a name already taken (by another
parameter, or body) is prefixed with its location. Headers and query
parameters atlas adds itself (opts.supplied-headers, lower case, and
opts.supplied-query) are left out."
  (let [taken {}
        params []
        add (fn [p]
              (let [arg (if (. taken p.name) (.. p.in "." p.name) p.name)]
                (tset taken arg true)
                (table.insert params
                              {: arg
                               :in p.in
                               :name p.name
                               :schema (param-schema p)
                               :required (or p.required (= p.in :path))
                               :description p.description})))
        declared (or op.parameters [])
        supplied? (fn [p]
                    (or (and (= p.in :header)
                             (?. opts :supplied-headers (p.name:lower)))
                        (and (= p.in :query) (?. opts :supplied-query p.name))))]
    (when op.has-body
      (tset taken :body true))
    (each [_ name (ipairs op.path-params)]
      (add (or (accumulate [found nil _ p (ipairs declared) &until found]
                 (when (and (= p.in :path) (= p.name name)) p))
               {: name :in :path})))
    (each [_ location (ipairs [:query :header])]
      (each [_ p (ipairs declared)]
        (when (and (= p.in location) (not (supplied? p)))
          (add p))))
    params))

(fn annotations [method]
  {:readOnlyHint (= true (. read-only-methods method))
   :destructiveHint (= true (. destructive-methods method))
   :idempotentHint (= true (. idempotent-methods method))
   ;; the API is outside atlas
   :openWorldHint true})

(fn tool-description [op]
  (let [summary op.spec.summary
        description op.spec.description
        parts [(.. (op.method:upper) " " op.path)]]
    (each [_ text (ipairs [summary description])]
      (when (and (= (type text) :string) (not= text "")
                 (not= text (. parts (length parts))))
        (table.insert parts text)))
    (table.concat parts "\n\n")))

(fn tool [op opts]
  "The MCP tool definition of operation op. opts: {:openapi-30 bool
:supplied-headers {lower-case-name true} :supplied-query {name true}}"
  (let [ctx (new-context)
        properties {}
        required []]
    (each [_ p (ipairs (tool-params op opts))]
      (let [schema (json-schema p.schema opts.openapi-30 ctx)]
        (when (and p.description (= (type schema) :table)
                   (= nil schema.description))
          (set schema.description p.description))
        (tset properties p.arg schema)
        (when p.required
          (table.insert required p.arg))))
    (when op.has-body
      (tset properties :body
            (json-schema (or op.body-schema {}) opts.openapi-30 ctx))
      (when (?. op.spec :requestBody :required)
        (table.insert required :body)))
    (table.sort required)
    (let [input {:type :object : properties :additionalProperties false}]
      (when (next required)
        (set input.required required))
      (when (next ctx.defs)
        (tset input "$defs" ctx.defs))
      {:name op.name
       :title op.spec.summary
       :description (tool-description op)
       :inputSchema input
       :annotations (annotations (op.method:upper))})))

(fn workflow-tool [wf inputs-schema]
  "The MCP tool definition of Arazzo workflow wf, whose inputs (JSON Schema,
refs resolved) are inputs-schema."
  (let [parts [(.. "Arazzo workflow " wf.workflowId)]]
    (each [_ text (ipairs [wf.summary wf.description])]
      (when (and (= (type text) :string) (not= text ""))
        (table.insert parts text)))
    {:name (.. "workflow." (pick-values 1 (wf.workflowId:gsub "[^%w_.-]" "_")))
     :title wf.summary
     :description (table.concat parts "\n\n")
     :inputSchema (if (= (type inputs-schema) :table)
                      (json-schema inputs-schema false)
                      {:type :object :additionalProperties false})
     ;; what a workflow does is up to its steps
     :annotations {:readOnlyHint false
                   :destructiveHint true
                   :idempotentHint false
                   :openWorldHint true}}))

(fn request [op arguments ?opts]
  "The op.invoke request for a tool call's arguments."
  (when (or (not= (type arguments) :table) (= arguments json.null)
            (json.array? arguments))
    (error "arguments must be an object" 0))
  (let [by-arg (collect [_ p (ipairs (tool-params op (or ?opts {})))]
                 p.arg
                 p)
        req {:path {} :query {} :headers {}}]
    (each [arg v (pairs arguments)]
      (if (and (= arg :body) op.has-body) (set req.body v)
          (let [p (or (. by-arg arg) (error (.. "unknown argument: " arg) 0))]
            (match p.in
              :path (tset req.path p.name v)
              :query (tset req.query p.name v)
              :header (tset req.headers p.name v)))))
    {:path req.path
     :query (when (next req.query) req.query)
     :headers (when (next req.headers) req.headers)
     :body req.body}))

;; ---- protocol ----

(local modern-versions ["2026-07-28"])

;; protocol versions that open with initialize, the latest first
(local legacy-versions ["2025-11-25" "2025-06-18" "2025-03-26" "2024-11-05"])

(local meta-version "io.modelcontextprotocol/protocolVersion")
(local meta-capabilities "io.modelcontextprotocol/clientCapabilities")
(local meta-server-info "io.modelcontextprotocol/serverInfo")

(fn member? [list x]
  (accumulate [found false _ v (ipairs list) &until found]
    (= v x)))

(fn error-response [id code message ?data]
  {:jsonrpc "2.0"
   :id (if (= nil id) json.null id)
   :error {: code : message :data ?data}})

(fn handler [server]
  "A function answering one decoded JSON-RPC message: a response, or nil for
notifications. Requests carrying a modern protocol version in _meta are served
statelessly (2026-07-28); initialize opens the legacy protocol for the rest of
the process. server: {:tools [tool] :call (fn [name arguments] result)
:version :instructions}"
  (var legacy false)
  (let [by-name (collect [_ t (ipairs server.tools)] t.name t)
        server-info {:name "atlas" :version server.version}
        results {"server/discover" (fn [modern]
                                     (when modern
                                       {:supportedVersions (json.array modern-versions)
                                        :capabilities {:tools {}}
                                        :instructions server.instructions}))
                 "tools/list" #{:tools (json.array server.tools)}
                 "tools/call" (fn [_ params]
                                (if (. by-name params.name)
                                    (server.call params.name
                                                 (or params.arguments {}))
                                    (values nil -32602
                                            (.. "Unknown tool: "
                                                (tostring params.name)))))
                 :ping #{}}
        respond (fn [msg modern]
                  (let [params (if (= (type msg.params) :table) msg.params {})
                        result-fn (. results msg.method)
                        (result code message) (when result-fn
                                                (result-fn modern params))]
                    (if result
                        {:jsonrpc "2.0"
                         :id msg.id
                         :result (if modern
                                     (doto result
                                       (tset :resultType :complete)
                                       (tset :_meta
                                             {meta-server-info server-info}))
                                     result)}
                        code
                        (error-response msg.id code message)
                        (error-response msg.id -32601
                                        (.. "Method not found: " msg.method)))))]
    (fn [msg]
      (if (or (not= (type msg) :table) (json.array? msg)
              (and (not= (type msg.method) :string) (not= nil msg.id)))
          (error-response (when (= (type msg) :table) msg.id) -32600
                          "Invalid request")
          ;; notifications, and responses we never asked for
          (= nil msg.id)
          nil
          (let [meta (?. msg :params :_meta)
                version (when (= (type meta) :table) (. meta meta-version))]
            (if version
                (if (not (member? modern-versions version))
                    (error-response msg.id -32022
                                    "Unsupported protocol version"
                                    {:supported (json.array modern-versions)
                                     :requested version})
                    (= nil (. meta meta-capabilities))
                    (error-response msg.id -32602
                                    (.. "missing _meta " meta-capabilities))
                    (respond msg true))
                (= msg.method :initialize)
                (let [asked (?. msg :params :protocolVersion)]
                  (set legacy true)
                  {:jsonrpc "2.0"
                   :id msg.id
                   :result {:protocolVersion (if (member? legacy-versions asked)
                                                 asked
                                                 (. legacy-versions 1))
                            :capabilities {:tools {}}
                            :serverInfo server-info
                            :instructions server.instructions}})
                (or legacy (= msg.method :ping))
                (respond msg false)
                (error-response msg.id -32602
                                (.. "missing _meta " meta-version
                                    " (atlas speaks "
                                    (table.concat modern-versions ", ")
                                    ", or initialize for "
                                    (table.concat legacy-versions ", ") ")"))))))))

(fn serve [handle read-line write-line]
  "Answer the newline-delimited JSON-RPC messages read-line returns, until it
returns nil, writing each response with write-line (one line, no newline)."
  (var line (read-line))
  (while line
    (when (line:match "%S")
      (let [(ok msg) (pcall json.decode line true)
            (handled response) (if ok (pcall handle msg) (values true nil))
            response (if (not ok) (error-response nil -32700 "Parse error")
                         handled response
                         (error-response (when (= (type msg) :table) msg.id)
                                         -32603 (tostring response)))]
        (when response
          (write-line (json.encode response)))))
    (set line (read-line))))

{: json-schema : tool : workflow-tool : request : handler : serve}
