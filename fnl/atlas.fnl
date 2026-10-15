;; ABOUTME: Builds callable API clients from OpenAPI 3.x schemas at runtime;
;; ABOUTME: each operation is invocable positionally or with a structured request.
(local util (require :atlas.util))
(local refs (require :atlas.refs))
(local json (require :atlas.json))

(local negotiate (require :atlas.negotiate))

(local doc (require :atlas.doc))

(local yaml (require :atlas.yaml))

(local http (require :atlas.http))

(fn parse-schema [text location]
  "The document in text (JSON or YAML), which must be a mapping; location
names it in errors."
  (let [(ok parsed) (pcall yaml.decode text)]
    (assert ok
            (string.format "failed to parse schema from '%s': %s"
                           (util.redact-url location) (tostring parsed)))
    (assert (and (= (type parsed) :table) (not= parsed json.null)
                 (not (json.array? parsed)))
            (string.format "'%s' is not an OpenAPI document"
                           (util.redact-url location)))
    parsed))

(fn load-schema [path ?opts]
  "Load an OpenAPI schema (JSON or YAML) from a local file path or http(s):// URL.
?opts — {:ssl tls-options :headers {} :timeout seconds} for fetching a URL"
  (parse-schema (http.fetch-text path
                                 {:headers (?. ?opts :headers)
                                  :ssl (?. ?opts :ssl)
                                  :timeout (?. ?opts :timeout)})
                path))

(fn merge-headers [...]
  "Merge header tables left to right; names are lowercased so later
tables override earlier ones regardless of case."
  (let [out {}]
    (each [_ hs (ipairs [...])]
      (each [k v (pairs hs)]
        (tset out (k:lower) v)))
    out))

(fn op-summary [op-spec]
  (let [s op-spec.summary
        d op-spec.description]
    (if (and s (not= s "")) s
        (and d (not= d "")) d
        nil)))

(fn positional-request [op args]
  "The invoke request for a positional call: path params in template order,
then the body when the operation has one, then an opts table."
  (let [n-path (length op.path-params)
        opts (or (. args (+ n-path (if op.has-body 2 1))) {})]
    {:path (collect [i name (ipairs op.path-params)] name (. args i))
     :body (when op.has-body (. args (+ n-path 1)))
     :query opts.query
     :headers opts.headers
     :timeout opts.timeout}))

(local operation-mt {:__call (fn [op ...]
                               (op.invoke (positional-request op [...])))
                     ;; the REPL docstring is rendered on first access only
                     :__index (fn [op key]
                                (when (= key :fnl/docstring)
                                  (let [text (doc.build op.path op.method
                                                        op.spec)]
                                    (rawset op key text)
                                    text)))})

(fn operation-url [base-url path req]
  ;; servers often end in / while paths start with one
  (.. (pick-values 1 (base-url:gsub "/+$" ""))
      (util.resolve-path path (or req.path {}))))

(fn make-operation [client-opts name path path-item method op-spec]
  (let [op-spec (doto (collect [k v (pairs op-spec)]
                        k
                        v)
                  (tset :parameters
                        (util.merge-parameters path-item.parameters
                                               op-spec.parameters)))
        content-type (negotiate.pick-content-type op-spec)
        negotiated {:accept (negotiate.pick-accept op-spec)
                    :content-type content-type}
        ;; how each declared query parameter is serialized
        query-styles (collect [_ p (ipairs (or op-spec.parameters []))]
                       (when (= p.in :query)
                         (values p.name {:style p.style :explode p.explode})))
        url-for (fn [?req]
                  "Full request URL for {:path {name v} :query {}}."
                  (let [req (or ?req {})]
                    (util.append-query (operation-url client-opts.base-url path
                                                      req)
                                       (or req.query {}) query-styles)))
        invoke (fn [?req]
                 "Call the operation with {:path {name v} :query {} :headers {} :body v :timeout n}."
                 (let [req (or ?req {})]
                   (client-opts.http-fn {:body req.body
                                         ;; no Content-Type without a body
                                         :headers (merge-headers (if (= nil
                                                                        req.body)
                                                                     {:accept negotiated.accept}
                                                                     negotiated)
                                                                 (or client-opts.headers
                                                                     {})
                                                                 (or req.headers
                                                                     {}))
                                         :method (method:upper)
                                         :query req.query
                                         : query-styles
                                         :ssl client-opts.ssl
                                         :timeout (or req.timeout
                                                      client-opts.timeout)
                                         :url (operation-url client-opts.base-url
                                                             path req)})))
        param-names (util.extract-path-params path)]
    (setmetatable {:body-schema (?. op-spec :requestBody :content content-type
                                    :schema)
                   :content-type content-type
                   :has-body (not= nil op-spec.requestBody)
                   : invoke
                   : method
                   : name
                   :operation-id op-spec.operationId
                   :parameters op-spec.parameters
                   : path
                   :path-params param-names
                   :spec op-spec
                   :summary (op-summary op-spec)
                   : url-for} operation-mt)))

(local http-methods {:get true
                     :put true
                     :post true
                     :delete true
                     :options true
                     :head true
                     :patch true
                     :trace true})

