;; ABOUTME: Specs for CLI argument parsing, request building, output formatting and options.
;; ABOUTME: Run with `make test` (busted, Fennel loader).
(local cli ;; the CLI is split across modules; the specs test it as one package
       (let [merged {}]
         (each [_ m (ipairs [:atlas.cli
                             :atlas.cli.args
                             :atlas.cli.request
                             :atlas.cli.output
                             :atlas.cli.settings
                             :atlas.cli.complete])]
           (each [k v (pairs (require m))]
             (tset merged k v)))
         merged))

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
            (it "adds auth headers to requests on first use, not up front"
                (fn []
                  (let [sent []
                        profile {:headers {:x-api-key "k"}
                                 :auth {:name "external-tool"
                                        :params {:commandline "echo tok"
                                                 :output "bearer-token"}}}
                        opts (cli.client-options "p" profile {:ssl {} :retry 0}
                                                 {}
                                                 (fn [req]
                                                   (table.insert sent req)
                                                   {:status 200 :headers {}}))]
                    (assert.are.same {:x-api-key "k"} opts.headers)
                    (opts.http-fn {:method "GET"
                                   :url "https://h/x"
                                   :headers {:x-api-key "k"}})
                    (assert.are.equal "Bearer tok"
                                      (. sent 1 :headers :authorization)))))
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
            (it "does not retry authentication failures"
                (fn []
                  (let [calls []
                        opts (cli.client-options "p"
                                                 {:auth {:name "external-tool"
                                                         :params {:commandline "exit 1"
                                                                  :output "bearer-token"}}}
                                                 {:ssl {} :retry 3} {}
                                                 (fn [req]
                                                   (table.insert calls req)
                                                   {:status 200 :headers {}}))
                        socket (require :socket)
                        t0 (socket.gettime)
                        (ok err) (pcall opts.http-fn
                                        {:method "GET"
                                         :url "https://h/x"
                                         :headers {}})]
                    (assert.is_false ok)
                    (assert.is_truthy (: (tostring err) :find
                                         "authentication failed" 1 true))
                    (assert.is_true (< (- (socket.gettime) t0) 0.5))
                    (assert.are.equal 0 (length calls)))))
            (it "lets an explicitly set header win over auth, case-insensitively"
                (fn []
                  (let [sent []
                        profile {:auth {:name "external-tool"
                                        :params {:commandline "echo tok"
                                                 :output "bearer-token"}}}
                        opts (cli.client-options "p" profile {:ssl {} :retry 0}
                                                 {}
                                                 (fn [req]
                                                   (table.insert sent req)
                                                   {:status 200 :headers {}}))]
                    (opts.http-fn {:method "GET"
                                   :url "https://h/x"
                                   :headers {:Authorization "Basic static"}})
                    (assert.are.same {:Authorization "Basic static"}
                                     (. sent 1 :headers)))))
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

