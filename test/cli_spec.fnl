;; ABOUTME: Specs for CLI argument parsing, request building, output formatting and options.
;; ABOUTME: Run with `make test` (busted, Fennel loader).
(local cli (require :atlas.cli))

(describe "cli.parse-args"
          (fn []
            (it "keeps positional path params as raw strings"
                (fn []
                  (let [p (cli.parse-args ["op" "api" "get-x" "007" "1e3"])]
                    (assert.are.same ["007" "1e3"] p.path-params))))
            (it "accepts empty values"
                (fn []
                  (let [p (cli.parse-args ["op"
                                           "api"
                                           "x"
                                           "--query.q="
                                           "--header.x-a="
                                           "--body.s="
                                           "--input.i="
                                           "-ij="])]
                    (assert.are.equal "" p.query.q)
                    (assert.are.equal "" (. p.headers :x-a))
                    (assert.are.same [["s" ""]] p.body-fields)
                    (assert.are.same [["i" ""] ["j" ""]] p.input-fields))))
            (it "parses --max-gotos"
                (fn []
                  (assert.are.equal 500
                                    (. (cli.parse-args ["az"
                                                        "f"
                                                        "wf"
                                                        "--max-gotos=500"])
                                       :max-gotos))))
            (it "collects --server.NAME=VAL"
                (fn []
                  (assert.are.same {:zone "de-fra-1"}
                                   (. (cli.parse-args ["op"
                                                       "api"
                                                       "--server.zone=de-fra-1"])
                                      :server-vars))))
            (it "rejects unknown options"
                (fn []
                  (assert.has.error #(cli.parse-args ["op" "api" "--qeury.x=1"])
                                    "unknown option: --qeury.x=1")))
            (it "requires a value after -d and -i"
                (fn []
                  (assert.has.error #(cli.parse-args ["op" "api" "mk" "-d"])
                                    "-d requires a value")
                  (assert.has.error #(cli.parse-args ["az" "f" "wf" "-i"])
                                    "-i requires a value")))
            (it "treats everything after -- as positional"
                (fn []
                  (let [p (cli.parse-args ["op"
                                           "api"
                                           "get-x"
                                           "--"
                                           "-5"
                                           "--list"])]
                    (assert.are.same ["-5" "--list"] p.path-params)
                    (assert.is_nil p.list))))
            (it "collects --body.KEY=VAL fields as raw strings in order"
                (fn []
                  (let [p (cli.parse-args ["op"
                                           "api"
                                           "mk"
                                           "--body.a.b=007"
                                           "--body.n=5"])]
                    (assert.are.same [["a.b" "007"] ["n" "5"]] p.body-fields))))))

(describe "cli.build-body"
          (fn []
            (it "coerces fields by schema"
                (fn []
                  (let [schema {:type "object"
                                :properties {:zip {:type "string"}
                                             :n {:type "integer"}
                                             :o {:type "object"
                                                 :properties {:on {:type "boolean"}}}}}]
                    (assert.are.same {:zip "007" :n 5 :o {:on true}}
                                     (cli.build-body [["zip" "007"]
                                                      ["n" "5"]
                                                      ["o.on" "true"]]
                                                     schema)))))
            (it "falls back to JSON literal rules without schema"
                (fn []
                  (assert.are.same {:a "007" :b 5}
                                   (cli.build-body [["a" "007"] ["b" "5"]] nil))))))

(describe "cli.op-request"
          (fn []
            (let [op {:path-params ["ownerId" "petId"] :has-body? true}]
              (it "maps positional path params to names without coercion"
                  (fn []
                    (let [req (cli.op-request op
                                              {:path-params ["007" "x"]
                                               :query {}
                                               :headers {}
                                               :body-fields []})]
                      (assert.are.same {:ownerId "007" :petId "x"} req.path))))
              (it "sends no body when none is given but keeps query"
                  (fn []
                    (let [req (cli.op-request op
                                              {:path-params ["1" "2"]
                                               :query {:q "v"}
                                               :headers {}
                                               :body-fields []})]
                      (assert.is_nil req.body)
                      (assert.are.same {:q "v"} req.query))))
              (it "merges --body.KEY fields over --body"
                  (fn []
                    (let [req (cli.op-request op
                                              {:path-params ["1" "2"]
                                               :query {}
                                               :headers {}
                                               :body {:x 1}
                                               :body-fields [["y" "2"]]})]
                      (assert.are.same {:x 1 :y 2} req.body)))))))

