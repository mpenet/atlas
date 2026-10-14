;; ABOUTME: Builds callable API clients from OpenAPI 3.x schemas at runtime;
;; ABOUTME: each operation is invocable positionally or with a structured request.
(local util (require :atlas.util))

(local negotiate (require :atlas.negotiate))

(local doc (require :atlas.doc))

(local yaml (require :atlas.yaml))

(local http (require :atlas.http))

(fn load-schema [path ?ssl ?headers]
  "Load an OpenAPI schema (JSON or YAML) from a local file path or http(s):// URL."
  (let [content (http.fetch-text path {:headers ?headers :ssl ?ssl})
        (ok parsed) (pcall yaml.decode content)]
    (assert ok (string.format "failed to parse schema from '%s': %s" path
                              (tostring parsed)))
    parsed))

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

(fn make-operation [client-opts root-schema path path-item method op-spec]
  (let [op-spec (doto (util.deref-deep root-schema op-spec)
                  (tset :parameters
                        (util.merge-parameters (util.deref-deep root-schema
                                                                path-item.parameters)
                                               (util.deref-deep root-schema
                                                                op-spec.parameters))))
        param-names (util.extract-path-params path)
        n-path (length param-names)
        has-body? (not= nil op-spec.requestBody)
        content-type (negotiate.pick-content-type op-spec)
        negotiated {:accept (negotiate.pick-accept op-spec)
                    :content-type content-type}
        base-url-for (fn [req]
                       (.. client-opts.base-url
                           (util.resolve-path path (or req.path {}))))
        url-for (fn [?req]
                  "Full request URL for {:path {name v} :query {}}."
                  (let [req (or ?req {})]
                    (util.append-query (base-url-for req) (or req.query {}))))
        invoke (fn [?req]
                 "Call the operation with {:path {name v} :query {} :headers {} :body v :timeout n}."
                 (let [req (or ?req {})]
                   (client-opts.http-fn {:body req.body
                                         :headers (merge-headers negotiated
                                                                 (or client-opts.headers
                                                                     {})
                                                                 (or req.headers
                                                                     {}))
                                         :method (method:upper)
                                         :query req.query
                                         :ssl client-opts.ssl
                                         :timeout (or req.timeout
                                                      client-opts.timeout)
                                         :url (base-url-for req)})))
        call-positional (fn [...]
                          (let [args [...]
                                opts (or (. args (+ n-path (if has-body? 2 1)))
                                         {})]
                            (invoke {:path (collect [i name (ipairs param-names)]
                                             name
                                             (. args i))
                                     :body (when has-body?
                                             (. args (+ n-path 1)))
                                     :query opts.query
                                     :headers opts.headers
                                     :timeout opts.timeout})))]
    (setmetatable {:body-schema (?. op-spec :requestBody :content content-type
                                    :schema)
                   :cli/help (doc.build-cli path method op-spec)
                   :fnl/docstring (doc.build path method op-spec)
                   :has-body? has-body?
                   :invoke invoke
                   :method method
                   :n-path n-path
                   :operation-id op-spec.operationId
                   :path path
                   :path-params param-names
                   :summary (op-summary op-spec)
                   :url-for url-for}
                  {:__call (fn [_ ...] (call-positional ...))})))

(fn client [schema ?opts]
  "Build an API client from an OpenAPI 3.x schema.

schema — parsed schema table, local file path, or http(s):// URL
?opts — {:base-url \"https://...\" :headers {} :http-fn custom-fn}
base-url defaults to schema.servers[1].url"
  (let [source-url (or (when (= (type schema) :string)
                         schema) (?. ?opts :source-url))
        schema (if (= (type schema) :string)
                   (load-schema schema)
                   schema)
        server (and schema.servers (. schema.servers 1))
        server-url (when server
                     (var u server.url)
                     (each [k v (pairs (or server.variables {}))]
                       (set u
                            (util.replace-all u (.. "{" k "}")
                                              (tostring v.default))))
                     u)
        base-url (or (?. ?opts :base-url)
                     (when (and server-url (server-url:match "^https?://"))
                       server-url)
                     (when (and source-url server-url (server-url:match "^/"))
                       (let [(origin) (source-url:match "^(https?://[^/]+)")]
                         (.. origin server-url)))
                     (error "no base-url: schema servers URL is missing or unresolvable, pass :base-url in opts"))
        client-opts {:base-url base-url
                     :headers (or (?. ?opts :headers) {})
                     :http-fn (or (?. ?opts :http-fn) http.request)
                     :ssl (?. ?opts :ssl)
                     :timeout (?. ?opts :timeout)}
        client {}]
    (each [path methods (pairs (or schema.paths {}))]
      (each [method op-spec (pairs methods)]
        (when (and (= (type op-spec) :table) op-spec.operationId)
          (tset client (util.camel->kebab op-spec.operationId)
                (make-operation client-opts schema path methods method op-spec)))))
    client))

{:client client :load-schema load-schema}
