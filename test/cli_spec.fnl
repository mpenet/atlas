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