(describe "cli.format-output"
          (fn []
            (let [resp {:status 200
                        :headers {:b "2" :a "1"}
                        :body {:x 1}
                        :raw "{\"x\": 1}"}]
              (it "raw prints the body exactly as received"
                  (fn []
                    (assert.are.equal "{\"x\": 1}"
                                      (cli.format-output resp :raw false))))
              (it "json pretty-prints"
                  (fn []
                    (assert.are.equal "{\n  \"x\": 1\n}"
                                      (cli.format-output resp :json false))))
              (it "yaml renders without leading newline"
                  (fn []
                    (assert.are.equal "x: 1"
                                      (cli.format-output resp :yaml false))))
              (it "status prints the code"
                  (fn []
                    (assert.are.equal "200"
                                      (cli.format-output resp :status false))))
              (it "headers print sorted"
                  (fn []
                    (assert.are.equal "a: 1\nb: 2"
                                      (cli.format-output resp :headers false))))
              (it "applies select"
                  (fn []
                    (assert.are.equal "1"
                                      (cli.format-output resp :json false ".x"))))
              (it "returns nil when there is no body"
                  (fn []
                    (assert.is_nil (cli.format-output {:status 204 :headers {}}
                                                      :json false)))))))

(describe "cli.client-options"
          (fn []
            (it "merges profile headers with auth headers"
                (fn []
                  (let [profile {:headers {:x-api-key "k"}
                                 :auth {:name "external-tool"
                                        :params {:commandline "echo tok"
                                                 :output "bearer-token"}}}
                        opts (cli.client-options "p" profile {:ssl {}} {})]
                    (assert.are.equal "k" opts.headers.x-api-key)
                    (assert.are.equal "Bearer tok" opts.headers.authorization))))
            (it "prefers CLI over profile over config for timeout and base-url"
                (fn []
                  (let [opts (cli.client-options "p"
                                                 {:timeout 5
                                                  :base-url "https://profile"}
                                                 {:ssl {}
                                                  :timeout 9
                                                  :base-url "https://cli"}
                                                 {:timeout 1})]
                    (assert.are.equal 9 opts.timeout)
                    (assert.are.equal "https://cli" opts.base-url))))
            (it "merges profile and auth headers case-insensitively, auth winning"
                (fn []
                  (let [profile {:headers {:Authorization "Basic static"}
                                 :auth {:name "external-tool"
                                        :params {:commandline "echo tok"
                                                 :output "bearer-token"}}}
                        opts (cli.client-options "p" profile {:ssl {}} {})]
                    (assert.are.same {:authorization "Bearer tok"} opts.headers))))
            (it "merges profile server vars with CLI ones, CLI winning"
                (fn []
                  (let [opts (cli.client-options "p"
                                                 {:server {:zone "ch-gva-2"
                                                           :version "v2"}}
                                                 {:ssl {}
                                                  :server-vars {:zone "de-fra-1"}}
                                                 {})]
                    (assert.are.same {:zone "de-fra-1" :version "v2"}
                                     opts.server-vars))))
            (it "falls back to config timeout"
                (fn []
                  (assert.are.equal 1
                                    (. (cli.client-options nil nil {:ssl {}}
                                                           {:timeout 1})
                                       :timeout))))))

(describe "cli.redact-header"
          (fn []
            (it "keeps the auth scheme but hides credentials"
                (fn []
                  (assert.are.equal "Bearer <redacted>"
                                    (cli.redact-header "Authorization"
                                                       "Bearer abc.def"))))
            (it "hides cookies, api keys, tokens and signatures"
                (fn []
                  (each [_ name (ipairs ["cookie"
                                         "x-api-key"
                                         "X-Auth-Token"
                                         "x-amz-signature"
                                         "client-secret"])]
                    (assert.are.equal "<redacted>"
                                      (cli.redact-header name "s3cr3t")))))
            (it "leaves other headers alone"
                (fn []
                  (assert.are.equal "application/json"
                                    (cli.redact-header "content-type"
                                                       "application/json"))))))

(describe "cli.strip-location"
          (fn []
            (it "strips Lua file locations"
                (fn []
                  (assert.are.equal "boom"
                                    (cli.strip-location "./lua/atlas/cli.lua:12: boom"))))
            (it "strips chunk-name locations from the static binary"
                (fn []
                  (assert.are.equal "goto loop detected at: s1"
                                    (cli.strip-location "[string \"fnl.atlas-bin\"]:7603: goto loop detected at: s1"))))
            (it "keeps URLs with ports intact"
                (fn []
                  (assert.are.equal "GET http://h:8080/x failed: timeout"
                                    (cli.strip-location "GET http://h:8080/x failed: timeout"))))))

