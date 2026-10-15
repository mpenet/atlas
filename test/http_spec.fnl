;; ABOUTME: Specs for request body encoding, response decoding, timeouts and fetching.
;; ABOUTME: Run with `make test` (busted, Fennel loader).
(local http (require :atlas.http))

(describe "http.encode-body"
          (fn []
            (it "returns nil without a body"
                (fn []
                  (assert.is_nil (http.encode-body {:headers {}}))))
            (it "JSON-encodes tables by default"
                (fn []
                  (assert.are.equal "{\"a\":1}"
                                    (http.encode-body {:body {:a 1}
                                                       :headers {}}))))
            (it "form-encodes for x-www-form-urlencoded"
                (fn []
                  (assert.are.equal "a=1&b=x%20y"
                                    (http.encode-body {:body {:b "x y" :a 1}
                                                       :headers {:content-type "application/x-www-form-urlencoded"}}))))
            (it "passes string bodies through unchanged"
                (fn []
                  (assert.are.equal "<x/>"
                                    (http.encode-body {:body "<x/>"
                                                       :headers {:content-type "application/xml"}}))))
            (it "prefers raw-body"
                (fn []
                  (assert.are.equal "raw"
                                    (http.encode-body {:raw-body "raw"
                                                       :body {:a 1}
                                                       :headers {}}))))))

(describe "http.decode-response"
          (fn []
            (it "matches media types whatever their case"
                (fn []
                  (assert.are.same {:a 1}
                                   (. (http.decode-response 200
                                                            {:content-type "Application/JSON"}
                                                            "{\"a\":1}")
                                      :body))
                  (assert.are.equal "a=1"
                                    (http.encode-body {:headers {:content-type "Application/X-WWW-Form-Urlencoded"}
                                                       :body {:a 1}}))))
            (it "decodes JSON content types"
                (fn []
                  (let [r (http.decode-response 200
                                                {:content-type "application/problem+json"}
                                                "{\"a\":1}")]
                    (assert.are.same {:a 1} r.body)
                    (assert.are.equal "{\"a\":1}" r.raw))))
            (it "keeps text bodies as strings"
                (fn []
                  (assert.are.equal "42"
                                    (. (http.decode-response 200
                                                             {:content-type "text/plain"}
                                                             "42")
                                       :body))))
            (it "sniffs JSON when content-type is absent"
                (fn []
                  (assert.are.same [1]
                                   (. (http.decode-response 200 {} "[1]") :body))))
            (it "falls back to text when JSON is malformed"
                (fn []
                  (assert.are.equal "{oops"
                                    (. (http.decode-response 200
                                                             {:content-type "application/json"}
                                                             "{oops")
                                       :body))))
            (it "returns nil body for empty payload"
                (fn []
                  (assert.is_nil (. (http.decode-response 204 {} "") :body))))))

(describe "http.request timeout"
          (fn []
            (it "aborts when the server does not answer in time"
                (fn []
                  (let [socket (require :socket)
                        srv (assert (socket.bind "127.0.0.1" 0))
                        (_ port) (srv:getsockname)
                        t0 (socket.gettime)
                        (ok err) (pcall http.request
                                        {:method "GET"
                                         :url (.. "http://127.0.0.1:" port "/")
                                         :timeout 0.2})]
                    (srv:close)
                    (assert.is_false ok)
                    (assert.is_truthy (: (tostring err) :find "timed out"))
                    (assert.is_true (< (- (socket.gettime) t0) 2)))))
            (it "keeps a timeout under a millisecond"
                (fn []
                  (let [socket (require :socket)
                        srv (assert (socket.bind "127.0.0.1" 0))
                        (_ port) (srv:getsockname)
                        t0 (socket.gettime)
                        (ok err) (pcall http.request
                                        {:method "GET"
                                         :url (.. "http://127.0.0.1:" port "/")
                                         :timeout 0.0004})]
                    (srv:close)
                    (assert.is_false ok)
                    (assert.is_true (< (- (socket.gettime) t0) 2)))))))

(describe "http.fetch-text"
          (fn []
            (it "gives up after the timeout"
                (fn []
                  (let [socket (require :socket)
                        srv (assert (socket.bind "127.0.0.1" 0))
                        (_ port) (srv:getsockname)
                        (ok err) (pcall http.fetch-text
                                        (.. "http://127.0.0.1:" port "/s.json")
                                        {:timeout 0.2})]
                    (srv:close)
                    (assert.is_false ok)
                    (assert.is_truthy (: (tostring err) :find "timed out")))))))

