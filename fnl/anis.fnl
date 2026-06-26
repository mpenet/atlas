(local util (require :anis.util))
(local negotiate (require :anis.negotiate))
(local doc (require :anis.doc))

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

(fn build-client [schema base-url http-fn ?opts]
  "Build an API client from an OpenAPI 3.x schema.

  schema   — parsed schema table
  base-url — e.g. \"https://api.example.com\"
  http-fn  — (fn [{:method :url :headers :query :body}]) → response
  ?opts    — {:headers {}} for default request headers (auth etc.)"
  (let [client {:base-url base-url
                :http-fn http-fn
                :headers (or (?. ?opts :headers) {})}]
    (each [path methods (pairs schema.paths)]
      (each [method op-spec (pairs methods)]
        (when (and (= (type op-spec) :table) op-spec.operationId)
          (tset client
                (util.camel->kebab op-spec.operationId)
                (make-operation path method op-spec)))))
    client))

(fn load-schema [path json-decode]
  "Load an OpenAPI schema from a JSON file.
  json-decode — (fn [string]) → table"
  (let [f (assert (io.open path :r))
        content (f:read :*a)]
    (f:close)
    (json-decode content)))

{: build-client : load-schema}
