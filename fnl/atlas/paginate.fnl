;; ABOUTME: Wraps an http-fn to follow Link rel="next" pagination on GET
;; ABOUTME: requests, concatenating JSON array pages into one response.
(local json (require :atlas.json))
(local util (require :atlas.util))

(fn link-params-rel [params]
  "Space-separated rel value of a Link entry's parameters, lowercased."
  (let [lower (params:lower)]
    (or (lower:match ";%s*rel%s*=%s*\"([^\"]*)\"")
        (lower:match ";%s*rel%s*=%s*([^;,%s]+)") "")))

(fn next-link [headers]
  "URL of the rel=\"next\" entry of a Link header, or nil.
URLs are delimited by <>, so commas inside them are safe."
  (let [link (util.header headers "link")]
    (when link
      (accumulate [found nil url params (link:gmatch "<([^>]*)>([^<]*)")
                   &until found]
        (when (accumulate [next? false rel (: (link-params-rel params) :gmatch
                                              "%S+")
                           &until next?]
                (= rel "next"))
          url)))))

(fn resolve-next [current ref]
  (if (= (ref:sub 1 1) "?")
      (.. (current:match "^[^?#]*") ref)
      (util.resolve-reference current ref)))

(fn array-text [resp]
  "Text between the outer brackets of a 2xx JSON array response, or nil."
  (when (and (util.success? resp.status) (= (type resp.raw) :string))
    (let [inner (resp.raw:match "^%s*%[(.*)%]%s*$")
          ;; one JSON array, not text that merely starts and ends with brackets
          (ok value) (when inner (pcall json.decode resp.raw))]
      (when (and ok (json.array? value))
        inner))))

(fn wrap [http-fn opts]
  "Follow next links for GET requests whose responses are JSON arrays.
Pages are merged from their raw JSON text, so nulls and number formatting
survive. opts: {:max-pages n} (default 25)"
  (let [max-pages (or opts.max-pages 25)]
    (fn [req]
      (let [first (http-fn req)
            first-items (array-text first)
            first-url (util.append-query req.url (or req.query {})
                                         req.query-styles)]
        (if (or (not= (: (or req.method "GET") :upper) "GET")
                (= nil first-items) (= nil (next-link first.headers)))
            first
            (let [chunks [first-items]]
              (var url first-url)
              (var resp first)
              (var failed-status nil)
              (var done false)
              (while (not done)
                (let [link (next-link resp.headers)
                      target (when link (resolve-next url link))]
                  (if (or (not target) (>= (length chunks) max-pages)
                          (not= (util.origin target) (util.origin first-url)))
                      (set done true)
                      ;; the original request (headers, TLS, timeout, what
                      ;; authentication marked sensitive) at the next URL
                      (let [page (http-fn (doto (collect [k v (pairs req)] k v)
                                            (tset :method "GET")
                                            (tset :url target)
                                            (tset :query nil)
                                            (tset :body nil)))
                            items (array-text page)]
                        (if items
                            (do
                              (table.insert chunks items)
                              (set url target)
                              (set resp page))
                            (do
                              (set failed-status page.status)
                              (set done true)))))))
              (let [raw (.. "["
                            (table.concat (icollect [_ c (ipairs chunks)]
                                            (when (c:match "%S") c))
                                          ",") "]")]
                {:status first.status
                 :headers first.headers
                 :body (json.decode raw true)
                 :raw raw
                 :pages (length chunks)
                 :next-page-status failed-status})))))))

{: wrap : next-link}
