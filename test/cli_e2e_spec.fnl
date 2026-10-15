;; ABOUTME: End-to-end specs for the atlas commands, run in-process through
;; ABOUTME: cli.run with a fake HTTP transport and an in-memory config.
(local cli (require :atlas.cli))

(fn respond [status body ?headers]
  (let [json (require :lunajson)
        raw (if (= nil body) "" (json.encode body))]
    {:status status
     :headers (or ?headers {:content-type "application/json"})
     :body body
     :raw raw}))

(fn routes-transport [routes]
  "Fake transport answering by \"METHOD URL\" (URL with query); records requests."
  (let [requests []]
    (values (fn [req]
              (let [util (require :atlas.util)
                    url (util.append-query req.url (or req.query {}))
                    route (or (. routes (.. req.method " " url)) (. routes url))]
                (table.insert requests req)
                (if (= (type route) :function) (route req)
                    route route
                    (respond 404 {:error "no route"})))) requests)))

(local config {:profiles {:p {:schema "test/fixtures/cli-api.json"
                              :headers {:x-org "o1"}
                              :auth {:name "bearer" :params {:token "t0k"}}}
                          :broken-auth {:schema "test/fixtures/cli-api.json"
                                        :auth {:name "external-tool"
                                               :params {:commandline "exit 1"
                                                        :output "bearer-token"}}}
                          :yaml {:schema "test/fixtures/cli-api.json"
                                 :output "yaml"
                                 :no-color true}
                          :counted {:schema "test/fixtures/cli-api.json"
                                    :auth {:name "external-tool"
                                           :params {:commandline "echo run >> build/test-home/auth-runs; echo tok"
                                                    :output "bearer-token"}}}}
               :arazzo {:flows {:file "test/fixtures/cli-flow.arazzo.json"
                                :profile "yaml"}}})

(var current-config config)

(fn with-config [cfg f]
  "Runs f with cfg as the CLI config."
  (set current-config cfg)
  (let [(ok result) (pcall f)]
    (set current-config config)
    (assert ok result)
    result))

(fn atlas-run [args ?routes]
  "Run the CLI in-process; returns {:code :out :err :requests}."
  (let [(transport requests) (routes-transport (or ?routes {}))
        out []
        err []
        real-print _G.print
        real-stderr io.stderr]
    (set _G.print (fn [...]
                    (table.insert out
                                  (table.concat (icollect [_ v (ipairs [...])]
                                                  (tostring v))
                                                "\t"))))
    (set io.stderr {:write (fn [_ s] (table.insert err s))})
    (let [(ok code) (pcall cli.run args {: transport :config current-config})]
      (set _G.print real-print)
      (set io.stderr real-stderr)
      (assert ok code)
      {: code :out (table.concat out "\n") :err (table.concat err) : requests})))