(describe "http.request failures"
          (fn []
            (it "hide the query parameters marked sensitive"
                (fn []
                  (let [socket (require :socket)
                        srv (assert (socket.bind "127.0.0.1" 0))
                        (_ port) (srv:getsockname)]
                    (srv:close)
                    (let [(ok err) (pcall http.request
                                          {:method "GET"
                                           :url (.. "http://127.0.0.1:" port
                                                    "/x?appid=QSECRET&n=1")
                                           :sensitive-query ["AppId"]})]
                      (assert.is_false ok)
                      (assert.is_nil (: (tostring err) :find "QSECRET" 1 true))
                      (assert.is_truthy (: (tostring err) :find "n=1" 1 true))))))))

(describe "the transport binding"
          (fn []
            (it "refuses strings with an embedded NUL"
                (fn []
                  (let [curl (require :atlas.curl)]
                    (assert.has.error #(curl.perform {:method "GET"
                                                      :url "http://localhost:1\0@127.0.0.1:2/"})
                                      "url must not contain NUL bytes")
                    (assert.has.error #(curl.perform {:method "GET"
                                                      :url "http://127.0.0.1:1/"
                                                      :headers ["x-a: b\0c"]})))))))

(describe "http.parse-headers"
          (fn []
            (it "lowercases names and joins repeated headers"
                (fn []
                  (assert.are.same {:content-type "application/json"
                                    :set-cookie "a=1, b=2"
                                    :x-empty ""}
                                   (http.parse-headers "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nSet-Cookie: a=1\r\nset-cookie: b=2\r\nX-Empty:\r\n\r\n"))))))

(describe "http.transfer"
          (fn []
            (let [tls {:verify true :cafile "/ca.pem"}]
              (it "describes the exchange for the transport"
                  (fn []
                    (assert.are.same {:method "POST"
                                      :url "https://h/x?a=1"
                                      :headers ["accept: application/json"
                                                "content-type: application/json"]
                                      :body "{}"
                                      :timeout 5
                                      :verify true
                                      :cafile "/ca.pem"}
                                     (http.transfer {:method "POST" :timeout 5}
                                                    "https://h/x?a=1" "{}"
                                                    {:content-type "application/json"
                                                     :accept "application/json"}
                                                    tls))))
              (it "stops the transport from adding a form content type"
                  (fn []
                    (assert.are.same ["content-type:"]
                                     (. (http.transfer {:method "POST"}
                                                       "https://h/x" "raw" {}
                                                       tls)
                                        :headers))))
              (it "sends empty header values"
                  (fn []
                    (assert.are.same ["x-empty;"]
                                     (. (http.transfer {:method "GET"}
                                                       "https://h/x" nil
                                                       {:x-empty ""} tls)
                                        :headers)))))))

(describe "http.request over the network"
          (fn []
            (fn with-server [n f]
              "Runs f with the port of an echo server answering n requests."
              (let [proc (io.popen (.. "lua test/fixtures/echo-server.lua " n))
                    port (proc:read :*l)
                    (ok err) (pcall f port)]
                (proc:close)
                (assert ok err)))

            (it "sends the method, path, query and body, and decodes the reply"
                (fn []
                  (with-server 1
                    (fn [port]
                      (let [resp (http.request {:method "POST"
                                                :url (.. "http://127.0.0.1:"
                                                         port "/pets")
                                                :query {:a "1"}
                                                :headers {:content-type "application/json"}
                                                :body {:name "Rex"}
                                                :ssl {:verify "none"}})]
                        (assert.are.equal 200 resp.status)
                        (assert.are.same {:method "POST"
                                          :path "/pets?a=1"
                                          :body "{\"name\":\"Rex\"}"
                                          :content_type "application/json"}
                                         resp.body))))))
            (it "goes through the proxy named by http_proxy"
                (fn []
                  (with-server 1
                    (fn [port]
                      (let [script "local r = require('atlas.http').request({method = 'GET', url = 'http://api.example.test/pets'}); io.write(r.body.path)"
                            proc (io.popen (.. "http_proxy=http://127.0.0.1:"
                                               port " lua -e \"" script "\""))
                            path (proc:read :*a)]
                        (proc:close)
                        ;; a proxy receives the absolute URL
                        (assert.are.equal "http://api.example.test/pets" path))))))
            (it "fetches text from a URL"
                (fn []
                  (with-server 1
                    (fn [port]
                      (let [text (http.fetch-text (.. "http://127.0.0.1:" port
                                                      "/spec.json")
                                                  {:headers {:x "1"}})]
                        (assert.is_truthy (text:find "\"path\":\"/spec.json\""
                                                     1 true)))))))))

(describe "http.fetch-text"
          (fn []
            (it "reads local files"
                (fn []
                  (assert.is_truthy (: (http.fetch-text "test/fixtures/simple.arazzo.json")
                                       :find "arazzo"))))
            (it "errors with the path for missing files"
                (fn []
                  (let [(ok err) (pcall http.fetch-text "nope/missing.json")]
                    (assert.is_false ok)
                    (assert.is_truthy (: (tostring err) :find
                                         "nope/missing.json" 1 true)))))))

