(local util (require :atlas.util))
(local negotiate (require :atlas.negotiate))
(local doc (require :atlas.doc))
(local json (require :lunajson))
(local http (require :atlas.http))
(local ltn12 (require :ltn12))
(local socket-http (require :socket.http))
(local https (require :ssl.https))

(fn load-schema [path ?ssl ?headers]
  "Load an OpenAPI schema from a local file path or http(s):// URL."
  (let [content (if (path:match "^https?://")
                    (let [requester (if (path:match "^https://") https socket-http)
                          body-out []
                          req (if (and ?ssl (path:match "^https://"))
                                  (collect [k v (pairs ?ssl)] k v)
                                  {})]
                      (tset req :url path)
                      (tset req :method :GET)
                      (tset req :headers (or ?headers {}))
                      (tset req :sink (ltn12.sink.table body-out))
                      (let [(ok code) (requester.request req)]
                        (assert ok (string.format "failed to fetch schema from %s: %s" path (tostring code)))
                        (assert (and (>= code 200) (< code 300))
                                (string.format "HTTP %s fetching schema from %s" code path))
                        (table.concat body-out)))
                    (let [(f err) (io.open path :r)]
                      (assert f (string.format "failed to open schema file '%s': %s" path (tostring err)))
                      (let [c (f:read :*a)]
                        (f:close)
                        c)))
        (ok parsed) (pcall json.decode content)]
    (assert ok (string.format "failed to parse schema JSON from '%s': %s" path (tostring parsed)))
    parsed))

(fn make-operation [client-opts path method op-spec]
  (let [param-names (util.extract-path-params path)
        n-path (length param-names)
        has-body? (not= nil op-spec.requestBody)
        fixed-headers (collect [k v (pairs {:content-type (negotiate.pick-content-type op-spec)
                                            :accept (negotiate.pick-accept op-spec)})]
                        (when v (values k v)))
        n-opts (+ n-path (if has-body? 2 1))
        f (fn [...]
            (let [args [...]
                  url (.. client-opts.base-url (util.resolve-path path args))
                  body (when has-body? (. args (+ n-path 1)))
                  opts (. args n-opts)
                  headers (collect [k v (pairs (or client-opts.headers {}))] k v)]
              (each [k v (pairs (or (?. opts :headers) {}))]
                (tset headers k v))
              (each [k v (pairs fixed-headers)]
                (tset headers k v))
              (client-opts.http-fn {:method (method:upper)
                                    :url url
                                    :query (?. opts :query)
                                    :body body
                                    :headers headers
                                    :timeout (or (?. opts :timeout) client-opts.timeout)
                                    :ssl client-opts.ssl})))]
    (setmetatable {:fnl/docstring (doc.build path method op-spec)
                   :has-body? has-body?
                   :n-path n-path}
                  {:__call (fn [_ ...] (f ...))})))

(fn client [schema ?opts]
  "Build an API client from an OpenAPI 3.x schema.

  schema — parsed schema table, local file path, or http(s):// URL
  ?opts  — {:base-url \"https://...\" :headers {} :http-fn custom-fn}
           base-url defaults to schema.servers[1].url"
  (let [source-url (or (when (= (type schema) :string) schema)
                       (?. ?opts :source-url))
        schema (if (= (type schema) :string) (load-schema schema) schema)
        server (and schema.servers (. schema.servers 1))
        server-url (when server
                     (var u server.url)
                     (each [k v (pairs (or server.variables {}))]
                       (set u (u:gsub (.. "{" k "}") v.default)))
                     u)
        base-url (or (?. ?opts :base-url)
                     (when (and server-url (server-url:match "^https?://"))
                       server-url)
                     (when (and source-url server-url (server-url:match "^/"))
                       (let [(origin) (source-url:match "^(https?://[^/]+)")]
                         (.. origin server-url)))
                     (error "no base-url: schema servers URL is missing or unresolvable, pass :base-url in opts"))
        client-opts {:base-url base-url
                     :http-fn (or (?. ?opts :http-fn) http.request)
                     :headers (or (?. ?opts :headers) {})
                     :timeout (?. ?opts :timeout)
                     :ssl (?. ?opts :ssl)}
        client {}]
    (each [path methods (pairs (or schema.paths {}))]
      (each [method op-spec (pairs methods)]
        (when (and (= (type op-spec) :table) op-spec.operationId)
          (tset client
                (util.camel->kebab op-spec.operationId)
                (make-operation client-opts path method op-spec)))))
    client))

{: client : load-schema}