(describe "atlas op"
          (fn []
            (it "sends the request with profile headers and auth, exit 0"
                (fn []
                  (let [r (atlas-run ["op" "p" "get-pet" "7" "--no-color"]
                                     {"GET https://api.test/pets/7" (respond 200
                                                                             {:name "Rex"})})]
                    (assert.are.equal 0 r.code)
                    (assert.is_truthy (r.out:find "\"name\": \"Rex\"" 1 true))
                    (assert.are.equal "Bearer t0k"
                                      (. r.requests 1 :headers :authorization))
                    (assert.are.equal "o1" (. r.requests 1 :headers :x-org)))))
            (it "maps HTTP errors to exit codes 4 and 5"
                (fn []
                  (assert.are.equal 4
                                    (. (atlas-run ["op" "p" "get-pet" "1"])
                                       :code))
                  (assert.are.equal 5
                                    (. (atlas-run ["op"
                                                   "p"
                                                   "get-pet"
                                                   "1"
                                                   "--retry=0"]
                                                  {"GET https://api.test/pets/1" (respond 503
                                                                                          {})})
                                       :code))
                  (assert.are.equal 0
                                    (. (atlas-run ["op"
                                                   "p"
                                                   "get-pet"
                                                   "1"
                                                   "--ignore-status"
                                                   "--retry=0"]
                                                  {"GET https://api.test/pets/1" (respond 503
                                                                                          {})})
                                       :code))))
            (it "blocks invalid bodies before sending"
                (fn []
                  (let [r (atlas-run ["op" "p" "add-pet" "--b.size=1"])]
                    (assert.are.equal 1 r.code)
                    (assert.is_truthy (r.err:find "body.name: required" 1 true))
                    (assert.are.equal 0 (length r.requests)))))
            (it "sends anyway with --no-validate"
                (fn []
                  (let [r (atlas-run ["op"
                                      "p"
                                      "add-pet"
                                      "--b.size=1"
                                      "--no-validate"]
                                     {"POST https://api.test/pets" (respond 201
                                                                            {})})]
                    (assert.are.equal 0 r.code)
                    (assert.are.equal 1 (length r.requests)))))
            (it "counts the auth header toward required headers"
                (fn []
                  (assert.are.equal 0
                                    (. (atlas-run ["op" "p" "get-secure"]
                                                  {"GET https://api.test/secure" (respond 200
                                                                                          {})})
                                       :code))))
            (it "does not authenticate for --help, --list or --servers"
                (fn []
                  (assert.are.equal 0
                                    (. (atlas-run ["op" "broken-auth" "--list"])
                                       :code))
                  (assert.are.equal 0
                                    (. (atlas-run ["op"
                                                   "broken-auth"
                                                   "get-pet"
                                                   "--help"])
                                       :code))
                  (assert.are.equal 0
                                    (. (atlas-run ["op"
                                                   "broken-auth"
                                                   "--servers"])
                                       :code))))
            (it "reports an auth failure when a request needs it"
                (fn []
                  (let [r (atlas-run ["op" "broken-auth" "get-pet" "1"])]
                    (assert.are.equal 1 r.code)
                    (assert.is_truthy (r.err:find "authentication failed" 1
                                                  true)))))
            (it "prints the request for --dry-run without sending"
                (fn []
                  (let [r (atlas-run ["op"
                                      "p"
                                      "list-pets"
                                      "--q.status=sold"
                                      "--dry-run"])]
                    (assert.are.equal 0 r.code)
                    (assert.is_truthy (r.out:find "GET https://api.test/pets?status=sold"
                                                  1 true))
                    (assert.are.equal 0 (length r.requests)))))
            (it "escapes control characters of the spec's text"
                (fn []
                  (let [spec (.. (os.tmpname) ".json")]
                    (with-open [f (io.open spec :w)]
                      (f:write "{\"openapi\":\"3.0.0\",\"info\":{},\"servers\":[{\"url\":\"https://h\",\"description\":\"s\\u001b[2J\"}],\"paths\":{\"/x\":{\"get\":{\"operationId\":\"getX\",\"summary\":\"list \\u001b]52;c;cHduZWQ=\\u0007\",\"description\":\"d\\u001b[31m\",\"responses\":{}}}}}"))
                    (let [outs (icollect [_ args (ipairs [["op" spec "--list"]
                                                          ["op"
                                                           spec
                                                           "get-x"
                                                           "--help"]
                                                          ["op"
                                                           spec
                                                           "--servers"]])]
                                 (. (atlas-run args) :out))]
                      (os.remove spec)
                      (each [_ out (ipairs outs)]
                        (assert.is_nil (out:find "\27" 1 true))
                        (assert.is_truthy (out:find "\\x1B" 1 true)))))))
            (it "escapes control characters in requests, headers and error bodies"
                (fn []
                  (let [spec (.. (os.tmpname) ".json")]
                    (with-open [f (io.open spec :w)]
                      (f:write "{\"openapi\":\"3.0.0\",\"info\":{},\"servers\":[{\"url\":\"https://h/a\\u001b]0;T\\u0007\"}],\"paths\":{\"/x\":{\"get\":{\"operationId\":\"getX\",\"responses\":{}}}}}"))
                    (let [outs (icollect [_ extra (ipairs [["--dry-run"]
                                                           ["--curl"]])]
                                 (let [r (atlas-run (doto ["op" spec "get-x"]
                                                      (table.insert (. extra 1))))]
                                   (.. r.out r.err)))
                          url "https://h/a\27]0;T\7/x"
                          routes {url {:status 400
                                       :headers {:content-type "text/plain"
                                                 :x-evil "a\27[2Jb"}
                                       :body "bad \27[31m"
                                       :raw "bad \27[31m"}}
                          v (atlas-run ["op" spec "get-x" "-v"] routes)]
                      (os.remove spec)
                      (table.insert outs (.. v.out v.err))
                      (each [_ out (ipairs outs)]
                        (assert.is_nil (out:find "\27" 1 true) out))))))
            (it "escapes control characters in errors and warnings"
                (fn []
                  (let [spec (.. (os.tmpname) ".json")]
                    (with-open [f (io.open spec :w)]
                      (f:write "{\"openapi\":\"3.0.0\",\"info\":{},\"servers\":[{\"url\":\"https://h\"}],\"paths\":{\"/x\":{\"get\":{\"operationId\":\"getX\",\"parameters\":[{\"name\":\"q\\u001b]0;P\\u0007\",\"in\":\"query\"}],\"responses\":{\"200\":{\"$ref\":\"#/nope\\u001b[31m\"}}}}}}"))
                    (let [r (atlas-run ["op" spec "--list"])]
                      (assert.are.equal 1 r.code)
                      (assert.is_nil (r.err:find "\27" 1 true))
                      (assert.is_truthy (r.err:find "\\x1B" 1 true)))
                    (with-open [f (io.open spec :w)]
                      (f:write "{\"openapi\":\"3.0.0\",\"info\":{},\"servers\":[{\"url\":\"https://h\"}],\"paths\":{\"/x\":{\"get\":{\"operationId\":\"getX\",\"parameters\":[{\"name\":\"q\\u001b]0;P\\u0007\",\"in\":\"query\"}],\"responses\":{}}}}}"))
                    (let [r (atlas-run ["op"
                                        spec
                                        "get-x"
                                        "--q.zz=1"
                                        "--dry-run"])]
                      (os.remove spec)
                      (assert.is_truthy (r.err:find "warning" 1 true))
                      (assert.is_nil (r.err:find "\27" 1 true))))))
            (it "sends --q. values of JSON query parameters as given"
                (fn []
                  (let [spec (.. (os.tmpname) ".json")]
                    (with-open [f (io.open spec :w)]
                      (f:write "{\"openapi\":\"3.0.0\",\"info\":{},\"servers\":[{\"url\":\"https://h\"}],\"paths\":{\"/s\":{\"get\":{\"operationId\":\"search\",\"parameters\":[{\"name\":\"filter\",\"in\":\"query\",\"content\":{\"application/json\":{\"schema\":{\"type\":\"object\"}}}}],\"responses\":{}}}}}"))
                    (let [r (atlas-run ["op"
                                        spec
                                        "search"
                                        "--q.filter={\"a\":1}"
                                        "--dry-run"])]
                      (os.remove spec)
                      (assert.is_truthy (r.out:find "GET https://h/s?filter=%7B%22a%22%3A1%7D"
                                                    1 true)
                                        r.out)))))
            (it "reads a query API key only when a request is sent"
                (fn []
                  (with-config {:profiles {:q {:schema "test/fixtures/cli-api.json"
                                               :auth {:name "api-key"
                                                      :params {:in "query"
                                                               :name "apikey"
                                                               :value "env:ATLAS_TEST_UNSET_KEY"}}}}}
                    #(do
                       (assert.are.equal 0
                                         (. (atlas-run ["op" "q" "--list"])
                                            :code))
                       (assert.are.equal 0
                                         (. (atlas-run ["op"
                                                        "q"
                                                        "list-pets"
                                                        "--help"])
                                            :code))
                       (let [r (atlas-run ["op" "q" "list-pets" "--dry-run"])]
                         (assert.are.equal 0 r.code)
                         (assert.is_truthy (r.out:find "apikey=<redacted>" 1
                                                       true)
                                           r.out))
                       (let [r (atlas-run ["op" "q" "list-pets"])]
                         (assert.are.equal 1 r.code)
                         (assert.is_truthy (r.err:find "ATLAS_TEST_UNSET_KEY" 1
                                                       true)))))))
            (it "rejects body fields on top of an array body"
                (fn []
                  (let [r (atlas-run ["op"
                                      "p"
                                      "add-pet"
                                      "-d"
                                      "[1]"
                                      "--b.x=1"
                                      "--no-validate"
                                      "--dry-run"])]
                    (assert.are.equal 1 r.code)
                    (assert.is_truthy (r.err:find "require --body to be a JSON object"
                                                  1 true)))))
            (it "rejects a document that is not an OpenAPI spec"
                (fn []
                  (let [path (.. (os.tmpname) ".json")
                        (transport) (routes-transport {"GET https://api.test/echo" {:status 200
                                                                                    :headers {}
                                                                                    :raw "{\"a\":1}"}})]
                    (with-open [f (io.open path :w)]
                      (f:write "{\"a\":1}"))
                    (let [r (atlas-run ["op" path "--list"])
                          real-stderr io.stderr
                          err []]
                      (os.remove path)
                      (assert.are.equal 1 r.code)
                      (assert.is_truthy (r.err:find "is not an OpenAPI document"
                                                    1 true)
                                        r.err)
                      (set io.stderr {:write (fn [_ s] (table.insert err s))})
                      (let [code (cli.run ["op"
                                           "https://api.test/echo"
                                           "--list"]
                                          {: transport
                                           :config {}
                                           :schema-cache false})]
                        (set io.stderr real-stderr)
                        (assert.are.equal 1 code)
                        (assert.is_truthy (: (table.concat err) :find
                                             "is not an OpenAPI document" 1 true)))))))
            (it "explains a profile without a schema"
                (fn []
                  (let [r (with-config {:profiles {:noschema {:base-url "https://api.test"}}}
                            #(atlas-run ["op" "noschema" "list-pets"]))]
                    (assert.are.equal 1 r.code)
                    (assert.is_truthy (r.err:find "profile noschema has no schema"
                                                  1 true)
                                      r.err))))
            (it "validates bodies and uploads files whatever the media type's case"
                (fn []
                  (let [spec (.. (os.tmpname) ".json")
                        file (.. (os.tmpname) ".txt")]
                    (with-open [f (io.open file :w)]
                      (f:write "hello"))
                    (with-open [f (io.open spec :w)]
                      (f:write "{\"openapi\":\"3.0.0\",\"info\":{},\"servers\":[{\"url\":\"https://h\"}],\"paths\":{\"/j\":{\"post\":{\"operationId\":\"create\",\"requestBody\":{\"content\":{\"Application/JSON\":{\"schema\":{\"type\":\"object\",\"required\":[\"name\"]}}}},\"responses\":{}}},\"/m\":{\"post\":{\"operationId\":\"upload\",\"requestBody\":{\"content\":{\"Multipart/Form-Data\":{\"schema\":{\"type\":\"object\"}}}},\"responses\":{}}}}}"))
                    (let [v (atlas-run ["op"
                                        spec
                                        "create"
                                        "--b.x=1"
                                        "--dry-run"])
                          m (atlas-run ["op"
                                        spec
                                        "upload"
                                        (.. "--b.file=@" file)
                                        "--dry-run"])]
                      (os.remove spec)
                      (os.remove file)
                      (assert.are.equal 1 v.code)
                      (assert.is_truthy (v.err:find "body.name: required" 1
                                                    true))
                      (assert.is_truthy (m.out:find "filename=" 1 true) m.out)))))
            (it "rejects a repeated JSON query parameter"
                (fn []
                  (let [spec (.. (os.tmpname) ".json")]
                    (with-open [f (io.open spec :w)]
                      (f:write "{\"openapi\":\"3.0.0\",\"info\":{},\"servers\":[{\"url\":\"https://h\"}],\"paths\":{\"/s\":{\"get\":{\"operationId\":\"search\",\"parameters\":[{\"name\":\"filter\",\"in\":\"query\",\"content\":{\"application/json\":{\"schema\":{}}}}],\"responses\":{}}}}}"))
                    (let [r (atlas-run ["op"
                                        spec
                                        "search"
                                        "--q.filter={\"a\":1}"
                                        "--q.filter={\"b\":2}"
                                        "--dry-run"])]
                      (os.remove spec)
                      (assert.are.equal 1 r.code)
                      (assert.is_truthy (r.err:find "filter takes one JSON value"
                                                    1 true)
                                        r.err)))))
            (it "counts query parameters the profile or a query key adds"
                (fn []
                  (let [spec (.. (os.tmpname) ".json")]
                    (with-open [f (io.open spec :w)]
                      (f:write "{\"openapi\":\"3.0.0\",\"info\":{},\"servers\":[{\"url\":\"https://h\"}],\"paths\":{\"/items\":{\"get\":{\"operationId\":\"listItems\",\"parameters\":[{\"name\":\"appid\",\"in\":\"query\",\"required\":true}],\"responses\":{}}}}}"))
                    (let [cfg {:profiles {:q {:schema spec
                                              :auth {:name "api-key"
                                                     :params {:in "query"
                                                              :name "appid"
                                                              :value "K"}}}
                                          :pq {:schema spec
                                               :query {:appid "P"}}}}
                          rq (with-config cfg
                               #(atlas-run ["op" "q" "list-items" "--dry-run"]))
                          rpq (with-config cfg
                                #(atlas-run ["op"
                                             "pq"
                                             "list-items"
                                             "--dry-run"]))]
                      (os.remove spec)
                      (assert.are.equal 0 rq.code)
                      (assert.are.equal 0 rpq.code)
                      (assert.is_nil (rpq.err:find "warning" 1 true))))))
            (it "rejects a body for an operation that takes none"
                (fn []
                  (each [_ extra (ipairs ["-d={}" "--b.z=2"])]
                    (let [r (atlas-run ["op"
                                        "p"
                                        "get-pet"
                                        "7"
                                        extra
                                        "--dry-run"])]
                      (assert.are.equal 1 r.code)
                      (assert.is_truthy (r.err:find "get-pet takes no request body"
                                                    1 true))))))
            (it "doesn't retry a request its signing tool failed to sign"
                (fn []
                  (let [count-file (os.tmpname)]
                    (let [r (with-config {:profiles {:sig {:schema "test/fixtures/cli-api.json"
                                                           :auth {:name "external-tool"
                                                                  :params {:commandline (.. "echo x >> "
                                                                                            count-file
                                                                                            "; exit 3")}}}}}
                              #(atlas-run ["op" "sig" "list-pets"]))
                          runs (with-open [f (io.open count-file)]
                                 (length (f:read :*a)))]
                      (os.remove count-file)
                      (assert.are.equal 1 r.code)
                      (assert.is_truthy (r.err:find "external auth command failed"
                                                    1 true))
                      ;; "x\n" once
                      (assert.are.equal 2 runs)))))
            (it "does not run the signing tool for --dry-run"
                (fn []
                  (let [marker (os.tmpname)]
                    (os.remove marker)
                    (let [r (with-config {:profiles {:sign {:schema "test/fixtures/cli-api.json"
                                                            :auth {:name "external-tool"
                                                                   :params {:commandline (.. "touch "
                                                                                             marker
                                                                                             "; echo '{}'")}}}}}
                              #(atlas-run ["op" "sign" "list-pets" "--dry-run"]))
                          ran (io.open marker)]
                      (when ran
                        (ran:close)
                        (os.remove marker))
                      (assert.are.equal 0 r.code)
                      (assert.is_nil ran)))))
            (it "uses the profile's output format"
                (fn []
                  (let [r (atlas-run ["op" "yaml" "get-pet" "3"]
                                     {"GET https://api.test/pets/3" (respond 200
                                                                             {:name "Rex"})})]
                    (assert.are.equal "name: Rex" r.out))))
            (it "reports unknown operations"
                (fn []
                  (let [r (atlas-run ["op" "p" "nope"])]
                    (assert.are.equal 1 r.code)
                    (assert.is_truthy (r.err:find "Unknown operation: nope" 1
                                                  true)))))
            (it "fetches a schema URL, authenticating only after a 401"
                (fn []
                  (let [schema-text (let [f (io.open "test/fixtures/cli-api.json")]
                                      (f:read :*a))
                        cfg-run (fn [args routes]
                                  (let [(transport requests) (routes-transport routes)
                                        real-print _G.print]
                                    (set _G.print (fn []))
                                    (let [code (cli.run args
                                                        {: transport
                                                         :config {:profiles {:remote {:schema "https://api.test/openapi.json"
                                                                                      :auth {:name "bearer"
                                                                                             :params {:token "t"}}}}}
                                                         :schema-cache false})]
                                      (set _G.print real-print)
                                      (values code requests))))
                        (code requests) (cfg-run ["op" "remote" "--list"]
                                                 {"GET https://api.test/openapi.json" (fn [req]
                                                                                        (if (. req.headers
                                                                                               :authorization)
                                                                                            {:status 200
                                                                                             :headers {}
                                                                                             :raw schema-text}
                                                                                            (respond 401
                                                                                                     {})))})]
                    (assert.are.equal 0 code)
                    (assert.are.equal 2 (length requests))
                    (assert.is_nil (. requests 1 :headers :authorization)))))
            (it "fetches the spec within --timeout"
                (fn []
                  (let [(transport requests) (routes-transport {"GET https://api.test/openapi.json" (respond 500
                                                                                                             {})})
                        real-stderr io.stderr]
                    (set io.stderr {:write (fn [])})
                    (cli.run ["op" "remote" "--list" "--timeout" "2"]
                             {: transport
                              :config {:profiles {:remote {:schema "https://api.test/openapi.json"}}}
                              :schema-cache false})
                    (set io.stderr real-stderr)
                    (assert.are.equal 2 (. requests 1 :timeout)))))
            (it "keeps profile headers from the documents a foreign spec refers to"
                (fn []
                  (let [spec "{\"openapi\":\"3.0.0\",\"info\":{},\"paths\":{\"/x\":{\"get\":{\"operationId\":\"getX\",\"parameters\":[{\"$ref\":\"part.json#/p\"}],\"responses\":{}}}}}"
                        (transport requests) (routes-transport {"GET https://specs.test/spec.json" {:status 200
                                                                                                    :headers {}
                                                                                                    :raw spec}
                                                                "GET https://specs.test/part.json" {:status 200
                                                                                                    :headers {}
                                                                                                    :raw "{\"p\":{\"name\":\"q\",\"in\":\"query\"}}"}})
                        code (cli.run ["op" "remote" "--list"]
                                      {: transport
                                       :config {:profiles {:remote {:schema "https://specs.test/spec.json"
                                                                    :base-url "https://api.test"
                                                                    :headers {:x-team "H"}}}}
                                       :schema-cache false})]
                    (assert.are.equal 0 code)
                    (assert.are.equal 2 (length requests))
                    (each [_ req (ipairs requests)]
                      (assert.is_nil (. req.headers :x-team))))))
            (it "never sends placeholder credentials for a dry run's spec"
                (fn []
                  (let [(transport requests) (routes-transport {"GET https://api.test/openapi.json" (respond 401
                                                                                                             {})})
                        real-stderr io.stderr]
                    (set io.stderr {:write (fn [])})
                    (cli.run ["op" "remote" "list-pets" "--dry-run"]
                             {: transport
                              :config {:profiles {:remote {:schema "https://api.test/openapi.json"
                                                           :auth {:name "bearer"
                                                                  :params {:token "t"}}}}}
                              :schema-cache false})
                    (set io.stderr real-stderr)
                    (each [_ req (ipairs requests)]
                      (assert.is_nil (. req.headers :authorization))))))
            (it "logs the fetches of a spec and its documents under -v"
                (fn []
                  (let [spec "{\"openapi\":\"3.0.0\",\"info\":{},\"servers\":[{\"url\":\"https://specs.test\"}],\"paths\":{\"/x\":{\"get\":{\"operationId\":\"getX\",\"parameters\":[{\"$ref\":\"part.json#/p\"}],\"responses\":{}}}}}"
                        (transport) (routes-transport {"GET https://specs.test/spec.json" {:status 200
                                                                                           :headers {}
                                                                                           :raw spec}
                                                       "GET https://specs.test/part.json" {:status 200
                                                                                           :headers {}
                                                                                           :raw "{\"p\":{\"name\":\"q\",\"in\":\"query\"}}"}})
                        err []
                        real-stderr io.stderr]
                    (set io.stderr {:write (fn [_ s] (table.insert err s))})
                    (cli.run ["op"
                              "https://specs.test/spec.json"
                              "--list"
                              "-v"]
                             {: transport :config {} :schema-cache false})
                    (set io.stderr real-stderr)
                    (let [text (table.concat err)]
                      (assert.is_truthy (text:find "> GET https://specs.test/spec.json"
                                                   1 true))
                      (assert.is_truthy (text:find "> GET https://specs.test/part.json"
                                                   1 true))))))
            (it "fetches a spec protected by a query API key after a 401"
                (fn []
                  (let [schema-text (with-open [f (io.open "test/fixtures/cli-api.json")]
                                      (f:read :*a))
                        (transport requests) (routes-transport {"GET https://api.test/openapi.json" (respond 401
                                                                                                             {})
                                                                "GET https://api.test/openapi.json?k=K" {:status 200
                                                                                                         :headers {}
                                                                                                         :raw schema-text}})
                        code (cli.run ["op" "remote" "--list"]
                                      {: transport
                                       :config {:profiles {:remote {:schema "https://api.test/openapi.json"
                                                                    :auth {:name "api-key"
                                                                           :params {:in "query"
                                                                                    :name "k"
                                                                                    :value "K"}}}}}
                                       :schema-cache false})]
                    (assert.are.equal 0 code)
                    (assert.are.equal 2 (length requests))
                    (assert.is_nil (?. requests 1 :query :k)))))
            (it "keeps profile headers and credentials from a spec on another origin"
                (fn []
                  (let [(transport requests) (routes-transport {"GET https://specs.test/openapi.json" (respond 401
                                                                                                               {})})
                        code (cli.run ["op" "remote" "--list"]
                                      {: transport
                                       :config {:profiles {:remote {:schema "https://specs.test/openapi.json"
                                                                    :base-url "https://api.test"
                                                                    :headers {:authorization "Bearer P"}
                                                                    :auth {:name "bearer"
                                                                           :params {:token "t"}}}}}
                                       :schema-cache false})]
                    (assert.are.equal 1 code)
                    (assert.are.equal 1 (length requests))
                    (assert.is_nil (. requests 1 :headers :authorization)))))))

(describe "atlas az"
          (fn []
            (it "runs a workflow with the context's profile and prints outputs in its format"
                (fn []
                  (let [r (atlas-run ["az" "flows" "fetchPet" "-i" "id=7"]
                                     {"GET https://api.test/pets/7" (respond 200
                                                                             {:name "Rex"})})]
                    (assert.are.equal 0 r.code)
                    (assert.are.equal "name: Rex" r.out))))
            (it "validates workflow inputs against the inputs schema"
                (fn []
                  (let [r (atlas-run ["az"
                                      "flows"
                                      "fetchPet"
                                      "--inputs"
                                      "{\"id\": 7}"])]
                    (assert.are.equal 1 r.code)
                    (assert.is_truthy (r.err:find "inputs.id: expected string, got integer"
                                                  1 true))
                    (assert.are.equal 0 (length r.requests)))))
            (it "prints each step's response with --arazzo-output steps"
                (fn []
                  (let [r (atlas-run ["az"
                                      "flows"
                                      "fetchPet"
                                      "-i"
                                      "id=7"
                                      "--arazzo-output"
                                      "steps"]
                                     {"GET https://api.test/pets/7" (respond 200
                                                                             {:name "Rex"})})]
                    (assert.are.equal 0 r.code)
                    (assert.are.equal "--- get ---\nname: Rex\n--- outputs ---\nname: Rex"
                                      r.out))))
            (it "prints requests and responses with --arazzo-output full"
                (fn []
                  (let [r (atlas-run ["az"
                                      "flows"
                                      "fetchPet"
                                      "-i"
                                      "id=7"
                                      "--arazzo-output"
                                      "full"]
                                     {"GET https://api.test/pets/7" (respond 200
                                                                             {:name "Rex"})})]
                    (assert.are.equal 0 r.code)
                    (assert.are.equal "--- get request ---\noperation: getPet\n--- get response HTTP 200 ---\nname: Rex\n--- outputs ---\nname: Rex"
                                      r.out))))
            (it "lists the workflows of a document"
                (fn []
                  (let [r (atlas-run ["az" "flows"])]
                    (assert.are.equal 0 r.code)
                    (assert.are.equal "fetchPet" r.out))))
            (it "takes inputs from -d and --b. fields"
                (fn []
                  (let [routes {"GET https://api.test/pets/7" (respond 200
                                                                       {:name "Rex"})}]
                    (assert.are.equal "name: Rex"
                                      (. (atlas-run ["az"
                                                     "flows"
                                                     "fetchPet"
                                                     "-d"
                                                     "{\"id\": \"7\"}"]
                                                    routes)
                                         :out))
                    (assert.are.equal "name: Rex"
                                      (. (atlas-run ["az"
                                                     "flows"
                                                     "fetchPet"
                                                     "--b.id=7"]
                                                    routes)
                                         :out)))))
            (it "prints workflow help"
                (fn []
                  (let [r (atlas-run ["az" "flows" "fetchPet" "--help"])]
                    (assert.are.equal 0 r.code)
                    (assert.is_truthy (r.out:find "fetchPet" 1 true))
                    (assert.are.equal 0 (length r.requests)))))
            (it "escapes control characters of step ids"
                (fn []
                  (let [file (.. (os.tmpname) ".json")]
                    (with-open [f (io.open file :w)]
                      (f:write "{\"arazzo\":\"1.0.0\",\"info\":{},\"sourceDescriptions\":[{\"name\":\"api\",\"type\":\"openapi\",\"url\":\""
                               (os.getenv :PWD)
                               "/test/fixtures/cli-api.json\"}],\"workflows\":[{\"workflowId\":\"w\",\"steps\":[{\"stepId\":\"s\\u001b]0;P\\u0007\",\"operationId\":\"getPet\",\"parameters\":[{\"name\":\"id\",\"in\":\"path\",\"value\":7}]}]}]}"))
                    (let [routes {"GET https://api.test/pets/7" (respond 200
                                                                         {:name "Rex"})}
                          verbose (atlas-run ["az" file "w" "-v"] routes)
                          steps (atlas-run ["az"
                                            file
                                            "w"
                                            "--arazzo-output"
                                            "full"]
                                           routes)]
                      (os.remove file)
                      (assert.are.equal 0 verbose.code)
                      (assert.is_nil (verbose.err:find "\27" 1 true))
                      (assert.is_nil (steps.out:find "\27" 1 true))
                      (assert.is_truthy (steps.out:find "\\x1B" 1 true))))))
            (it "lists workflows whose id is not a string"
                (fn []
                  (let [file (.. (os.tmpname) ".json")]
                    (with-open [f (io.open file :w)]
                      (f:write "{\"arazzo\":\"1.0.0\",\"info\":{},\"workflows\":[{\"workflowId\":5,\"steps\":[]},{\"steps\":[]}]}"))
                    (let [r (atlas-run ["az" file])]
                      (os.remove file)
                      (assert.are.equal 0 r.code)
                      (assert.is_truthy (r.out:find "5" 1 true))))))
            (it "rejects an unknown profile"
                (fn []
                  (let [r (atlas-run ["az"
                                      "flows"
                                      "fetchPet"
                                      "-i"
                                      "id=7"
                                      "--profile"
                                      "typo"])]
                    (assert.are.equal 1 r.code)
                    (assert.is_truthy (r.err:find "Profile not found: typo" 1
                                                  true))
                    (assert.are.equal 0 (length r.requests)))))
            (it "rejects unknown workflows and --dry-run"
                (fn []
                  (let [r (atlas-run ["az" "flows" "nope"])]
                    (assert.are.equal 1 r.code)
                    (assert.are.equal "Unknown workflow: nope\n" r.err))
                  (let [r (atlas-run ["az" "flows" "fetchPet" "--dry-run"])]
                    (assert.are.equal 1 r.code)
                    (assert.is_truthy (r.err:find "not supported for az" 1 true)))))
            (it "reports a failed workflow in progress mode"
                (fn []
                  (let [r (atlas-run ["az"
                                      "flows"
                                      "fetchPet"
                                      "-i"
                                      "id=7"
                                      "--arazzo-output"
                                      "progress"])]
                    (assert.are.equal 1 r.code)
                    (assert.is_truthy (r.err:find "workflow fetchPet failed" 1
                                                  true)))))
            (it "fails with exit 1 when a step fails"
                (fn []
                  (let [r (atlas-run ["az" "flows" "fetchPet" "-i" "id=7"])]
                    (assert.are.equal 1 r.code)
                    (assert.is_truthy (r.err:find "step 'get' failed" 1 true)))))))

(describe "other commands"
          (fn []
            (it "prints usage without arguments"
                (fn []
                  (let [r (atlas-run [])]
                    (assert.are.equal 0 r.code)
                    (assert.is_truthy (r.out:find "Usage: atlas" 1 true)))))
            (it "prints its version and the HTTP library it uses"
                (fn []
                  (let [r (atlas-run ["--version"])
                        version (. (require :atlas) :version)]
                    (assert.are.equal 0 r.code)
                    (assert.is_truthy (version:match "^%d+%.%d+%.%d+"))
                    (assert.is_truthy (r.out:find (.. "atlas " version
                                                      " (libcurl/")
                                                  1 true)))))
            (it "lists profiles sorted"
                (fn []
                  (let [r (atlas-run ["profile" "list"])]
                    (assert.are.equal "broken-auth\ttest/fixtures/cli-api.json\ncounted\ttest/fixtures/cli-api.json\np\ttest/fixtures/cli-api.json\nyaml\ttest/fixtures/cli-api.json"
                                      r.out))))
            (it "prints static credentials for atlas auth"
                (fn []
                  (assert.are.equal "authorization: Bearer t0k"
                                    (. (atlas-run ["auth" "p"]) :out))))
            (it "rejects options given to completion"
                (fn []
                  (let [r (atlas-run ["completion" "bash" "--dry-run"])]
                    (assert.are.equal 1 r.code)
                    (assert.is_truthy (r.err:find "--dry-run doesn't apply to completion"
                                                  1 true)))))
            (it "explains missing profile arguments"
                (fn []
                  (let [r (atlas-run ["profile"])]
                    (assert.are.equal 1 r.code)
                    (assert.is_truthy (r.err:find "Usage: atlas profile" 1 true))
                    (assert.is_nil (r.err:find "nil" 1 true)))
                  (let [r (atlas-run ["profile" "show"])]
                    (assert.are.equal 1 r.code)
                    (assert.is_truthy (r.err:find "Usage: atlas profile show <name>"
                                                  1 true)))))
            (it "explains field paths without a name and inputs that are not objects"
                (fn []
                  (each [_ [args msg] (ipairs [[["op" "p" "add-pet" "--b..=1"]
                                                "has no field name"]
                                               [["az"
                                                 "flows"
                                                 "fetchPet"
                                                 "-i"
                                                 ".=1"]
                                                "has no field name"]
                                               [["az"
                                                 "flows"
                                                 "fetchPet"
                                                 "--inputs"
                                                 "5"]
                                                "--inputs must be an object"]
                                               [["az"
                                                 "flows"
                                                 "fetchPet"
                                                 "-d"
                                                 "\"s\""]
                                                "--body must be an object"]])]
                    (let [r (atlas-run args)]
                      (assert.are.equal 1 r.code)
                      (assert.is_truthy (r.err:find msg 1 true) r.err)))))
            (it "keeps the cached token when signing in again fails"
                (fn []
                  (let [auth (require :atlas.auth)
                        socket (require :socket)
                        srv (assert (socket.bind "127.0.0.1" 0))
                        (_ port) (srv:getsockname)]
                    (srv:close)
                    (auth.save-token "oc-keep"
                                     {:access_token "old" :refresh_token "r"})
                    (let [r (with-config {:profiles {:oc-keep {:auth {:name "oauth-client-credentials"
                                                                      :params {:token_url (.. "http://127.0.0.1:"
                                                                                              port
                                                                                              "/token")
                                                                               :client_id "c"
                                                                               :client_secret "s"}}}}}
                              #(atlas-run ["auth" "oc-keep"]))
                          kept (auth.load-token "oc-keep")]
                      (auth.clear-token "oc-keep")
                      (assert.are.equal 1 r.code)
                      (assert.are.equal "old" (?. kept :access_token))))))
            (it "takes --timeout for the token endpoint"
                (fn []
                  (let [r (atlas-run ["auth" "p" "--timeout" "5"])]
                    (assert.are.equal 0 r.code)
                    (assert.are.equal "authorization: Bearer t0k" r.out))))
            (it "shows a query API key read from the environment"
                (fn []
                  (let [r (with-config {:profiles {:qkenv {:auth {:name "api-key"
                                                                  :params {:in "query"
                                                                           :name "key"
                                                                           :value "env:ATLAS_TEST_UNSET_KEY"}}}}}
                            #(atlas-run ["auth" "qkenv"]))]
                    (assert.are.equal 1 r.code)
                    (assert.is_truthy (r.err:find "ATLAS_TEST_UNSET_KEY" 1 true)))
                  (let [r (with-config {:profiles {:qkenv {:auth {:name "api-key"
                                                                  :params {:in "query"
                                                                           :name "key"
                                                                           :value "env:HOME"}}}}}
                            #(atlas-run ["auth" "qkenv"]))]
                    (assert.are.equal (.. "query: key=" (os.getenv :HOME))
                                      r.out))))
            (it "rejects unknown TLS options and non-positive timeouts"
                (fn []
                  (each [_ [args msg] (ipairs [[["op"
                                                 "p"
                                                 "--list"
                                                 "--ssl.cert=c.pem"]
                                                "unknown TLS option: cert (expected cafile, capath, certificate, key or verify)"]
                                               [["op"
                                                 "p"
                                                 "--list"
                                                 "--timeout=-5"]
                                                "--timeout must be greater than 0"]
                                               [["op"
                                                 "p"
                                                 "--list"
                                                 "--timeout=0"]
                                                "--timeout must be greater than 0"]])]
                    (let [r (atlas-run args)]
                      (assert.are.equal 1 r.code)
                      (assert.is_truthy (r.err:find msg 1 true) r.err)))))
            (it "rejects a config with the wrong shape"
                (fn []
                  (each [_ [cfg msg] (ipairs [[{:profiles "x"}
                                               "config: profiles must be an object"]
                                              [{:profiles [1]}
                                               "config: profiles must be an object"]
                                              [3
                                               "config must be a JSON object"]
                                              [{:profiles {:a {:schema 5}}}
                                               "profile a: schema must be a string"]])]
                    ;; profile list marks a broken profile and goes on
                    (let [r (with-config cfg
                              #(atlas-run ["op" "a" "--list"]))
                          listed (with-config cfg
                                   #(atlas-run ["profile" "list"]))]
                      (assert.are.equal 1 r.code)
                      (assert.is_truthy (r.err:find msg 1 true) r.err)
                      (assert.is_truthy (: (.. listed.out listed.err) :find msg
                                           1 true))))))
            (it "lists, shows and logs out of a profile whose auth is incomplete"
                (fn []
                  (with-config {:profiles {:nopw {:schema "test/fixtures/cli-api.json"
                                                  :auth {:name "basic"
                                                         :params {:username "me"}}}}}
                    #(each [_ args (ipairs [["op" "nopw" "--list"]
                                            ["op" "nopw" "list-pets" "--help"]
                                            ["profile" "show" "nopw"]
                                            ["auth" "nopw" "--logout"]])]
                       (assert.are.equal 0 (. (atlas-run args) :code)
                                         (table.concat args " "))))))
            (it "adds a cookie API key to the cookies already sent"
                (fn []
                  (let [cfg {:profiles {:ck {:schema "test/fixtures/cli-api.json"
                                             :headers {:Cookie "theme=dark"}
                                             :auth {:name "api-key"
                                                    :params {:in "cookie"
                                                             :name "sid"
                                                             :value "S"}}}}}
                        routes {"GET https://api.test/pets" (respond 200 [])}
                        r (with-config cfg
                            #(atlas-run ["op" "ck" "list-pets"] routes))
                        mine (with-config cfg
                               #(atlas-run ["op"
                                            "ck"
                                            "list-pets"
                                            "--h.cookie=sid=MINE"]
                                           routes))
                        cookie (fn [run]
                                 (let [util (require :atlas.util)]
                                   (util.header (. run.requests 1 :headers)
                                                "cookie")))]
                    (assert.are.equal 0 r.code)
                    (assert.are.equal "theme=dark; sid=S" (cookie r))
                    (assert.are.equal "sid=MINE" (cookie mine)))))
            (it "names the auth parameters a profile is missing"
                (fn []
                  (each [_ [auth msg] (ipairs [[{:name "oauth-client-credentials"
                                                 :params {:client_id "c"}}
                                                "oauth-client-credentials auth requires params.token_url"]
                                               [{:name "oauth-client-credentials"}
                                                "oauth-client-credentials auth requires params.token_url"]
                                               [{:name "external-tool"}
                                                "external-tool auth requires params.commandline"]])]
                    (let [r (with-config {:profiles {:bad {:schema "test/fixtures/cli-api.json"
                                                           : auth}}}
                              #(atlas-run ["auth" "bad"]))]
                      (assert.are.equal 1 r.code)
                      (assert.is_truthy (r.err:find msg 1 true) r.err)))))
            (it "rejects Arazzo contexts and extends of the wrong shape"
                (fn []
                  (each [_ [cfg args msg] (ipairs [[{:arazzo {:pets "/x/wf.yaml"}}
                                                    ["az" "pets"]
                                                    "config: arazzo pets must be an object with a file"]
                                                   [{:arazzo {:m {:file "wf.yaml"
                                                                  :inputs "str"}}}
                                                    ["az" "m" "go"]
                                                    "config: arazzo m: inputs must be an object"]
                                                   [{:profiles {:x {:schema "s.json"
                                                                    :extends "y"}
                                                                :y "oops"}}
                                                    ["op" "x" "--list"]
                                                    "profile y must be an object"]])]
                    (let [r (with-config cfg #(atlas-run args))]
                      (assert.are.equal 1 r.code)
                      (assert.is_truthy (r.err:find msg 1 true) r.err)))
                  (let [r (with-config {:profiles {:x {:schema "s.json"
                                                       :extends "y"}
                                                   :y "oops"}}
                            #(atlas-run ["profile" "list"]))]
                    (assert.is_nil (r.out:find ".lua:" 1 true) r.out))))
            (it "rejects profiles whose settings have the wrong shape"
                (fn []
                  (each [_ [profile msg] (ipairs [[{:schema "test/fixtures/cli-api.json"
                                                    :auth "bearer"}
                                                   "profile bad: auth must be an object"]
                                                  [{:schema "test/fixtures/cli-api.json"
                                                    :headers "x"}
                                                   "profile bad: headers must be an object"]
                                                  [{:schema "test/fixtures/cli-api.json"
                                                    :auth {:params {}}}
                                                   "profile bad: auth needs a name"]])]
                    (let [r (with-config {:profiles {:bad profile}}
                              #(atlas-run ["op" "bad" "list-pets"]))]
                      (assert.are.equal 1 r.code)
                      (assert.is_truthy (r.err:find msg 1 true) r.err)))))
            (it "tells what atlas auth adds besides headers"
                (fn []
                  (with-config {:profiles {:qkey {:auth {:name "api-key"
                                                         :params {:in "query"
                                                                  :name "appid"
                                                                  :value "K"}}}
                                           :sign {:auth {:name "external-tool"
                                                         :params {:commandline "sign-it"}}}}}
                    #(do
                       (assert.are.equal "query: appid=K"
                                         (. (atlas-run ["auth" "qkey"]) :out))
                       (assert.are.equal "signs each request with: sign-it"
                                         (. (atlas-run ["auth" "sign"]) :out))))))
            (it "rejects unknown commands with exit 1"
                (fn []
                  (assert.are.equal 1 (. (atlas-run ["frobnicate"]) :code))))
            (it "lists the schema a profile inherits"
                (fn []
                  (let [r (with-config {:profiles {:base {:schema "s.json"}
                                                   :child {:extends "base"}}}
                            #(atlas-run ["profile" "list"]))]
                    (assert.are.equal "base\ts.json\nchild\ts.json" r.out))))
            (it "lists every profile, flagging one whose extends is broken"
                (fn []
                  (let [r (with-config {:profiles {:a {:schema "s.json"}
                                                   :b {:extends "nope"}
                                                   :c {:schema "t.json"}}}
                            #(atlas-run ["profile" "list"]))]
                    (assert.are.equal 0 r.code)
                    (assert.are.equal "a\ts.json\nb\t(broken: Profile not found: nope)\nc\tt.json"
                                      r.out))))
            (it "rejects options that don't apply to the command"
                (fn []
                  (let [r (atlas-run ["op"
                                      "p"
                                      "get-pet"
                                      "3"
                                      "--profile"
                                      "yaml"])]
                    (assert.are.equal 1 r.code)
                    (assert.are.equal "--profile doesn't apply to op (it is for az)\n"
                                      r.err)
                    (assert.are.equal 0 (length r.requests)))
                  (let [r (atlas-run ["az" "flows" "fetchPet" "--select" ".a"])]
                    (assert.are.equal 1 r.code)
                    (assert.are.equal "--select doesn't apply to az (it is for op)\n"
                                      r.err))
                  (let [r (atlas-run ["op" "p" "get-pet" "3" "--logout"])]
                    (assert.are.equal 1 r.code)
                    (assert.are.equal "--logout doesn't apply to op (it is for auth)\n"
                                      r.err))))
            (it "scopes options to profile and auth too"
                (fn []
                  (let [r (atlas-run ["profile" "list" "--timeout" "3"])]
                    (assert.are.equal 1 r.code)
                    (assert.are.equal "--timeout doesn't apply to profile (it is for op and az)\n"
                                      r.err))
                  (let [r (atlas-run ["profile" "list" "--dry-run"])]
                    (assert.are.equal 1 r.code)
                    (assert.is_truthy (r.err:find "--dry-run only applies to profile import-restish"
                                                  1 true)))
                  (let [r (atlas-run ["auth" "p" "--base-url" "http://x"])]
                    (assert.are.equal 1 r.code))
                  (assert.are.equal "authorization: Bearer t0k"
                                    (. (atlas-run ["auth"
                                                   "p"
                                                   "--ssl.verify=none"])
                                       :out))))
            (it "prints usage for --help on profile and auth, doing nothing else"
                (fn []
                  (each [_ args (ipairs [["auth" "p" "--help"]
                                         ["profile"
                                          "import-restish"
                                          "x.json"
                                          "--help"]])]
                    (let [r (atlas-run args)]
                      (assert.are.equal 0 r.code)
                      (assert.is_truthy (r.out:find "Usage: atlas" 1 true))
                      (assert.is_nil (r.out:find "Bearer" 1 true))))))
            (it "checks server variables when listing servers"
                (fn []
                  (let [r (atlas-run ["op"
                                      "p"
                                      "--servers"
                                      "--server.region=xx"])]
                    (assert.are.equal 1 r.code)
                    (assert.is_truthy (r.err:find "unknown server variable 'region'"
                                                  1 true)))))
            (it "explains bad option values"
                (fn []
                  (let [r (atlas-run ["op" "p" "get-pet" "3" "--output=yml"])]
                    (assert.are.equal 1 r.code)
                    (assert.is_truthy (r.err:find "--output must be one of json, yaml, raw, status, headers"
                                                  1 true)))
                  (let [r (atlas-run ["op"
                                      "p"
                                      "get-pet"
                                      "3"
                                      "--server-index=0"])]
                    (assert.are.equal 1 r.code)
                    (assert.is_truthy (r.err:find "server index 0 out of range"
                                                  1 true)))
                  (let [r (atlas-run ["op" "p" "add-pet" "--b.=1"])]
                    (assert.are.equal 1 r.code)
                    (assert.is_truthy (r.err:find "--b. needs a field name" 1
                                                  true)))))
            (it "shows a profile, or fails when it does not exist"
                (fn []
                  (let [r (atlas-run ["profile" "show" "yaml"])]
                    (assert.are.equal 0 r.code)
                    (assert.is_truthy (r.out:find "test/fixtures/cli-api.json"
                                                  1 true)))
                  (let [r (atlas-run ["profile" "show" "nope"])]
                    (assert.are.equal 1 r.code)
                    (assert.are.equal "Profile not found: nope\n" r.err))))
            (it "rejects unknown profile subcommands"
                (fn []
                  (let [r (atlas-run ["profile" "frob"])]
                    (assert.are.equal 1 r.code)
                    (assert.is_truthy (r.err:find "Unknown profile subcommand: frob"
                                                  1 true)))))
            (it "explains what atlas auth needs"
                (fn []
                  (assert.are.equal "Usage: atlas auth <profile> [--logout]\n"
                                    (. (atlas-run ["auth"]) :err))
                  (assert.are.equal "Profile not found: nope\n"
                                    (. (atlas-run ["auth" "nope"]) :err))
                  (assert.are.equal "No auth configured for profile: yaml\n"
                                    (. (atlas-run ["auth" "yaml"]) :err))
                  (assert.is_truthy (: (. (atlas-run ["auth" "broken-auth"])
                                          :err)
                                       :find
                                       "external auth command failed (exit 1)" 1
                                       true))))
            (it "logs out of a profile"
                (fn []
                  (let [r (atlas-run ["auth" "p" "--logout"])]
                    (assert.are.equal 0 r.code)
                    (assert.are.equal "Logged out: p" r.out))))
            (it "lists configured profiles and contexts when op or az has no target"
                (fn []
                  (let [r (atlas-run ["op"])]
                    (assert.are.equal 1 r.code)
                    (assert.is_truthy (r.err:find "Configured profiles:\n  broken-auth\ttest/fixtures/cli-api.json\n"
                                                  1 true)))
                  (let [r (atlas-run ["az"])]
                    (assert.are.equal 1 r.code)
                    (assert.is_truthy (r.err:find "Configured Arazzo contexts:\n  flows\ttest/fixtures/cli-flow.arazzo.json\n"
                                                  1 true)))))
            (it "answers the shell scripts' completion requests"
                (fn []
                  (assert.are.equal "import-restish"
                                    (. (atlas-run ["__complete"
                                                   "atlas profile im"])
                                       :out))
                  (assert.are.equal "--verbose\tShow status, headers and requests"
                                    (. (atlas-run ["__complete"
                                                   "--describe"
                                                   "atlas op x --verb"])
                                       :out))
                  (assert.are.equal ""
                                    (. (atlas-run ["__complete" "atlas"]) :out))))
            (it "prints completion scripts for each shell"
                (fn []
                  (each [_ shell (ipairs ["fish" "bash" "zsh"])]
                    (let [r (atlas-run ["completion" shell])]
                      (assert.are.equal 0 r.code)
                      (assert.is_truthy (r.out:find "__complete" 1 true))))
                  (assert.are.equal 1
                                    (. (atlas-run ["completion" "tcsh"]) :code))))))

(describe "credentials and schema sources"
          (fn []
            (let [schema-text (let [f (io.open "test/fixtures/cli-api.json")
                                    s (f:read :*a)]
                                (f:close)
                                s)
                  remote-config {:profiles {:remote {:schema "https://api.test/openapi.json"
                                                     :headers {:authorization "Basic profile"}
                                                     :auth {:name "bearer"
                                                            :params {:token "t"}}}
                                            :tok {:auth {:name "bearer"
                                                         :params {:token "t"}}}}
                                 :arazzo {:remote-flow {:file "test/fixtures/cli-remote.arazzo.json"
                                                        :profile "tok"}}}
                  run-with (fn [args routes]
                             (let [(transport requests) (routes-transport routes)
                                   real-print _G.print
                                   real-stderr io.stderr
                                   err []]
                               (set _G.print (fn []))
                               (set io.stderr
                                    {:write (fn [_ s] (table.insert err s))})
                               (let [code (cli.run args
                                                   {: transport
                                                    :config remote-config
                                                    :schema-cache false})]
                                 (set _G.print real-print)
                                 (set io.stderr real-stderr)
                                 (values code requests (table.concat err)))))]
              (it "keeps an explicit Authorization header when retrying a schema fetch after 401"
                  (fn []
                    (let [(code requests) (run-with ["op" "remote" "--list"]
                                                    {"GET https://api.test/openapi.json" (fn [req]
                                                                                           (if (= (length (or req.headers.authorization
                                                                                                              ""))
                                                                                                  0)
                                                                                               (respond 401
                                                                                                        {})
                                                                                               (respond 401
                                                                                                        {})))})]
                      (assert.are.equal 1 code)
                      (assert.are.equal 2 (length requests))
                      (assert.are.equal "Basic profile"
                                        (. requests 2 :headers :authorization)))))
              (it "does not send credentials to az sources until they ask"
                  (fn []
                    (let [f (io.open "test/fixtures/cli-remote.arazzo.json" :w)]
                      (f:write "{\"arazzo\":\"1.0.0\",\"info\":{\"title\":\"r\",\"version\":\"1\"},\"sourceDescriptions\":[{\"name\":\"api\",\"type\":\"openapi\",\"url\":\"https://specs.test/openapi.json\"}],\"workflows\":[{\"workflowId\":\"w\",\"steps\":[{\"stepId\":\"s\",\"operationId\":\"listPets\"}]}]}")
                      (f:close))
                    (let [(code requests err) (run-with ["az"
                                                         "remote-flow"
                                                         "w"]
                                                        {"GET https://specs.test/openapi.json" {:status 200
                                                                                                :headers {}
                                                                                                :raw schema-text}
                                                         "GET https://api.test/pets" (respond 200
                                                                                              [])})]
                      (os.remove "test/fixtures/cli-remote.arazzo.json")
                      (assert.are.equal 0 code err)
                      (assert.is_nil (. requests 1 :headers :authorization))
                      (assert.are.equal "Bearer t"
                                        (. requests 2 :headers :authorization)))))
              (it "never sends credentials to a host a source's $ref names"
                  (fn []
                    (let [f (io.open "test/fixtures/cli-remote.arazzo.json" :w)]
                      (f:write "{\"arazzo\":\"1.0.0\",\"info\":{\"title\":\"r\",\"version\":\"1\"},\"sourceDescriptions\":[{\"name\":\"api\",\"type\":\"openapi\",\"url\":\"https://specs.test/openapi.json\"}],\"workflows\":[{\"workflowId\":\"w\",\"steps\":[{\"stepId\":\"s\",\"operationId\":\"listPets\"}]}]}")
                      (f:close))
                    (let [spec "{\"openapi\":\"3.0.0\",\"info\":{\"title\":\"t\",\"version\":\"1\"},\"servers\":[{\"url\":\"https://api.test\"}],\"paths\":{\"/pets\":{\"get\":{\"operationId\":\"listPets\",\"responses\":{\"200\":{\"$ref\":\"https://other.test/common.json#/ok\"}}}}}}"
                          (_ requests) (run-with ["az" "remote-flow" "w"]
                                                 {"GET https://specs.test/openapi.json" {:status 200
                                                                                         :headers {}
                                                                                         :raw spec}
                                                  "GET https://other.test/common.json" {:status 401
                                                                                        :headers {}
                                                                                        :raw ""}})]
                      (os.remove "test/fixtures/cli-remote.arazzo.json")
                      (each [_ req (ipairs requests)]
                        (when (req.url:find "other.test" 1 true)
                          (assert.is_nil (?. req :headers :authorization))))))))))

(describe "auth and argument edge cases"
          (fn []
            (fn auth-runs []
              (let [f (io.open "build/test-home/auth-runs")]
                (if f (let [n (length (icollect [_ (: (f:read :*a) :gmatch
                                                      "run")]
                                        1))]
                        (f:close)
                        n) 0)))

            (before_each (fn [] (os.remove "build/test-home/auth-runs")))
            (it "runs the auth flow once for atlas auth"
                (fn []
                  (assert.are.equal "authorization: Bearer tok"
                                    (. (atlas-run ["auth" "counted"]) :out))
                  (assert.are.equal 1 (auth-runs))))
            (it "honors --logout for every auth type"
                (fn []
                  (let [r (atlas-run ["auth" "p" "--logout"])]
                    (assert.are.equal "Logged out: p" r.out))))
            (it "does not authenticate for --dry-run"
                (fn []
                  (let [r (atlas-run ["op" "counted" "get-pet" "1" "--dry-run"])]
                    (assert.are.equal 0 r.code)
                    (assert.is_truthy (r.out:find "authorization: <redacted>" 1
                                                  true))
                    (assert.are.equal 0 (auth-runs)))))
            (it "does not authenticate when an explicit header covers it"
                (fn []
                  (let [r (atlas-run ["op"
                                      "counted"
                                      "get-pet"
                                      "1"
                                      "--h.Authorization=Basic x"]
                                     {"GET https://api.test/pets/1" (respond 200
                                                                             {})})]
                    (assert.are.equal 0 r.code)
                    (assert.are.equal "Basic x"
                                      (. r.requests 1 :headers :authorization))
                    (assert.are.equal 0 (auth-runs)))))
            (it "rejects extra positional arguments"
                (fn []
                  (let [r (atlas-run ["op" "p" "get-pet" "1" "2"])]
                    (assert.are.equal 1 r.code)
                    (assert.is_truthy (r.err:find "get-pet takes 1 path parameter (id), got 2"
                                                  1 true))
                    (assert.are.equal 0 (length r.requests)))))
            (it "rejects workflow inputs on op"
                (fn []
                  (let [r (atlas-run ["op" "p" "list-pets" "-i" "a=1"])]
                    (assert.are.equal 1 r.code)
                    (assert.is_truthy (r.err:find "doesn't apply to op (it is for az)"
                                                  1 true)))))))

(describe "atlas profile import-restish"
          (fn []
            (let [json (require :lunajson)
                  target "build/test-home/import-config.json"
                  run-import (fn [args config]
                               (let [out []
                                     err []
                                     real-print _G.print
                                     real-stderr io.stderr]
                                 (set _G.print
                                      (fn [...]
                                        (table.insert out
                                                      (table.concat [...] "\t"))))
                                 (set io.stderr
                                      {:write (fn [_ s] (table.insert err s))})
                                 (let [code (cli.run args
                                                     {:config config
                                                      :config-path target})]
                                   (set _G.print real-print)
                                   (set io.stderr real-stderr)
                                   {: code
                                    :out (table.concat out "\n")
                                    :err (table.concat err)})))
                  read-target #(let [f (io.open target)]
                                 (when f
                                   (let [v (json.decode (f:read :*a))]
                                     (f:close)
                                     v)))]
              (before_each (fn []
                             (os.remove target)
                             (os.remove (.. target ".bak"))))
              (it "previews with --dry-run without writing"
                  (fn []
                    (let [r (run-import ["profile"
                                         "import-restish"
                                         "test/fixtures/restish-v1.json"
                                         "--dry-run"]
                                        {})]
                      (assert.are.equal 0 r.code)
                      (assert.is_truthy (r.out:find "\"petstore.staging\"" 1
                                                    true))
                      (assert.is_truthy (r.err:find "discovered: no spec_files"
                                                    1 true))
                      (assert.is_nil (read-target)))))
              (it "adds profiles to the config, keeping existing ones"
                  (fn []
                    (let [f (io.open target :w)]
                      (f:write "{\"output\": \"yaml\", \"profiles\": {\"petstore\": {\"schema\": \"mine.json\"}}}")
                      (f:close))
                    (let [r (run-import ["profile"
                                         "import-restish"
                                         "test/fixtures/restish-v1.json"]
                                        {:output "yaml"
                                         :profiles {:petstore {:schema "mine.json"}}})
                          written (read-target)]
                      (assert.are.equal 0 r.code)
                      (assert.are.equal "mine.json"
                                        written.profiles.petstore.schema)
                      (assert.are.equal "yaml" written.output)
                      (assert.are.equal "basic"
                                        (. written.profiles "petstore.staging"
                                           :auth :name))
                      (assert.is_not_nil written.profiles.devices)
                      (assert.is_truthy (r.out:find "kept existing profile: petstore"
                                                    1 true))
                      (assert.is_truthy (r.out:find "imported 3 profiles" 1
                                                    true))
                      (assert.is_not_nil (io.open (.. target ".bak")))
                      ;; profiles hold credentials
                      (each [_ path (ipairs [target (.. target ".bak")])]
                        (let [p (io.popen (.. "ls -l " path))
                              mode (: (p:read :*a) :match "^(%S+)")]
                          (p:close)
                          (assert.are.equal "-rw-------" mode))))))
              (it "keeps the config's null values when rewriting it"
                  (fn []
                    (let [f (io.open target :w)]
                      (f:write "{\"arazzo\": {\"x\": {\"file\": \"f\", \"inputs\": {\"nul\": null}}}}")
                      (f:close))
                    (let [r (run-import ["profile"
                                         "import-restish"
                                         "test/fixtures/restish-v1.json"]
                                        {:arazzo {:x {:file "f"}}})
                          f (io.open target)
                          text (f:read :*a)]
                      (f:close)
                      (assert.are.equal 0 r.code)
                      (assert.is_truthy (text:find "\"nul\": null" 1 true)))))
              (it "fails clearly for a missing file"
                  (fn []
                    (let [r (run-import ["profile"
                                         "import-restish"
                                         "nope/restish.json"]
                                        {})]
                      (assert.are.equal 1 r.code)
                      (assert.is_truthy (r.err:find "nope/restish.json" 1 true))))))))