(describe "http.encode-body multipart"
          (fn []
            (it "encodes fields and file parts with a boundary in the content type"
                (fn []
                  (let [(payload content-type) (http.encode-body {:headers {:content-type "multipart/form-data"}
                                                                  :body {:name "Rex"
                                                                         :photo {:filename "rex.png"
                                                                                 :content "\137PNG\0bin"
                                                                                 :content-type "image/png"}}})
                        boundary (content-type:match "^multipart/form%-data; boundary=(.+)$")]
                    (assert.is_truthy boundary)
                    (assert.are.equal (.. "--" boundary "\r\n"
                                          "Content-Disposition: form-data; name=\"name\"\r\n\r\n"
                                          "Rex\r\n" "--" boundary "\r\n"
                                          "Content-Disposition: form-data; name=\"photo\"; filename=\"rex.png\"\r\n"
                                          "Content-Type: image/png\r\n\r\n"
                                          "\137PNG\0bin\r\n" "--" boundary
                                          "--\r\n")
                                      payload))))
            (it "defaults file parts to application/octet-stream"
                (fn []
                  (let [payload (http.encode-body {:headers {:content-type "multipart/form-data"}
                                                   :body {:f {:filename "x"
                                                              :content "y"}}})]
                    (assert.is_truthy (payload:find "Content-Type: application/octet-stream"
                                                    1 true)))))
            (it "leaves the content type alone for other bodies"
                (fn []
                  (let [(_ ct) (http.encode-body {:headers {:content-type "application/json"}
                                                  :body {:a 1}})]
                    (assert.is_nil ct))))))

(describe "multipart field names"
          (fn []
            (it "percent-escapes quotes and line breaks"
                (fn []
                  (let [payload (http.encode-body {:headers {:content-type "multipart/form-data"}
                                                   :body {"a\"\r\nX-Evil: 1" "v"}})]
                    (assert.is_nil (payload:find "\r\nX-Evil" 1 true))
                    (assert.is_truthy (payload:find "name=\"a%22%0D%0AX-Evil: 1\""
                                                    1 true)))))))

