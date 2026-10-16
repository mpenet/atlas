;; ABOUTME: HTTP transport over libcurl: encodes request bodies by
;; ABOUTME: content-type and decodes responses into {:status :headers :body :raw}.
(local curl (require :atlas.curl))
(local tls (require :atlas.tls))
(local json (require :atlas.json))
(local util (require :atlas.util))
(local yaml (require :atlas.yaml))

(fn media-type [content-type]
  "The type/subtype of a content type, in lower case, without parameters."
  (when content-type
    (: (content-type:lower) :match "^%s*([^;%s]*)")))

(fn json-type? [content-type]
  (let [mt (media-type content-type)]
    (and mt (or (= mt "application/json")
                (mt:match "^[%w%.%-]+/[%w%.%-]+%+json$")))))

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
        parts []
        _ (each [_ name (ipairs names)]
            (let [value (. body name)]
              ;; an array is one part per element, all with its name (OpenAPI:
              ;; an array's encoding is its items')
              (if (json.array? value)
                  (each [_ item (ipairs value)]
                    (table.insert parts (multipart-part name item)))
                  (table.insert parts (multipart-part name value)))))
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
  ;; media types are case-insensitive
  (let [content-type (-?> (util.header req.headers "content-type") (: :lower))]
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

(local json-lines-types
       {"application/x-ndjson" true
        "application/ndjson" true
        "application/jsonl" true
        "application/jsonlines" true
        "application/x-jsonlines" true})

(fn json-lines-type? [content-type]
  (. json-lines-types (or (media-type content-type) "")))

(fn yaml-type? [content-type]
  (let [mt (media-type content-type)]
    (and mt (or (= mt "application/x-yaml") (mt:match "^[%w%.%-]+/yaml$")
                (mt:match "^[%w%.%-]+/[%w%.%-]+%+yaml$")))))

(fn decode-json-lines [raw]
  "An array of the JSON values of raw's non-blank lines."
  (json.array (icollect [line (raw:gmatch "[^\n]+")]
                (when (line:match "%S")
                  ;; CRLF line ends too
                  (json.decode (line:match "^%s*(.-)%s*$") true)))))

(fn decode-response [status headers raw]
  "Build a response; JSON, JSON Lines (as an array) and YAML content, or
untyped content that parses as JSON, is decoded. Content that doesn't parse
stays text."
  (let [content-type (util.header headers "content-type")
        ;; nulls are kept: the body is shown as received
        decode (if (or (json-type? content-type) (= nil content-type))
                   #(json.decode $ true)
                   (json-lines-type? content-type)
                   decode-json-lines
                   (yaml-type? content-type)
                   ;; an empty or null document is null, as JSON's
                   #(let [v (yaml.parse $ true)]
                      (if (= nil v) json.null v)))
        body (when (> (length raw) 0)
               (if decode
                   (let [(ok val) (pcall decode raw)]
                     (if ok val raw))
                   raw))]
    {:status status :headers headers :body body :raw raw}))

(fn check-header [name value]
  "Raise for names that aren't HTTP tokens and values with CR, LF or NUL,
which would let a value inject extra headers."
  (when (not (: (tostring name) :match "^[!#$%%&'*+%-.^_`|~%w]+$"))
    (error (string.format "invalid header name %q" (tostring name)) 0))
  (when (: (tostring value) :find "[\r\n%z]")
    (error (string.format "header '%s' contains a line break or NUL" name) 0)))

(fn header-value [name v]
  "A header's value as text: arrays in the simple style (a,b), as OpenAPI
serializes header parameters; objects can't be sent."
  (if (not= (type v) :table) v (json.array? v)
      (table.concat (icollect [_ x (ipairs v)]
                      (if (= (type x) :table)
                          (error (.. "header " name
                                     ": nested objects and arrays can't be sent")
                                 0)
                          (tostring x))) ",")
      (error (.. "header " name ": objects can't be sent in a header") 0)))

(fn encode-request [req]
  "Wire form of a request: (url payload headers), with the content type
replaced when body encoding chose one."
  (let [(payload content-type) (encode-body req)
        headers (collect [k v (pairs (or req.headers {}))]
                  (when (or (= nil content-type)
                            (not= (k:lower) "content-type"))
                    (values k (header-value k v))))]
    (when content-type
      (tset headers :content-type content-type))
    (each [k v (pairs headers)]
      (check-header k v))
    (values (util.append-query req.url (or req.query {}) req.query-styles)
            payload headers)))

(local redirect-status {301 true 302 true 303 true 307 true 308 true})

