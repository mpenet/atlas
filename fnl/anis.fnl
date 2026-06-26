(local util (require :anis.util))
(local negotiate (require :anis.negotiate))
(local doc (require :anis.doc))
(local json (require :lunajson))
(local http (require :anis.http))
(local ltn12 (require :ltn12))
(local socket-http (require :socket.http))
(local https (require :ssl.https))

(fn make-operation [path method op-spec]
  (let [param-names (util.extract-path-params path)
        n-path (length param-names)
        has-body? (not= nil op-spec.requestBody)
        ct (negotiate.pick-content-type op-spec)
        accept (negotiate.pick-accept op-spec)
        f (fn [client ...]
            (let [args [...]
                  url (.. client.base-url (util.resolve-path path args))
                  body (when has-body? (. args (+ n-path 1)))
                  query (. args (+ n-path (if has-body? 2 1)))
                  headers (collect [k v (pairs (or client.headers {}))] k v)]
              (when ct (tset headers :content-type ct))
              (when accept (tset headers :accept accept))
              (client.http-fn {:method (method:upper)
                               :url url
                               :query query
                               :body body
                               :headers headers})))]
    (setmetatable f {:fnl/docstring (doc.build path method op-spec)})))

(fn client [schema ?opts]
  "Build an API client from an OpenAPI 3.x schema.

  schema — parsed schema table, local file path, or http(s):// URL
  ?opts  — {:base-url \"https://...\" :headers {} :http-fn custom-fn}
           base-url defaults to schema.servers[1].url"
  (let [schema (if (= (type schema) :string) (load-schema schema) schema)
        base-url (or (?. ?opts :base-url)
                     (?. schema :servers 1 :url)
                     (error "no base-url: pass via ?opts or add servers to schema"))
        client {:base-url base-url
                :http-fn (or (?. ?opts :http-fn) http.request)
                :headers (or (?. ?opts :headers) {})}]
    (each [path methods (pairs schema.paths)]
      (each [method op-spec (pairs methods)]
        (when (and (= (type op-spec) :table) op-spec.operationId)
          (tset client
                (util.camel->kebab op-spec.operationId)
                (make-operation path method op-spec)))))
    client))

(fn load-schema [path]
  "Load an OpenAPI schema from a local file path or http(s):// URL."
  (let [content (if (path:match "^https?://")
                    (let [requester (if (path:match "^https://") https socket-http)
                          body-out []
                          (ok code) (requester.request {:url path
                                                        :method :GET
                                                        :sink (ltn12.sink.table body-out)})]
                      (assert ok (tostring code))
                      (table.concat body-out))
                    (let [f (assert (io.open path :r))
                          c (f:read :*a)]
                      (f:close)
                      c))]
    (json.decode content)))

{: client}
