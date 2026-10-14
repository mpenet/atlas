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
                    (assert.is_truthy (: (tostring err) :find "timeout"))
                    (assert.is_true (< (- (socket.gettime) t0) 2)))))))

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