(describe "JSON bodies, dry-run redaction and curl output"
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

(describe "cli server listing and choice"
          (fn []
            (it "parses --server-index and --servers"
                (fn []
                  (let [p (cli.parse-args ["op"
                                           "a"
                                           "--server-index=2"
                                           "--servers"])]
                    (assert.are.equal 2 p.server-index)
                    (assert.is_true p.servers))))
            (it "takes server-index from the profile unless given on the command line"
                (fn []
                  (assert.are.equal 2
                                    (. (cli.client-options nil
                                                           {:server-index 2}
                                                           {:ssl {}} {})
                                       :server-index))
                  (assert.are.equal 3
                                    (. (cli.client-options nil
                                                           {:server-index 2}
                                                           {:ssl {}
                                                            :server-index 3}
                                                           {})
                                       :server-index))))
            (it "formats servers, marking the selection and effective values"
                (fn []
                  (let [servers [{:url "https://api-{zone}.test/v2"
                                  :variables {:zone {:default "ch-gva-2"
                                                     :enum ["ch-gva-2"
                                                            "de-fra-1"]}}}
                                 {:url "/api"
                                  :description "relative"
                                  :variables {}}]]
                    (assert.are.equal (.. "* 1. https://api-{zone}.test/v2\n"
                                          "       zone = de-fra-1  (default: ch-gva-2; one of: ch-gva-2, de-fra-1)\n"
                                          "  2. /api — relative")
                                      (cli.format-servers servers 1
                                                          {:zone "de-fra-1"})))))
            (it "shows empty string values visibly"
                (fn []
                  (let [text (cli.format-servers [{:url "https://{env}x.test"
                                                   :variables {:env {:default ""
                                                                     :enum [""
                                                                            "pp"]}}}]
                                                 1 {})]
                    (assert.is_truthy (text:find "env = \"\"  (default: \"\"; one of: \"\", pp)"
                                                 1 true)))))))

(describe "cli short aliases"
          (fn []
            (it "accepts --q. --h. --b. --i. like their long forms"
                (fn []
                  (let [short (cli.parse-args ["op"
                                               "a"
                                               "x"
                                               "--q.status=ok"
                                               "--h.x-trace=t"
                                               "--b.pet.name=Rex"
                                               "--i.zone=z"])
                        long (cli.parse-args ["op"
                                              "a"
                                              "x"
                                              "--query.status=ok"
                                              "--header.x-trace=t"
                                              "--body.pet.name=Rex"
                                              "--input.zone=z"])]
                    (assert.are.same long.query short.query)
                    (assert.are.same long.headers short.headers)
                    (assert.are.same long.body-fields short.body-fields)
                    (assert.are.same long.input-fields short.input-fields)
                    (assert.are.same {:status "ok"} short.query))))
            (it "keeps field order across short and long forms"
                (fn []
                  (assert.are.same [["a" "1"] ["b" "2"]]
                                   (. (cli.parse-args ["op"
                                                       "a"
                                                       "x"
                                                       "--b.a=1"
                                                       "--body.b=2"])
                                      :body-fields))))
            (it "still rejects unknown dotted prefixes"
                (fn []
                  (assert.has.error #(cli.parse-args ["op" "a" "--x.y=1"])
                                    "unknown option: --x.y=1")))))

(describe "cli.check-params"
          (fn []
            (let [op {:operation-id "listPets"
                      :parameters [{:name "status" :in "query" :required true}
                                   {:name "limit" :in "query"}
                                   {:name "X-Org" :in "header" :required true}]}]
              (it "reports missing required query and header params"
                  (fn []
                    (let [(errors) (cli.check-params op {:query {} :headers {}})]
                      (assert.are.same ["missing required query parameter 'status' (--q.status=…)"
                                        "missing required header 'X-Org' (--h.X-Org=…)"]
                                       errors))))
              (it "accepts headers in any case, including ones from the profile"
                  (fn []
                    (let [(errors) (cli.check-params op
                                                     {:query {:status "a"}
                                                      :headers {:x-org "1"}})]
                      (assert.are.same [] errors))))
              (it "warns about undeclared query names, listing the declared ones"
                  (fn []
                    (let [(_ warnings) (cli.check-params op
                                                         {:query {:status "a"
                                                                  :stauts "b"}
                                                          :headers {:x-org "1"}})]
                      (assert.are.same ["list-pets does not declare query parameter 'stauts' (declared: limit, status)"]
                                       warnings))))
              (it "does not warn about extra headers"
                  (fn []
                    (let [(_ warnings) (cli.check-params op
                                                         {:query {:status "a"}
                                                          :headers {:x-org "1"
                                                                    :x-trace "t"}})]
                      (assert.are.same [] warnings)))))
            (it "parses --no-validate"
                (fn []
                  (assert.is_true (. (cli.parse-args ["op" "a" "--no-validate"])
                                     :no-validate))))))

(describe "cli.check-body"
          (fn []
            (let [op {:content-type "application/json"
                      :body-schema {:type "object"
                                    :required ["name"]
                                    :properties {:name {:type "string"}}}}]
              (it "validates table bodies"
                  (fn []
                    (assert.are.same ["body.name: required"]
                                     (cli.check-body op {:size 1}))))
              (it "validates JSON text bodies"
                  (fn []
                    (assert.are.same ["body.name: expected string, got integer"]
                                     (cli.check-body op "{\"name\": 1}"))))
              (it "accepts valid bodies and absent ones"
                  (fn []
                    (assert.are.same [] (cli.check-body op {:name "Rex"}))
                    (assert.are.same [] (cli.check-body op nil)))))
            (it "skips non-JSON operations"
                (fn []
                  (assert.are.same []
                                   (cli.check-body {:content-type "multipart/form-data"
                                                    :body-schema {:required ["file"]}}
                                                   {}))))))

(local completion-schema
       {:openapi "3.0.0"
        :info {}
        :servers [{:url "https://api-{zone}.test"
                   :variables {:zone {:default "a" :enum ["a" "b"]}}}]
        :paths {"/pets" {:get {:operationId "listPets"
                               :summary "List pets"
                               :parameters [{:name "status"
                                             :in "query"
                                             :schema {:enum ["available"
                                                             "sold"]}}
                                            {:name "limit" :in "query"}
                                            {:name "X-Org" :in "header"}]
                               :responses {}}
                         :post {:operationId "addPet"
                                :requestBody {:content {:application/json {:schema {:properties {:name {:type "string"}
                                                                                                 :tier {:enum ["small"
                                                                                                               "large"]}}}}}}
                                :responses {}}}}})

(local completion-ctx
       {:config {:profiles {:exo {:schema "S"} :warp {:schema "W"}}
                 :arazzo {:flows {:file "F"}}}
        :load-schema (fn [_] completion-schema)
        :load-doc (fn [_]
                    {:workflows [{:workflowId "createPet"
                                  :inputs {:properties {:zone {:enum ["z1"
                                                                      "z2"]}
                                                        :name {}}}}
                                 {:workflowId "deletePet"}]})})

(fn complete [line]
  (cli.complete-line line completion-ctx))

(describe "cli.complete-line"
          (fn []
            (it "completes subcommands"
                (fn []
                  (assert.are.same ["auth" "az" "completion" "op" "profile"]
                                   (complete ""))))
            (it "filters by the current word"
                (fn []
                  (assert.are.same ["auth" "az"] (complete "a"))
                  (assert.are.same ["az"] (complete "az"))))
            (it "completes profiles after op, auth and profile show"
                (fn []
                  (assert.are.same ["exo" "warp"] (complete "op "))
                  (assert.are.same ["exo"] (complete "auth e"))
                  (assert.are.same ["exo" "warp"] (complete "profile show "))))
            (it "completes operation names"
                (fn []
                  (assert.are.same ["add-pet" "list-pets"] (complete "op exo "))))
            (it "completes declared query params with the prefix as typed"
                (fn []
                  (assert.are.same ["--q.limit=" "--q.status="]
                                   (complete "op exo list-pets --q."))
                  (assert.are.same ["--query.status="]
                                   (complete "op exo list-pets --query.st"))))
            (it "completes enum values"
                (fn []
                  (assert.are.same ["--q.status=available" "--q.status=sold"]
                                   (complete "op exo list-pets --q.status="))
                  (assert.are.same ["--b.tier=large"]
                                   (complete "op exo add-pet --b.tier=l"))))
            (it "completes headers and body properties"
                (fn []
                  (assert.are.same ["--h.X-Org="]
                                   (complete "op exo list-pets --h."))
                  (assert.are.same ["--b.name=" "--b.tier="]
                                   (complete "op exo add-pet --b."))))
            (it "completes server variables and their values"
                (fn []
                  (assert.are.same ["--server.zone="]
                                   (complete "op exo --server."))
                  (assert.are.same ["--server.zone=a" "--server.zone=b"]
                                   (complete "op exo list-pets --server.zone="))))
            (it "completes flags"
                (fn []
                  (assert.are.same ["--retry-max-wait="
                                    "--retry-unsafe"
                                    "--retry="]
                                   (complete "op exo list-pets --retr"))))
            (it "completes arazzo contexts, workflows and inputs"
                (fn []
                  (assert.are.same ["flows"] (complete "az "))
                  (assert.are.same ["createPet" "deletePet"]
                                   (complete "az flows "))
                  (assert.are.same ["--i.name=" "--i.zone="]
                                   (complete "az flows createPet --i."))
                  (assert.are.same ["--i.zone=z1" "--i.zone=z2"]
                                   (complete "az flows createPet --i.zone="))))
            (it "completes shells"
                (fn []
                  (assert.are.same ["bash" "fish" "zsh"]
                                   (complete "completion "))))
            (it "returns nothing rather than failing when a schema cannot load"
                (fn []
                  (assert.are.same []
                                   (cli.complete-line "op exo "
                                                      {:config completion-ctx.config
                                                       :load-schema #(error "offline")}))))))

(describe "request log (-v)"
          (fn []
            (it "logs the full URL with secret query parameters redacted"
                (fn []
                  (let [written []
                        real io.stderr]
                    (set io.stderr {:write (fn [_ s] (table.insert written s))})
                    (let [(ok err) (pcall (cli.wrap-log-request (fn []
                                                                  {:status 200}))
                                          {:method "GET"
                                           :url "https://h/x?api_key=SECRET"
                                           :query {:page "2"}
                                           :headers {:authorization "Bearer t"}})]
                      (set io.stderr real)
                      (assert.is_true ok err)
                      (let [text (table.concat written)]
                        (assert.is_truthy (text:find "> GET https://h/x?api_key=<redacted>&page=2"
                                                     1 true))
                        (assert.is_nil (text:find "SECRET" 1 true))
                        (assert.is_nil (text:find "Bearer t" 1 true)))))))))

(describe "explicit nulls and repeated params"
          (fn []
            (it "accepts null for a required nullable property"
                (fn []
                  (assert.are.same []
                                   (cli.check-body {:content-type "application/json"
                                                    :body-schema {:required ["a"]
                                                                  :properties {:a {:type "string"
                                                                                   :nullable true}}}}
                                                   "{\"a\": null}"))))
            (it "builds arrays from repeated query flags"
                (fn []
                  (assert.are.same {:tag ["a" "b" "c"] :one "x"}
                                   (. (cli.parse-args ["op"
                                                       "s"
                                                       "o"
                                                       "--q.tag=a"
                                                       "--query.tag=b"
                                                       "--q.tag=c"
                                                       "--q.one=x"])
                                      :query))))
            (it "joins repeated header flags"
                (fn []
                  (assert.are.same {:accept "a/b, c/d"}
                                   (. (cli.parse-args ["op"
                                                       "s"
                                                       "o"
                                                       "--h.accept=a/b"
                                                       "--h.accept=c/d"])
                                      :headers))))))

(describe "option table parsing"
          (fn []
            (it "accepts --flag VALUE as well as --flag=VALUE"
                (fn []
                  (let [p (cli.parse-args ["op"
                                           "a"
                                           "--timeout"
                                           "5"
                                           "--output"
                                           "yaml"
                                           "--retry=1"])]
                    (assert.are.equal 5 p.timeout)
                    (assert.are.equal "yaml" p.output)
                    (assert.are.equal 1 p.retry))))
            (it "rejects non-numeric values for numeric options"
                (fn []
                  (assert.has.error #(cli.parse-args ["op" "a" "--timeout=abc"])
                                    "--timeout expects a number, got 'abc'")))
            (it "rejects values on switches"
                (fn []
                  (assert.has.error #(cli.parse-args ["op" "a" "--list=yes"])
                                    "--list takes no value")))
            (it "requires a value for value options at the end of the line"
                (fn []
                  (assert.has.error #(cli.parse-args ["op" "a" "--timeout"])
                                    "--timeout requires a value")))
            (it "parses --ssl. and --server. families"
                (fn []
                  (let [p (cli.parse-args ["op"
                                           "a"
                                           "--ssl.verify=none"
                                           "--server.zone=z"])]
                    (assert.are.same {:verify "none"} p.ssl)
                    (assert.are.same {:zone "z"} p.server-vars))))
            (it "has one entry per option for usage and completion"
                (fn []
                  (let [seen {}]
                    (each [_ o (ipairs cli.options)]
                      (each [_ n (ipairs (or o.names []))]
                        (assert.is_nil (. seen n) n)
                        (tset seen n true))))))))

(describe "CLI edge cases"
          (fn []
            (it "completion skips the values of separated options"
                (fn []
                  (assert.are.same ["add-pet" "list-pets"]
                                   (complete "op --output yaml exo "))
                  (assert.are.same ["list-pets"]
                                   (complete "op --timeout 5 exo li"))))
            (it "merges repeated headers regardless of case"
                (fn []
                  (assert.are.same {:X-A "1, 2"}
                                   (. (cli.parse-args ["op"
                                                       "s"
                                                       "o"
                                                       "--h.X-A=1"
                                                       "--h.x-a=2"])
                                      :headers))))))
