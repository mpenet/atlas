;; ABOUTME: HTTP transport over luasocket/luasec: encodes request bodies by
;; ABOUTME: content-type and decodes responses into {:status :headers :body :raw}.
(local socket-http (require :socket.http))
(local https (require :ssl.https))
(local ltn12 (require :ltn12))
(local json (require :lunajson))
(local util (require :atlas.util))

(fn json-type? [content-type]
  (and content-type
       (or (content-type:match "^application/json")
           (content-type:match "^[%w%.%-]+/[%w%.%-]+%+json"))))

(fn encode-body [req]
  "Serialize the request body according to its content-type header."
  (let [content-type (util.header req.headers "content-type")]
    (if req.raw-body req.raw-body (= nil req.body) nil
        (= (type req.body) :string) req.body
        (and content-type
             (content-type:match "^application/x%-www%-form%-urlencoded"))
        (util.form-encode req.body)
        (let [(ok payload) (pcall json.encode req.body)]
          (assert ok (string.format "failed to encode request body: %s"
                                    (tostring payload)))
          payload))))

(fn decode-response [status headers raw]
  "Build a response; JSON content (or untyped content that parses) is decoded."
  (let [content-type (util.header headers "content-type")
        body (when (> (length raw) 0)
               (if (or (json-type? content-type) (= nil content-type))
                   (let [(ok val) (pcall json.decode raw)]
                     (if ok val raw))
                   raw))]
    {:status status :headers headers :body body :raw raw}))

(fn with-timeout [seconds f]
  "Run f with luasocket/luasec module timeouts set to seconds; they only
support a module-level setting, so it is restored afterwards."
  (if (= nil seconds)
      (f)
      (let [prev-http socket-http.TIMEOUT
            prev-https https.TIMEOUT]
        (set socket-http.TIMEOUT seconds)
        (set https.TIMEOUT seconds)
        (let [result (table.pack (pcall f))]
          (set socket-http.TIMEOUT prev-http)
          (set https.TIMEOUT prev-https)
          (if (. result 1)
              (table.unpack result 2 result.n)
              (error (. result 2) 0))))))

(fn request [req]
  (let [url (util.append-query req.url (or req.query {}))
        requester (if (url:match "^https://") https socket-http)
        payload (encode-body req)
        headers (collect [k v (pairs (or req.headers {}))]
                  k
                  v)
        body-out []
        req-table (if (and req.ssl (url:match "^https://"))
                      (collect [k v (pairs req.ssl)] k v)
                      {})]
    (when payload
      (tset headers :content-length (tostring (length payload))))
    (tset req-table :url url)
    (tset req-table :method req.method)
    (tset req-table :headers headers)
    (tset req-table :source (when payload (ltn12.source.string payload)))
    (tset req-table :sink (ltn12.sink.table body-out))
    (let [(ok code resp-headers) (with-timeout req.timeout
                                   #(requester.request req-table))]
      (assert ok (string.format "%s %s failed: %s" req.method url
                                (tostring code)))
      (decode-response code resp-headers (table.concat body-out)))))

(fn fetch-text [location ?opts]
  "Return the text at location: an http(s):// URL or a local file path.
?opts: {:ssl {} :headers {}}"
  (if (location:match "^https?://")
      (let [resp (request {:method "GET"
                           :url location
                           :headers (?. ?opts :headers)
                           :ssl (?. ?opts :ssl)})]
        (assert (and (>= resp.status 200) (< resp.status 300))
                (string.format "HTTP %s fetching %s" resp.status location))
        resp.raw)
      (let [(f err) (io.open location :r)]
        (assert f
                (string.format "cannot open '%s': %s" location (tostring err)))
        (let [content (f:read :*a)]
          (f:close)
          content))))

{: request : fetch-text : encode-body : decode-response}