(describe "cli.exit-code"
          (fn []
            (it "maps status classes"
                (fn []
                  (assert.are.equal 0 (cli.exit-code 200 false))
                  (assert.are.equal 0 (cli.exit-code 304 false))
                  (assert.are.equal 4 (cli.exit-code 404 false))
                  (assert.are.equal 5 (cli.exit-code 503 false))))
            (it "returns 0 for any status with --ignore-status"
                (fn [] (assert.are.equal 0 (cli.exit-code 500 true))))
            (it "parses --ignore-status"
                (fn []
                  (assert.is_true (. (cli.parse-args ["op"
                                                      "a"
                                                      "--ignore-status"])
                                     :ignore-status))))))

(describe "cli retry options"
          (fn []
            (it "parses retry flags"
                (fn []
                  (let [p (cli.parse-args ["op"
                                           "a"
                                           "--retry=5"
                                           "--retry-unsafe"
                                           "--retry-max-wait=10"])]
                    (assert.are.equal 5 p.retry)
                    (assert.is_true p.retry-unsafe)
                    (assert.are.equal 10 p.retry-max-wait))))
            (it "defaults to 2 safe retries capped at 300s"
                (fn []
                  (assert.are.same {:attempts 2 :unsafe false :max-wait 300}
                                   (cli.retry-options nil {} {}))))
            (it "prefers CLI over profile over config"
                (fn []
                  (assert.are.same {:attempts 0 :unsafe true :max-wait 30}
                                   (cli.retry-options {:retry {:attempts 4
                                                               :unsafe true}}
                                                      {:retry 0}
                                                      {:retry {:attempts 9
                                                               :max-wait 30}}))))))

(describe "dry-run rendering"
          (fn []
            (let [req {:method "POST"
                       :url "https://h/pets"
                       :query {:dry "1"}
                       :headers {:content-type "application/json"
                                 :authorization "Bearer s3cret"}
                       :body {:name "it's"}}]
              (it "describes the request with credentials redacted"
                  (fn []
                    (assert.are.equal "POST https://h/pets?dry=1\nauthorization: Bearer <redacted>\ncontent-type: application/json\n\n{\"name\":\"it's\"}"
                                      (cli.request-text req))))
              (it "renders a runnable curl command"
                  (fn []
                    (assert.are.equal "curl -X POST 'https://h/pets?dry=1' -H 'authorization: Bearer s3cret' -H 'content-type: application/json' --data-raw '{\"name\":\"it'\\''s\"}'"
                                      (cli.curl-command req))))
              (it "omits the body when there is none"
                  (fn []
                    (assert.are.equal "curl -X GET 'https://h/x'"
                                      (cli.curl-command {:method "GET"
                                                         :url "https://h/x"
                                                         :headers {}})))))
            (it "parses the flags"
                (fn []
                  (let [p (cli.parse-args ["op" "a" "--dry-run" "--curl"])]
                    (assert.is_true p.dry-run)
                    (assert.is_true p.curl))))))

(describe "cli body decoding"
          (fn []
            (it "parses JSON or YAML for JSON operations"
                (fn []
                  (assert.are.same {:a 1}
                                   (cli.decode-body "{\"a\": 1}"
                                                    "application/json"))
                  (assert.are.same {:a 1 :b "x"}
                                   (cli.decode-body "a: 1\nb: x\n"
                                                    "application/json"))))
            (it "parses structured input for form operations"
                (fn []
                  (assert.are.same {:a "1"}
                                   (cli.decode-body "a: \"1\""
                                                    "application/x-www-form-urlencoded"))))
            (it "rejects unparseable input for JSON operations"
                (fn []
                  (let [(ok err) (pcall cli.decode-body "{oops"
                                        "application/json")]
                    (assert.is_false ok)
                    (assert.is_truthy (: (tostring err) :find "invalid body" 1
                                         true)))))
            (it "sends other content types byte-for-byte"
                (fn []
                  (assert.are.equal "\137PNG\0"
                                    (cli.decode-body "\137PNG\0" "image/png"))
                  (assert.are.equal "{not json"
                                    (cli.decode-body "{not json" "text/plain"))))
            (it "keeps --body as given when there is no requestBody content type"
                (fn []
                  (assert.are.same {:a 1} (cli.decode-body "{\"a\":1}" nil))))
            (it "reads -d values raw"
                (fn []
                  (assert.are.equal "a: 1"
                                    (. (cli.parse-args ["op"
                                                        "x"
                                                        "y"
                                                        "-d"
                                                        "a: 1"])
                                       :body))))))