(fn redirect-target [req resp]
  "The request to send next for a followable redirect, or nil. Only GET and
HEAD are followed; https never goes to http. On the same origin, the query
parameters authentication added (req.sensitive-query) go along; when the
origin changes, they and the credential headers are dropped: those named in
req.sensitive-headers and any whose name looks like a credential."
  (let [location (util.header resp.headers "location")
        method (: (or req.method "GET") :upper)]
    (when (and (. redirect-status resp.status) location
               (or (= method "GET") (= method "HEAD")))
      (let [from (util.append-query req.url (or req.query {}) req.query-styles)
            target ((. (require :socket.url) :absolute) from location)
            target-origin (util.origin target)
            same-origin? (and target-origin
                              (= target-origin (util.origin from)))
            sensitive (collect [_ n (ipairs (or req.sensitive-headers []))]
                        (n:lower)
                        true)]
        (when (not (and (: (from:lower) :match "^https:")
                        (: (target:lower) :match "^http:")))
          (doto (collect [k v (pairs req)] k v)
            (tset :url target)
            (tset :query (let [kept (collect [_ n (ipairs (or req.sensitive-query
                                                              []))]
                                      (when (and same-origin?
                                                 (not= nil (?. req.query n))
                                                 (not (util.query-has? target n)))
                                        (values n (. req.query n))))]
                           (when (next kept) kept)))
            (tset :headers (if same-origin?
                               req.headers
                               (collect [k v (pairs (or req.headers {}))]
                                 (when (not (or (util.secret-name? k)
                                                (. sensitive (k:lower))))
                                   (values k v)))))))))))

(fn follow-redirects [send req]
  "Call send, following redirects (at most 5, then an error) as
redirect-target allows. The response's :url is where it came from."
  (var current req)
  (var resp (send req))
  (var hops 0)
  (var next-req (redirect-target current resp))
  (while next-req
    (when (>= hops 5)
      (error (.. "too many redirects from "
                 (util.redact-url req.url req.sensitive-query)) 0))
    (set hops (+ hops 1))
    (set current next-req)
    (set resp (send current))
    (set next-req (redirect-target current resp)))
  (when (= nil resp.url)
    (set resp.url (util.append-query current.url (or current.query {})
                                     current.query-styles)))
  resp)

(fn parse-headers [text]
  "Header map of a response header block: names lowercased, repeated
headers joined with \", \"."
  (let [headers {}]
    (each [line (text:gmatch "[^\r\n]+")]
      (match (line:match "^([^:%s]+):%s*(.-)%s*$")
        (name value) (let [k (name:lower)]
                       (tset headers k
                             (match (. headers k)
                               prev (.. prev ", " value)
                               _ value)))))
    headers))

(local body-methods {:POST true :PUT true :PATCH true})

(fn transfer [req url payload headers tls-options]
  "The exchange as the transport takes it: headers as sorted \"name: value\"
lines, plus the TLS settings."
  (let [names (doto (icollect [k (pairs headers)] k)
                (table.sort))
        lines (icollect [_ k (ipairs names)]
                (let [v (tostring (. headers k))]
                  ;; "name;" is how libcurl sends an empty value
                  (if (= v "") (.. k ";") (.. k ": " v))))]
    ;; a body without a content type would otherwise be sent as a form
    (when (and (or payload (. body-methods req.method))
               (= nil (util.header headers "content-type")))
      (table.insert lines "content-type:"))
    (doto (collect [k v (pairs tls-options)] k v)
      (tset :method req.method)
      (tset :url url)
      (tset :headers lines)
      (tset :body payload)
      (tset :timeout req.timeout))))

(fn send [req]
  "One HTTP exchange; redirects are followed by request, not by the transport."
  (let [(ok url payload headers) (pcall encode-request req)
        _ (when (not ok)
            (error (util.permanent-error (tostring url))))
        (status head body) (curl.perform (transfer req url payload headers
                                                   (tls.options req.ssl)))]
    (assert status (string.format "%s %s failed: %s" req.method
                                  (util.redact-url url req.sensitive-query)
                                  (tostring head)))
    (decode-response status (parse-headers head) body)))

(fn request [req]
  (follow-redirects send req))

(fn fetch-text [location ?opts]
  "Return the text at location: an http(s):// URL or a local file path.
?opts: {:ssl {} :headers {} :timeout seconds}"
  (if (location:match "^https?://")
      (let [resp (request {:method "GET"
                           :url location
                           :headers (?. ?opts :headers)
                           :ssl (?. ?opts :ssl)
                           :timeout (?. ?opts :timeout)})]
        (assert (util.success? resp.status)
                (string.format "HTTP %s fetching %s" resp.status
                               (util.redact-url location)))
        resp.raw)
      (let [(f err) (io.open location :r)]
        (assert f
                (string.format "cannot open '%s': %s" location (tostring err)))
        (let [content (f:read :*a)]
          (f:close)
          content))))

{: request
 : parse-headers
 : transfer
 : follow-redirects
 : encode-request
 : header-value
 : fetch-text
 : encode-body
 : decode-response
 : json-type?}
