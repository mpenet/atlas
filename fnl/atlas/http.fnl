(local socket-http (require :socket.http))
(local https (require :ssl.https))
(local ltn12 (require :ltn12))
(local json (require :lunajson))

(fn url-encode [s]
  (: (tostring s) :gsub "[^%w%-%.%_%~]"
    (fn [c] (string.format "%%%02X" (string.byte c)))))

(fn encode-query [params]
  (when params
    (let [parts []]
      (each [k v (pairs params)]
        (table.insert parts (.. (url-encode k) "=" (url-encode v))))
      (when (> (length parts) 0)
        (table.concat parts "&")))))

(fn build-url [url query]
  (let [qs (encode-query query)]
    (if qs (.. url "?" qs) url)))

(fn request [req]
  (let [url (build-url req.url req.query)
        requester (if (url:match "^https://") https socket-http)
        (ok-enc payload) (if req.raw-body
                             (values true req.raw-body)
                             (if req.body
                                 (pcall json.encode req.body)
                                 (values true nil)))]
    (assert ok-enc (string.format "failed to encode request body: %s" (tostring payload)))
    (let [headers (collect [k v (pairs (or req.headers {}))] k v)
          body-out []]
      (when payload
        (tset headers :content-length (tostring (length payload))))
      (let [req-table {:url url
                       :method req.method
                       :headers headers
                       :timeout req.timeout
                       :source (when payload (ltn12.source.string payload))
                       :sink (ltn12.sink.table body-out)}]
        (when (and req.ssl (url:match "^https://"))
          (each [k v (pairs req.ssl)]
            (tset req-table k v)))
        (let [(ok code resp-headers) (requester.request req-table)]
          (assert ok (string.format "%s %s failed: %s" req.method url (tostring code)))
          (let [raw (table.concat body-out)
                body (when (> (length raw) 0)
                       (let [(ok val) (pcall json.decode raw)]
                         (if ok val raw)))]
            {:status code
             :headers resp-headers
             :body body}))))))

{: request}