(fn schema-operations [schema deref]
  "The schema's operations as [{:path :path-item :method :op-spec}], with
their refs resolved, in path then method order, so that naming them is
deterministic."
  (let [paths (doto (icollect [path item (pairs (or schema.paths {}))]
                      ;; extensions (x-...) may hold any value
                      (when (= (type item) :table) path))
                (table.sort))
        entries []]
    (each [_ path (ipairs paths)]
      (let [path-item (deref (. schema.paths path))
            methods (doto (icollect [method op-spec (pairs path-item)]
                            (when (and (. http-methods method)
                                       (= (type op-spec) :table))
                              method))
                      (table.sort))]
        (each [_ method (ipairs methods)]
          (table.insert entries
                        {: path
                         : path-item
                         : method
                         :op-spec (. path-item method)}))))
    entries))

(fn ref-load-opts [load-opts source-url location]
  "Loader options for a document a $ref points to: the spec's headers and
credentials only go to the spec's own origin."
  (let [origin (when source-url (util.origin source-url))]
    (if (and origin (= origin (util.origin location)))
        load-opts
        {:ssl load-opts.ssl :timeout load-opts.timeout :credentials false})))

(fn sorted [items]
  (doto (icollect [_ x (ipairs items)] x)
    table.sort))

(fn expand-server-url [server overrides]
  "Server URL with {variables} replaced by overrides or their defaults.
Overrides must name declared variables and respect their enum."
  (let [variables (or server.variables {})]
    (each [name value (pairs overrides)]
      (let [spec (. variables name)]
        (when (not spec)
          (error (string.format "unknown server variable '%s' (known: %s)" name
                                (table.concat (sorted (icollect [k (pairs variables)]
                                                        k))
                                              ", ")) 0))
        (when (and spec.enum
                   (not (accumulate [found false _ allowed (ipairs spec.enum)
                                     &until found]
                          (= (tostring allowed) (tostring value)))))
          (error (string.format "server variable %s: '%s' is not one of %s"
                                name (tostring value)
                                (table.concat spec.enum ", "))
                 0))))
    (accumulate [url server.url name spec (pairs variables)]
      (util.replace-all url (.. "{" name "}")
                        (tostring (or (. overrides name) spec.default))))))

(fn servers [schema]
  "The schema's servers as [{:url :description :variables {name {:default :enum :description}}}]."
  (icollect [_ s (ipairs (or schema.servers []))]
    {:url s.url
     :description s.description
     :variables (collect [name v (pairs (or s.variables {}))]
                  name
                  {:default v.default :enum v.enum :description v.description})}))

(fn client [schema ?opts]
  "Build an API client from an OpenAPI 3.x schema.

schema — parsed schema table, local file path, or http(s):// URL
?opts — {:base-url \"https://...\" :server-index n :server-vars {:name value} :headers {} :http-fn custom-fn
         :load-schema (fn [location {:ssl :headers}]) to fetch schema documents yourself}
base-url defaults to schema.servers[1].url with :server-vars applied"
  (let [source-url (or (when (= (type schema) :string)
                         schema) (?. ?opts :source-url))
        load-opts {:ssl (?. ?opts :ssl)
                   :headers (?. ?opts :headers)
                   :timeout (?. ?opts :timeout)}
        load (or (?. ?opts :load-schema) load-schema)
        schema (if (= (type schema) :string)
                   (load schema load-opts)
                   schema)
        deref (refs.resolver schema
                             {:base source-url
                              :load #(load $
                                           (ref-load-opts load-opts source-url
                                                          $))})
        servers (or schema.servers [])
        index (or (?. ?opts :server-index) 1)
        server (when (and (not (?. ?opts :base-url)) (> (length servers) 0))
                 (assert (. servers index)
                         (string.format "server index %s out of range (schema has %d servers)"
                                        (tostring index) (length servers)))
                 (. servers index))
        server-url (when (and server (not (?. ?opts :base-url)))
                     (expand-server-url server (or (?. ?opts :server-vars) {})))
        base-url (or (?. ?opts :base-url)
                     (when (and server-url (server-url:match "^https?://"))
                       server-url)
                     (when (and source-url server-url (server-url:match "^/"))
                       (let [(origin) (source-url:match "^(https?://[^/]+)")]
                         (when origin
                           (.. origin server-url))))
                     (error "no base-url: schema servers URL is missing or unresolvable, pass :base-url in opts"))
        client-opts {:base-url base-url
                     :headers (or (?. ?opts :headers) {})
                     :http-fn (or (?. ?opts :http-fn) http.request)
                     :ssl (?. ?opts :ssl)
                     :timeout (?. ?opts :timeout)}
        client {}
        entries (schema-operations schema deref)
        add (fn [name {: path : path-item : method : op-spec}]
              (tset client name
                    (make-operation client-opts name path path-item method
                                    op-spec)))
        unnamed (icollect [_ entry (ipairs entries)]
                  (let [name (when entry.op-spec.operationId
                               (util.operation-name entry.method entry.path
                                                    entry.op-spec))]
                    (if (and name (= nil (. client name)))
                        (add name entry)
                        entry)))]
    ;; operations without an operationId, or whose name was taken, are named
    ;; after their method and path
    (each [_ entry (ipairs unnamed)]
      (let [base (util.operation-name entry.method entry.path {})]
        (var name base)
        (var n 1)
        (while (not= nil (. client name))
          (set n (+ n 1))
          (set name (.. base "-" n)))
        (add name entry)))
    client))

{:version "1.0.0-beta1"
 :client client
 :load-schema load-schema
 :parse-schema parse-schema
 :servers servers
 :server-url expand-server-url}