(describe "http.follow-redirects"
          (fn []
            (fn site [routes]
              "Single-shot transport serving routes keyed by URL; records requests."
              (let [seen []]
                (values (fn [req]
                          (table.insert seen req)
                          (let [util (require :atlas.util)]
                            (or (. routes
                                   (util.append-query req.url (or req.query {})))
                                {:status 404 :headers {}})))
                        seen)))

            (fn moved [location ?status]
              {:status (or ?status 302) :headers {:location location}})

            (let [creds {:authorization "Bearer s"
                         :cookie "c=1"
                         :x-api-key "k"
                         :accept "application/json"}]
              (it "follows same-origin redirects keeping headers"
                  (fn []
                    (let [(send seen) (site {"https://a.test/x" (moved "/y")
                                             "https://a.test/y" {:status 200
                                                                 :headers {}}})
                          resp (http.follow-redirects send
                                                      {:method "GET"
                                                       :url "https://a.test/x"
                                                       :headers creds})]
                      (assert.are.equal 200 resp.status)
                      (assert.are.equal "Bearer s"
                                        (. seen 2 :headers :authorization)))))
              (it "drops credentials when the origin changes"
                  (fn []
                    (let [(send seen) (site {"https://a.test/x" (moved "https://b.test/y")
                                             "https://b.test/y" {:status 200
                                                                 :headers {}}})]
                      (http.follow-redirects send
                                             {:method "GET"
                                              :url "https://a.test/x"
                                              :headers creds})
                      (assert.are.same {:accept "application/json"}
                                       (. seen 2 :headers)))))
              (it "keeps a query API key on the same origin only"
                  (fn []
                    (let [(send seen) (site {"https://a.test/x?k=K&n=1" (moved "/y")
                                             "https://a.test/y?k=K" (moved "https://b.test/z")
                                             "https://b.test/z" {:status 200
                                                                 :headers {}}})
                          resp (http.follow-redirects send
                                                      {:method "GET"
                                                       :url "https://a.test/x"
                                                       :query {:k "K" :n "1"}
                                                       :sensitive-query [:k]
                                                       :headers {}})]
                      (assert.are.equal 200 resp.status)
                      (assert.are.equal 3 (length seen)))))
              (it "drops the headers authentication added, whatever their name"
                  (fn []
                    (let [(send seen) (site {"https://a.test/x" (moved "https://b.test/y")
                                             "https://b.test/y" {:status 200
                                                                 :headers {}}})]
                      (http.follow-redirects send
                                             {:method "GET"
                                              :url "https://a.test/x"
                                              :headers {:X-AppId "k"
                                                        :accept "application/json"}
                                              :sensitive-headers [:x-appid]})
                      (assert.are.same {:accept "application/json"}
                                       (. seen 2 :headers)))))
              (it "drops credentials on redirects with a backslash in the host"
                  (fn []
                    (let [target "https://a.test\\@evil.test/y"
                          (send seen) (site {"https://a.test/x" (moved target)
                                             target {:status 200 :headers {}}})]
                      (http.follow-redirects send
                                             {:method "GET"
                                              :url "https://a.test/x"
                                              :headers creds})
                      (assert.are.same {:accept "application/json"}
                                       (. seen 2 :headers)))))
              (it "drops credentials on redirects that only look same-origin"
                  (fn []
                    (let [target "https://evil.test?@a.test/y"
                          (send seen) (site {"https://a.test/x" (moved target)
                                             target {:status 200 :headers {}}})]
                      (http.follow-redirects send
                                             {:method "GET"
                                              :url "https://a.test/x"
                                              :headers creds})
                      (assert.are.same {:accept "application/json"}
                                       (. seen 2 :headers)))))
              (it "never follows https to http"
                  (fn []
                    (let [(send seen) (site {"https://a.test/x" (moved "http://a.test/x")})
                          resp (http.follow-redirects send
                                                      {:method "GET"
                                                       :url "https://a.test/x"
                                                       :headers {}})]
                      (assert.are.equal 302 resp.status)
                      (assert.are.equal 1 (length seen)))))
              (it "does not follow redirects for other methods"
                  (fn []
                    (let [(send seen) (site {"https://a.test/x" (moved "/y" 307)})
                          resp (http.follow-redirects send
                                                      {:method "POST"
                                                       :url "https://a.test/x"
                                                       :headers {}})]
                      (assert.are.equal 307 resp.status)
                      (assert.are.equal 1 (length seen)))))
              (it "gives up with an error after 5 redirects"
                  (fn []
                    (let [(send seen) (site {"https://a.test/loop" (moved "/loop"
                                                                          301)})
                          (ok err) (pcall http.follow-redirects send
                                          {:method "GET"
                                           :url "https://a.test/loop"
                                           :headers {}})]
                      (assert.is_false ok)
                      (assert.is_truthy (: (tostring err) :find
                                           "too many redirects" 1 true))
                      (assert.are.equal 6 (length seen)))))
              (it "carries the query of the original request only on the first hop"
                  (fn []
                    (let [(send seen) (site {"https://a.test/x?q=1" (moved "/y?z=2"
                                                                           308)
                                             "https://a.test/y?z=2" {:status 200
                                                                     :headers {}}})]
                      (http.follow-redirects send
                                             {:method "GET"
                                              :url "https://a.test/x"
                                              :query {:q "1"}
                                              :headers {}})
                      (assert.are.equal "https://a.test/y?z=2" (. seen 2 :url))
                      (assert.is_nil (. seen 2 :query))))))))

(describe "header safety"
          (fn []
            (it "rejects line breaks in header values"
                (fn []
                  (let [(ok err) (pcall http.encode-request
                                        {:method "GET"
                                         :url "https://h/x"
                                         :headers {:x-a "v\r\nX-Injected: yes"}})]
                    (assert.is_false ok)
                    (assert.is_truthy (: (tostring err) :find
                                         "header 'x-a' contains a line break" 1
                                         true)))))
            (it "rejects invalid header names"
                (fn []
                  (let [(ok err) (pcall http.encode-request
                                        {:method "GET"
                                         :url "https://h/x"
                                         :headers {"bad name\r\n" "v"}})]
                    (assert.is_false ok)
                    (assert.is_truthy (: (tostring err) :find
                                         "invalid header name" 1 true)))))
            (it "accepts ordinary headers"
                (fn []
                  (assert.has_no.errors #(http.encode-request {:method "GET"
                                                               :url "https://h/x"
                                                               :headers {:X-Trace "a b; c=d"
                                                                         :accept "*/*"}}))))))

(describe "redirect edge cases"
          (fn []
            (it "treats the scheme case-insensitively when refusing https to http"
                (fn []
                  (let [seen []
                        send (fn [req] (table.insert seen req)
                               {:status 302
                                :headers {:location "HTTP://a.test/x"}})
                        resp (http.follow-redirects send
                                                    {:method "GET"
                                                     :url "https://a.test/x"
                                                     :headers {}})]
                    (assert.are.equal 302 resp.status)
                    (assert.are.equal 1 (length seen)))))
            (it "reports a redirect loop as an error"
                (fn []
                  (let [send (fn [] {:status 301 :headers {:location "/loop"}})
                        (ok err) (pcall http.follow-redirects send
                                        {:method "GET"
                                         :url "https://a.test/loop"
                                         :headers {}})]
                    (assert.is_false ok)
                    (assert.is_truthy (: (tostring err) :find
                                         "too many redirects" 1 true)))))))
