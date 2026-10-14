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
    (let [(ok code) (pcall cli.run args {: transport : config})]
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
            (it "lists profiles sorted"
                (fn []
                  (let [r (atlas-run ["profile" "list"])]
                    (assert.are.equal "broken-auth\ttest/fixtures/cli-api.json\ncounted\ttest/fixtures/cli-api.json\np\ttest/fixtures/cli-api.json\nyaml\ttest/fixtures/cli-api.json"
                                      r.out))))
            (it "prints static credentials for atlas auth"
                (fn []
                  (assert.are.equal "authorization: Bearer t0k"
                                    (. (atlas-run ["auth" "p"]) :out))))
            (it "rejects unknown commands with exit 1"
                (fn []
                  (assert.are.equal 1 (. (atlas-run ["frobnicate"]) :code))))))

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
                                        (. requests 2 :headers :authorization))))))))

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
                    (assert.is_truthy (r.err:find "workflow inputs (-i, --i.) only apply to az"
                                                  1 true)))))))
