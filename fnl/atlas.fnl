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
                   :content-type content-type
                   :fnl/docstring (doc.build path method op-spec)
                   :has-body? has-body?
                   :invoke invoke
                   :method method
                   :n-path n-path
                   :operation-id op-spec.operationId
                   :parameters op-spec.parameters
                   :path path
                   :path-params param-names
                   :summary (op-summary op-spec)
                   :url-for url-for}
                  {:__call (fn [_ ...] (call-positional ...))})))

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
?opts — {:base-url \"https://...\" :server-index n :server-vars {:name value} :headers {} :http-fn custom-fn}
base-url defaults to schema.servers[1].url with :server-vars applied"
  (let [source-url (or (when (= (type schema) :string)
                         schema) (?. ?opts :source-url))
        schema (if (= (type schema) :string)
                   (load-schema schema)
                   schema)
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

{:client client :load-schema load-schema :servers servers}
