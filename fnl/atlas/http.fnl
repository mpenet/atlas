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

(fn multipart-boundary [parts]
  "A boundary string that does not occur in any part."
  (var boundary nil)
  (while (or (= nil boundary)
             (accumulate [found false _ part (ipairs parts) &until found]
               (not= nil (part:find boundary 1 true))))
    (set boundary (string.format "atlas-%08x%08x" (math.random 0 0x7fffffff)
                                 (math.random 0 0x7fffffff))))
  boundary)

(fn quote-param [s]
  "Value for a quoted Content-Disposition parameter: \", CR and LF are
percent-escaped (as browsers do) so they cannot break out of the header."
  (pick-values 1 (: (tostring s) :gsub "[\"\r\n]"
                    #(string.format "%%%02X" (string.byte $)))))

(fn multipart-part [name value]
  "Headers and content of one form-data part; file parts are
{:filename :content :content-type}."
  (if (and (= (type value) :table) value.filename)
      (.. "Content-Disposition: form-data; name=\"" (quote-param name)
          "\"; filename=\"" (quote-param value.filename) "\"\r\n"
          "Content-Type: " (or value.content-type "application/octet-stream")
          "\r\n\r\n" value.content)
      (.. "Content-Disposition: form-data; name=\"" (quote-param name)
          "\"\r\n\r\n" (if (= (type value) :table) (json.encode value)
                          (tostring value)))))

(fn encode-multipart [body]
  "Returns (payload content-type) for a multipart/form-data body."
  (let [names (doto (icollect [k (pairs body)] k)
                (table.sort))
        parts (icollect [_ name (ipairs names)]
                (multipart-part name (. body name)))
        boundary (multipart-boundary parts)
        chunks []]
    (each [_ part (ipairs parts)]
      (table.insert chunks (.. "--" boundary "\r\n" part "\r\n")))
    (table.insert chunks (.. "--" boundary "--\r\n"))
    (values (table.concat chunks)
            (.. "multipart/form-data; boundary=" boundary))))

(fn encode-body [req]
  "Serialize the request body according to its content-type header.
Returns the payload, plus a replacement content type when encoding
determines one (multipart boundaries)."
  (let [content-type (util.header req.headers "content-type")]
    (if req.raw-body req.raw-body (= nil req.body) nil
        (= (type req.body) :string) req.body
        (and content-type
             (content-type:match "^application/x%-www%-form%-urlencoded"))
        (util.form-encode req.body)
        (and content-type (content-type:match "^multipart/form%-data"))
        (encode-multipart req.body)
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

(fn encode-request [req]
  "Wire form of a request: (url payload headers), with the content type
replaced when body encoding chose one."
  (let [(payload content-type) (encode-body req)
        headers (collect [k v (pairs (or req.headers {}))]
                  (when (or (= nil content-type)
                            (not= (k:lower) "content-type"))
                    (values k v)))]
    (when content-type
      (tset headers :content-type content-type))
    (values (util.append-query req.url (or req.query {})) payload headers)))

(fn request [req]
  (let [(url payload headers) (encode-request req)
        requester (if (url:match "^https://") https socket-http)
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
      (assert ok
              (string.format "%s %s failed: %s" req.method
                             (util.redact-url url) (tostring code)))
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

{: request : encode-request : fetch-text : encode-body : decode-response}
