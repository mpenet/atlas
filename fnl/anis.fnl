(local util (require :anis.util))
(local negotiate (require :anis.negotiate))
(local doc (require :anis.doc))
(local json (require :lunajson))
(local http (require :anis.http))
(local ltn12 (require :ltn12))
(local socket-http (require :socket.http))
(local https (require :ssl.https))

(fn load-schema [path]
  "Load an OpenAPI schema from a local file path or http(s):// URL."
  (let [content (if (path:match "^https?://")
                    (let [requester (if (path:match "^https://") https socket-http)
                          body-out []
                          (ok code) (requester.request {:url path
                                                        :method :GET
                                                        :sink (ltn12.sink.table body-out)})]
                      (assert ok (tostring code))
                      (assert (and (>= code 200) (< code 300))
                              (string.format "HTTP %s fetching schema from %s" code path))
                      (table.concat body-out))
                    (let [f (assert (io.open path :r))
                          c (f:read :*a)]
                      (f:close)
                      c))]
    (json.decode content)))

(fn make-operation [client path method op-spec]
  (let [param-names (util.extract-path-params path)
        n-path (length param-names)
        has-body? (not= nil op-spec.requestBody)
        ct (negotiate.pick-content-type op-spec)
        accept (negotiate.pick-accept op-spec)
        n-opts (+ n-path (if has-body? 2 1))
        f (fn [...]
            (let [args [...]
                  url (.. client.base-url (util.resolve-path path args))
                  body (when has-body? (. args (+ n-path 1)))
                  opts (. args n-opts)
                  headers (collect [k v (pairs (or client.headers {}))] k v)]
              (each [k v (pairs (or (?. opts :headers) {}))]
                (tset headers k v))
              (when ct (tset headers :content-type ct))
              (when accept (tset headers :accept accept))
              (client.http-fn {:method (method:upper)
                               :url url
                               :query (?. opts :query)
                               :body body
                               :headers headers
                               :timeout (?. opts :timeout)})))]
    (setmetatable {:fnl/docstring (doc.build path method op-spec)}
                  {:__call (fn [_ ...] (f ...))})))

(fn client [schema ?opts]
  "Build an API client from an OpenAPI 3.x schema.

  schema — parsed schema table, local file path, or http(s):// URL
  ?opts  — {:base-url \"https://...\" :headers {} :http-fn custom-fn}
           base-url defaults to schema.servers[1].url"
  (let [source-url (when (= (type schema) :string) schema)
        schema (if source-url (load-schema source-url) schema)
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
        client {:base-url base-url
                :http-fn (or (?. ?opts :http-fn) http.request)
                :headers (or (?. ?opts :headers) {})}]
    (each [path methods (pairs schema.paths)]
      (each [method op-spec (pairs methods)]
        (when (and (= (type op-spec) :table) op-spec.operationId)
          (tset client
                (util.camel->kebab op-spec.operationId)
                (make-operation client path method op-spec)))))
    client))

{: client}