(describe "cli multipart fields"
          (fn []
            (it "turns @path fields into file parts and @@ into a literal @"
                (fn []
                  (let [path (os.tmpname)
                        f (io.open path :wb)]
                    (f:write "hello")
                    (f:close)
                    (let [req (cli.op-request {:path-params []
                                               :has-body? true
                                               :content-type "multipart/form-data"}
                                              {:path-params []
                                               :query {}
                                               :headers {}
                                               :body-fields [["file"
                                                              (.. "@" path)]
                                                             ["handle" "@@rex"]]})]
                      (os.remove path)
                      (assert.are.equal "hello" req.body.file.content)
                      (assert.are.equal (path:match "[^/]+$")
                                        req.body.file.filename)
                      (assert.are.equal "@rex" req.body.handle)))))))

(describe "dry-run with encoded bodies"
          (fn []
            (it "shows the multipart content type with its boundary"
                (fn []
                  (let [text (cli.request-text {:method "POST"
                                                :url "https://h/u"
                                                :headers {:content-type "multipart/form-data"}
                                                :body {:a "1"}})]
                    (assert.is_truthy (text:find "content-type: multipart/form-data; boundary=atlas-"
                                                 1 true)))))
            (it "refuses to inline binary bodies in curl"
                (fn []
                  (let [(ok err) (pcall cli.curl-command
                                        {:method "POST"
                                         :url "https://h/u"
                                         :headers {:content-type "image/png"}
                                         :body "\137PNG\0"})]
                    (assert.is_false ok)
                    (assert.is_truthy (: (tostring err) :find
                                         "cannot inline a binary body" 1 true)))))))

(describe "cli pagination options"
          (fn []
            (it "parses pagination flags"
                (fn []
                  (let [p (cli.parse-args ["op"
                                           "a"
                                           "--max-pages=3"
                                           "--no-paginate"])]
                    (assert.are.equal 3 p.max-pages)
                    (assert.is_true p.no-paginate))))
            (it "defaults to 25 pages"
                (fn []
                  (assert.are.same {:max-pages 25}
                                   (cli.paginate-options nil {} {}))))
            (it "prefers CLI over profile over config"
                (fn []
                  (assert.are.same {:max-pages 7}
                                   (cli.paginate-options {:max-pages 7} {}
                                                         {:max-pages 9}))
                  (assert.are.same {:max-pages 2}
                                   (cli.paginate-options {:max-pages 7}
                                                         {:max-pages 2} {}))))
            (it "is disabled by --no-paginate"
                (fn []
                  (assert.is_nil (cli.paginate-options nil {:no-paginate true}
                                                       {}))))))

(describe "review round 2"
          (fn []
            (it "sends valid JSON bodies byte-for-byte"
                (fn []
                  (let [op {:path-params []
                            :has-body? true
                            :content-type "application/json"}
                        req #(cli.op-request op
                                             {:path-params []
                                              :query {}
                                              :headers {}
                                              :body-fields []
                                              :body $})]
                    (assert.are.equal "\"hello\"" (. (req "\"hello\"") :body))
                    (assert.are.equal "null" (. (req "null") :body))
                    (assert.are.equal "{\"n\": 12345678901234567890}"
                                      (. (req "{\"n\": 12345678901234567890}")
                                         :body)))))
            (it "converts YAML input to JSON text"
                (fn []
                  (let [op {:path-params []
                            :has-body? true
                            :content-type "application/json"}
                        r (cli.op-request op
                                          {:path-params []
                                           :query {}
                                           :headers {}
                                           :body-fields []
                                           :body "a: 1"})]
                    (assert.are.same {:a 1} r.body))))
            (it "redacts secret query parameters in --dry-run"
                (fn []
                  (assert.is_truthy (: (cli.request-text {:method "GET"
                                                          :url "https://h/x"
                                                          :query {:api_key "S"}
                                                          :headers {}})
                                       :find "api_key=<redacted>" 1 true))))
            (it "uses --data-raw so a leading @ is not read as a file"
                (fn []
                  (assert.is_truthy (: (cli.curl-command {:method "POST"
                                                          :url "https://h/x"
                                                          :headers {:content-type "text/plain"}
                                                          :body "@/etc/passwd"})
                                       :find "--data-raw '@/etc/passwd'" 1 true))))))
