;; ABOUTME: Specs for Arazzo document loading, client resolution and workflow execution.
;; ABOUTME: Run with `make test` (busted, Fennel loader).
(local arazzo (require :atlas.arazzo))
(local expr (require :atlas.arazzo.expr))

;; ---- helpers ----

(fn make-client [ops]
  "Build a fake atlas client: {operationId → (fn [req] resp)}."
  (collect [id f (pairs ops)]
    (.. "op-" id)
    {:operation-id id
     :method "get"
     :url-for (fn [req] (.. "https://api.test/" id (if req.query "?q" "")))
     :invoke f}))

(fn ok-resp [body ?status]
  {:status (or ?status 200)
   :headers {:content-type "application/json"}
   :body body})

(fn counter []
  (let [n [0]]
    {:inc (fn []
            (tset n 1 (+ (. n 1) 1)))
     :val (fn [] (. n 1))}))

;; ---- load-doc ----

(describe "load-doc"
          (fn []
            (it "loads a JSON file from disk"
                (fn []
                  (let [doc (arazzo.load-doc "test/fixtures/simple.arazzo.json")]
                    (assert.are.equal "1.0.0" doc.arazzo)
                    (assert.is_not_nil doc.workflows))))))

;; ---- build-clients ----

(describe "build-clients"
          (fn []
            (it "returns empty table when no sourceDescriptions"
                (fn []
                  (let [doc {:arazzo "1.0.0" :info {} :workflows []}
                        clients (arazzo.build-clients doc {})]
                    (assert.are.same {} clients))))
            (it "resolves relative source URLs against the document location"
                (fn []
                  (let [doc {:sourceDescriptions [{:name "pets"
                                                   :type "openapi"
                                                   :url "./petstore.yaml"}]
                             :workflows []}
                        clients (arazzo.build-clients doc {}
                                                      "test/fixtures/flow.arazzo.json")]
                    (assert.is_not_nil (. clients :pets)))))
            (it "rejects a base-url override when several openapi sources exist"
                (fn []
                  (let [doc {:sourceDescriptions [{:name "a"
                                                   :type "openapi"
                                                   :url "./petstore.yaml"}
                                                  {:name "b"
                                                   :type "openapi"
                                                   :url "./petstore.yaml"}]
                             :workflows []}]
                    (assert.has.error #(arazzo.build-clients doc
                                                             {:base-url "https://x"}
                                                             "test/fixtures/flow.arazzo.json")
                                      "base-url override is ambiguous: the document has 2 openapi sources"))))
            (it "gives each source only the server variables it declares"
                (fn []
                  (let [dir (os.tmpname)
                        write (fn [name content]
                                (let [f (io.open (.. dir "-" name) :w)]
                                  (f:write content)
                                  (f:close)))]
                    (write "a.json"
                           "{\"openapi\":\"3.0.0\",\"info\":{},\"servers\":[{\"url\":\"https://{zone}.a.test\",\"variables\":{\"zone\":{\"default\":\"z1\"}}}],\"paths\":{\"/x\":{\"get\":{\"operationId\":\"ax\",\"responses\":{}}}}}")
                    (write "b.json"
                           "{\"openapi\":\"3.0.0\",\"info\":{},\"servers\":[{\"url\":\"https://b.test\"}],\"paths\":{\"/y\":{\"get\":{\"operationId\":\"by\",\"responses\":{}}}}}")
                    (let [doc {:sourceDescriptions [{:name "a"
                                                     :type "openapi"
                                                     :url (.. dir "-a.json")}
                                                    {:name "b"
                                                     :type "openapi"
                                                     :url (.. dir "-b.json")}]
                               :workflows []}
                          clients (arazzo.build-clients doc
                                                        {:server-vars {:zone "z9"}})]
                      (os.remove (.. dir "-a.json"))
                      (os.remove (.. dir "-b.json"))
                      (assert.are.equal "https://z9.a.test/x"
                                        (clients.a.ax.url-for))
                      (assert.are.equal "https://b.test/y"
                                        (clients.b.by.url-for))))))
            (it "rejects server variables no source declares"
                (fn []
                  (let [doc {:sourceDescriptions [{:name "a"
                                                   :type "openapi"
                                                   :url "./petstore.yaml"}]
                             :workflows []}]
                    (assert.has.error #(arazzo.build-clients doc
                                                             {:server-vars {:nope "x"}}
                                                             "test/fixtures/flow.arazzo.json")
                                      "no openapi source declares server variable 'nope'"))))
            (it "skips non-openapi sources"
                (fn []
                  (let [doc {:sourceDescriptions [{:name "ext"
                                                   :type "arazzo"
                                                   :url "other.yaml"}]
                             :workflows []}
                        clients (arazzo.build-clients doc {})]
                    (assert.are.same {} clients))))))

;; ---- run-workflow ----

(describe "run-workflow"
          (fn []
            (it "runs a single-step workflow and returns outputs"
                (fn []
                  (let [resp (ok-resp {:token "tok99"})
                        c (counter)
                        op (fn [] (c.inc) resp)
                        clients {:myapi (make-client {:getToken op})}
                        doc {:arazzo "1.0.0"
                             :info {}
                             :workflows [{:workflowId "auth"
                                          :steps [{:stepId "step1"
                                                   :operationId "getToken"
                                                   :successCriteria [{:condition "$statusCode == 200"}]
                                                   :outputs {:tok "$response.body#/token"}}]
                                          :outputs {:token "$steps.step1.outputs.tok"}}]}
                        result (arazzo.run-workflow doc "auth" {} clients {})]
                    (assert.are.equal "tok99" result.outputs.token)
                    (assert.are.equal 1 (c.val)))))
            (it "executes onSuccess goto — skips to non-sequential step"
                (fn []
                  ;; s1 →(goto s3)→ s3; s2 is skipped entirely
                  (let [call-log []
                        make-op (fn [id]
                                  (fn []
                                    (table.insert call-log id)
                                    (ok-resp {})))
                        clients {:api (make-client {:op1 (make-op :s1)
                                                    :op2 (make-op :s2)
                                                    :op3 (make-op :s3)})}
                        doc {:arazzo "1.0.0"
                             :info {}
                             :workflows [{:workflowId "wf"
                                          :steps [{:stepId "s1"
                                                   :operationId "op1"
                                                   :successCriteria [{:condition "$statusCode == 200"}]
                                                   :onSuccess [{:type :goto
                                                                :stepId "s3"}]}
                                                  {:stepId "s2"
                                                   :operationId "op2"
                                                   :successCriteria [{:condition "$statusCode == 200"}]}
                                                  {:stepId "s3"
                                                   :operationId "op3"
                                                   :successCriteria [{:condition "$statusCode == 200"}]}]
                                          :outputs {}}]}]
                    (arazzo.run-workflow doc "wf" {} clients {})
                    (assert.are.same [:s1 :s3] call-log))))
            (it "executes onFailure end action"
                (fn []
                  (let [clients {:api (make-client {:failop (fn []
                                                              (ok-resp {:e "err"}
                                                                       500))})}
                        doc {:arazzo "1.0.0"
                             :info {}
                             :workflows [{:workflowId "wf"
                                          :steps [{:stepId "s1"
                                                   :operationId "failop"
                                                   :successCriteria [{:condition "$statusCode == 200"}]
                                                   :onFailure [{:type :end}]}]
                                          :outputs {}}]}
                        result (arazzo.run-workflow doc "wf" {} clients {})]
                    (assert.are.same {} result.outputs))))
            (it "raises on step failure with no action"
                (fn []
                  (let [clients {:api (make-client {:failop (fn []
                                                              (ok-resp {} 500))})}
                        doc {:arazzo "1.0.0"
                             :info {}
                             :workflows [{:workflowId "wf"
                                          :steps [{:stepId "s1"
                                                   :operationId "failop"
                                                   :successCriteria [{:condition "$statusCode == 200"}]}]
                                          :outputs {}}]}]
                    (assert.has.error (fn []
                                        (arazzo.run-workflow doc "wf" {}
                                                             clients {}))
                                      "step 's1' failed success criteria (HTTP 500 {})"))))
            (it "passes inputs to steps via path parameters"
                (fn []
                  (let [received []
                        op (fn [req] (table.insert received req.path.id)
                             (ok-resp {}))
                        clients {:api (make-client {:getUser op})}
                        doc {:arazzo "1.0.0"
                             :info {}
                             :workflows [{:workflowId "wf"
                                          :steps [{:stepId "s1"
                                                   :operationId "getUser"
                                                   :parameters [{:in :path
                                                                 :name "id"
                                                                 :value "$inputs.userId"}]
                                                   :successCriteria [{:condition "$statusCode == 200"}]}]
                                          :outputs {}}]}]
                    (arazzo.run-workflow doc "wf" {:userId "42"} clients {})
                    (assert.are.equal "42" (. received 1)))))
            (it "merges workflow-level parameters into steps"
                (fn []
                  (let [received []
                        op (fn [req] (table.insert received req.path.env)
                             (ok-resp {}))
                        clients {:api (make-client {:op op})}
                        doc {:arazzo "1.0.0"
                             :info {}
                             :workflows [{:workflowId "wf"
                                          :parameters [{:in :path
                                                        :name "env"
                                                        :value "$inputs.env"}]
                                          :steps [{:stepId "s1"
                                                   :operationId "op"
                                                   :successCriteria [{:condition "$statusCode == 200"}]}]
                                          :outputs {}}]}]
                    (arazzo.run-workflow doc "wf" {:env "prod"} clients {})
                    (assert.are.equal "prod" (. received 1)))))
            (it "resolves requestBody.payload expression"
                (fn []
                  (let [received []
                        op (fn [req] (table.insert received req.body)
                             (ok-resp {}))
                        clients {:api (make-client {:createUser op})}
                        doc {:arazzo "1.0.0"
                             :info {}
                             :workflows [{:workflowId "wf"
                                          :steps [{:stepId "s1"
                                                   :operationId "createUser"
                                                   :requestBody {:payload "$inputs.user"}
                                                   :successCriteria [{:condition "$statusCode == 200"}]}]
                                          :outputs {}}]}]
                    (arazzo.run-workflow doc "wf" {:user {:name "alice"}}
                                         clients {})
                    (assert.are.same {:name "alice"} (. received 1)))))
            (it "propagates step outputs via $steps expression"
                (fn []
                  (let [login-resp (ok-resp {:access_token "tok-abc"})
                        use-resp (ok-resp {:ok true})
                        token-used []
                        clients {:api (make-client {:login (fn [] login-resp)
                                                    :use (fn [req]
                                                           (table.insert token-used
                                                                         req.path.t)
                                                           use-resp)})}
                        doc {:arazzo "1.0.0"
                             :info {}
                             :workflows [{:workflowId "wf"
                                          :steps [{:stepId "login"
                                                   :operationId "login"
                                                   :successCriteria [{:condition "$statusCode == 200"}]
                                                   :outputs {:token "$response.body#/access_token"}}
                                                  {:stepId "use"
                                                   :operationId "use"
                                                   :parameters [{:in :path
                                                                 :name "t"
                                                                 :value "$steps.login.outputs.token"}]
                                                   :successCriteria [{:condition "$statusCode == 200"}]}]
                                          :outputs {}}]}]
                    (arazzo.run-workflow doc "wf" {} clients {})
                    (assert.are.equal "tok-abc" (. token-used 1)))))
            (it "runs sub-workflow and exposes its outputs"
                (fn []
                  (let [clients {:api (make-client {:op (fn [] (ok-resp {:v 7}))})}
                        doc {:arazzo "1.0.0"
                             :info {}
                             :workflows [{:workflowId "inner"
                                          :steps [{:stepId "s1"
                                                   :operationId "op"
                                                   :successCriteria [{:condition "$statusCode == 200"}]
                                                   :outputs {:val "$response.body#/v"}}]
                                          :outputs {:result "$steps.s1.outputs.val"}}
                                         {:workflowId "outer"
                                          :steps [{:stepId "sub"
                                                   :workflowId "inner"}]
                                          :outputs {:x "$steps.sub.outputs.result"}}]}
                        result (arazzo.run-workflow doc "outer" {} clients {})]
                    (assert.are.equal 7 result.outputs.x))))
            (it "detects goto loops"
                (fn []
                  (let [clients {:api (make-client {:op (fn [] (ok-resp {}))})}
                        doc {:arazzo "1.0.0"
                             :info {}
                             :workflows [{:workflowId "wf"
                                          :steps [{:stepId "s1"
                                                   :operationId "op"
                                                   :successCriteria [{:condition "$statusCode == 200"}]
                                                   :onSuccess [{:type :goto
                                                                :stepId "s1"}]}]
                                          :outputs {}}]}]
                    (assert.has.error (fn []
                                        (arazzo.run-workflow doc "wf" {}
                                                             clients {}))
                                      "goto loop detected at: s1"))))
            (it "resolves operationPath via path index"
                (fn []
                  (let [resp (ok-resp {:id 1})
                        c (counter)
                        op (fn [] (c.inc) resp)
                        clients {:api {:list-users {:path "/users"
                                                    :method "get"
                                                    :url-for #"u"
                                                    :invoke op}}}
                        doc {:arazzo "1.0.0"
                             :info {}
                             :workflows [{:workflowId "wf"
                                          :steps [{:stepId "s1"
                                                   :operationPath "{$sourceDescriptions.api.url}#/paths/~1users/get"
                                                   :successCriteria [{:condition "$statusCode == 200"}]}]
                                          :outputs {}}]}]
                    (arazzo.run-workflow doc "wf" {} clients {})
                    (assert.are.equal 1 (c.val)))))
            (it "raises on operationPath with missing source"
                (fn []
                  (let [clients {}
                        doc {:arazzo "1.0.0"
                             :info {}
                             :workflows [{:workflowId "wf"
                                          :steps [{:stepId "s1"
                                                   :operationPath "{$sourceDescriptions.missing.url}#/paths/~1users/get"}]
                                          :outputs {}}]}]
                    (assert.has.error (fn []
                                        (arazzo.run-workflow doc "wf" {}
                                                             clients {}))
                                      "operationPath: unknown source 'missing'"))))
            (it "calls on-step callback with running and done events"
                (fn []
                  (let [events []
                        clients {:api (make-client {:op (fn [] (ok-resp {}))})}
                        doc {:arazzo "1.0.0"
                             :info {}
                             :workflows [{:workflowId "wf"
                                          :steps [{:stepId "s1"
                                                   :operationId "op"
                                                   :successCriteria [{:condition "$statusCode == 200"}]}]
                                          :outputs {}}]}
                        on-step (fn [ev] (table.insert events ev.status))]
                    (arazzo.run-workflow doc "wf" {} clients {:on-step on-step})
                    (assert.are.same [:running :done] events))))))

;; ---- run-workflow: $response.body (no pointer) ----

(describe "run-workflow $response.body"
          (fn []
            (it "captures full response body as step output"
                (fn []
                  (let [body {:id 42 :name "alice"}
                        clients {:api (make-client {:op (fn [] (ok-resp body))})}
                        doc {:arazzo "1.0.0"
                             :info {}
                             :workflows [{:workflowId "wf"
                                          :steps [{:stepId "s1"
                                                   :operationId "op"
                                                   :successCriteria [{:condition "$statusCode == 200"}]
                                                   :outputs {:data "$response.body"}}]
                                          :outputs {:result "$steps.s1.outputs.data"}}]}
                        result (arazzo.run-workflow doc "wf" {} clients {})]
                    (assert.are.same body result.outputs.result))))
            (it "passes full body through requestBody payload table"
                (fn []
                  (let [received []
                        op (fn [req] (table.insert received req.body)
                             (ok-resp {}))
                        clients {:api (make-client {:op op})}
                        doc {:arazzo "1.0.0"
                             :info {}
                             :workflows [{:workflowId "wf"
                                          :steps [{:stepId "s1"
                                                   :operationId "op"
                                                   :requestBody {:payload {:name "$inputs.name"
                                                                           :role "$inputs.role"}}
                                                   :successCriteria [{:condition "$statusCode == 200"}]}]
                                          :outputs {}}]}]
                    (arazzo.run-workflow doc "wf" {:name "bob" :role "admin"}
                                         clients {})
                    (assert.are.same {:name "bob" :role "admin"} (. received 1)))))
            (it "propagates full body between steps via $steps.id.response.body"
                (fn []
                  (let [first-body {:token "xyz"}
                        received []
                        clients {:api (make-client {:login (fn []
                                                             (ok-resp first-body))
                                                    :use (fn [req]
                                                           (table.insert received
                                                                         req.body)
                                                           (ok-resp {}))})}
                        doc {:arazzo "1.0.0"
                             :info {}
                             :workflows [{:workflowId "wf"
                                          :steps [{:stepId "login"
                                                   :operationId "login"
                                                   :successCriteria [{:condition "$statusCode == 200"}]}
                                                  {:stepId "use"
                                                   :operationId "use"
                                                   :requestBody {:payload "$steps.login.response.body"}
                                                   :successCriteria [{:condition "$statusCode == 200"}]}]
                                          :outputs {}}]}]
                    (arazzo.run-workflow doc "wf" {} clients {})
                    (assert.are.same first-body (. received 1)))))))

;; ---- run-workflow: multiple successCriteria (AND) ----

(describe "run-workflow multiple successCriteria"
          (fn []
            (it "passes when all criteria match"
                (fn []
                  (let [clients {:api (make-client {:op (fn []
                                                          (ok-resp {:state "done"}))})}
                        doc {:arazzo "1.0.0"
                             :info {}
                             :workflows [{:workflowId "wf"
                                          :steps [{:stepId "s1"
                                                   :operationId "op"
                                                   :successCriteria [{:condition "$statusCode == 200"}
                                                                     {:condition "$response.body#/state == \"done\""}]}]
                                          :outputs {}}]}
                        result (arazzo.run-workflow doc "wf" {} clients {})]
                    (assert.are.same {} result.outputs))))
            (it "fails when second criterion does not match"
                (fn []
                  (let [clients {:api (make-client {:op (fn []
                                                          (ok-resp {:state "pending"}))})}
                        doc {:arazzo "1.0.0"
                             :info {}
                             :workflows [{:workflowId "wf"
                                          :steps [{:stepId "s1"
                                                   :operationId "op"
                                                   :successCriteria [{:condition "$statusCode == 200"}
                                                                     {:condition "$response.body#/state == \"done\""}]
                                                   :onFailure [{:type :end}]}]
                                          :outputs {}}]}
                        result (arazzo.run-workflow doc "wf" {} clients {})]
                    (assert.are.same {} result.outputs))))))

;; ---- run-workflow: onSuccess criteria-gated action ----

(describe "run-workflow onSuccess criteria"
          (fn []
            (it "only fires action whose criteria match"
                (fn []
                  ;; two onSuccess actions; only the matching one should fire
                  (let [call-log []
                        make-op (fn [id]
                                  (fn [] (table.insert call-log id)
                                    (ok-resp {:v 1})))
                        clients {:api (make-client {:op1 (make-op :s1)
                                                    :op2 (make-op :s2)
                                                    :op3 (make-op :s3)})}
                        doc {:arazzo "1.0.0"
                             :info {}
                             :workflows [{:workflowId "wf"
                                          :steps [{:stepId "s1"
                                                   :operationId "op1"
                                                   :successCriteria [{:condition "$statusCode == 200"}]
                                                   :onSuccess [{:type :goto
                                                                :stepId "s2"
                                                                :criteria [{:condition "$response.body#/v == 99"}]}
                                                               {:type :goto
                                                                :stepId "s3"
                                                                :criteria [{:condition "$response.body#/v == 1"}]}]}
                                                  {:stepId "s2"
                                                   :operationId "op2"
                                                   :successCriteria [{:condition "$statusCode == 200"}]}
                                                  {:stepId "s3"
                                                   :operationId "op3"
                                                   :successCriteria [{:condition "$statusCode == 200"}]}]
                                          :outputs {}}]}]
                    (arazzo.run-workflow doc "wf" {} clients {})
                    (assert.are.same [:s1 :s3] call-log))))))

;; ---- run-workflow: onFailure goto (poll pattern) ----

(describe "run-workflow onFailure goto"
          (fn []
            (it "retries until success criterion met"
                (fn []
                  (let [calls (counter) ;; returns pending twice then done
                        op (fn []
                             (calls.inc)
                             (if (< (calls.val) 3)
                                 (ok-resp {:state "pending"})
                                 (ok-resp {:state "done"})))
                        clients {:api (make-client {:op op})}
                        doc {:arazzo "1.0.0"
                             :info {}
                             :workflows [{:workflowId "wf"
                                          :steps [{:stepId "poll"
                                                   :operationId "op"
                                                   :successCriteria [{:condition "$statusCode == 200"}
                                                                     {:condition "$response.body#/state == \"done\""}]
                                                   :onFailure [{:type :goto
                                                                :stepId "poll"}]
                                                   :outputs {:state "$response.body#/state"}}]
                                          :outputs {:state "$steps.poll.outputs.state"}}]}
                        result (arazzo.run-workflow doc "wf" {} clients {})]
                    (assert.are.equal 3 (calls.val))
                    (assert.are.equal "done" result.outputs.state))))))

;; ---- expr: json-pointer ----

(describe "json-pointer"
          (fn []
            (it "resolves nested path"
                (fn []
                  (assert.are.equal "bar"
                                    (expr.json-pointer {:a {:b "bar"}} "/a/b"))))
            (it "resolves array index (0-based)"
                (fn []
                  (assert.are.equal "second"
                                    (expr.json-pointer ["first" "second"] "/1"))))
            (it "decodes ~1 as slash"
                (fn []
                  (assert.are.equal 42 (expr.json-pointer {"a/b" 42} "/a~1b"))))
            (it "decodes ~0 as tilde"
                (fn []
                  (assert.are.equal "yes"
                                    (expr.json-pointer {"a~b" "yes"} "/a~0b"))))
            (it "returns nil for missing key"
                (fn []
                  (assert.is_nil (expr.json-pointer {:a 1} "/z"))))
            (it "returns nil for nil obj"
                (fn []
                  (assert.is_nil (expr.json-pointer nil "/a"))))))

;; ---- expr: resolve-expr ----

(describe "resolve-expr"
          (fn []
            (let [ctx {:inputs {:x "hello" :n 7}
                       :steps {:s1 {:outputs {:k "v"}
                                    :response {:status 201
                                               :headers {:x-id "abc"}
                                               :body {:msg "hi"}}
                                    :request {:body {:q "search"} :headers {}}}}
                       :workflows {}
                       :response {:status 200
                                  :headers {:content-type "application/json"}
                                  :body {:result "ok"}}
                       :request {:body {:payload "data"} :headers {}}}]
              (it "resolves $inputs.x"
                  (fn []
                    (assert.are.equal "hello"
                                      (expr.resolve-expr ctx "$inputs.x"))))
              (it "resolves $statusCode"
                  (fn []
                    (assert.are.equal 200 (expr.resolve-expr ctx "$statusCode"))))
              (it "resolves $response.body (no pointer) as full table"
                  (fn []
                    (assert.are.same {:result "ok"}
                                     (expr.resolve-expr ctx "$response.body"))))
              (it "resolves $response.body#/result"
                  (fn []
                    (assert.are.equal "ok"
                                      (expr.resolve-expr ctx
                                                         "$response.body#/result"))))
              (it "resolves $response.header.content-type"
                  (fn []
                    (assert.are.equal "application/json"
                                      (expr.resolve-expr ctx
                                                         "$response.header.content-type"))))
              (it "resolves $steps.s1.outputs.k"
                  (fn []
                    (assert.are.equal "v"
                                      (expr.resolve-expr ctx
                                                         "$steps.s1.outputs.k"))))
              (it "resolves $steps.s1.response.body (no pointer)"
                  (fn []
                    (assert.are.same {:msg "hi"}
                                     (expr.resolve-expr ctx
                                                        "$steps.s1.response.body"))))
              (it "resolves $steps.s1.response.body#/msg"
                  (fn []
                    (assert.are.equal "hi"
                                      (expr.resolve-expr ctx
                                                         "$steps.s1.response.body#/msg"))))
              (it "resolves response headers case-insensitively"
                  (fn []
                    (assert.are.equal "application/json"
                                      (expr.resolve-expr ctx
                                                         "$response.header.Content-Type"))
                    (assert.are.equal "abc"
                                      (expr.resolve-expr ctx
                                                         "$steps.s1.response.header.X-Id"))))
              (it "resolves $steps.s1.response.header.x-id"
                  (fn []
                    (assert.are.equal "abc"
                                      (expr.resolve-expr ctx
                                                         "$steps.s1.response.header.x-id"))))
              (it "resolves $request.body (no pointer) as full table"
                  (fn []
                    (assert.are.same {:payload "data"}
                                     (expr.resolve-expr ctx "$request.body"))))
              (it "resolves $steps.s1.request.body#/q"
                  (fn []
                    (assert.are.equal "search"
                                      (expr.resolve-expr ctx
                                                         "$steps.s1.request.body#/q"))))
              (it "errors on non-expression string"
                  (fn []
                    (assert.has.error (fn []
                                        (expr.resolve-expr ctx "notanexpr"))))))))

;; ---- expr: eval-template ----

(describe "eval-template"
          (fn []
            (let [ctx {:inputs {:env "prod" :v 3}
                       :steps {}
                       :workflows {}
                       :response nil
                       :request nil}]
              (it "substitutes single expression"
                  (fn []
                    (assert.are.equal "env=prod"
                                      (expr.eval-template ctx
                                                          "env={$inputs.env}"))))
              (it "substitutes multiple expressions"
                  (fn []
                    (assert.are.equal "prod-3"
                                      (expr.eval-template ctx
                                                          "{$inputs.env}-{$inputs.v}"))))
              (it "leaves non-expression text unchanged"
                  (fn []
                    (assert.are.equal "hello world"
                                      (expr.eval-template ctx "hello world"))))
              (it "replaces unknown expr with empty string"
                  (fn []
                    (assert.are.equal "val="
                                      (expr.eval-template ctx
                                                          "val={$inputs.missing}")))))))

;; ---- expr: eval-criterion simple ----

(describe "eval-criterion simple"
          (fn []
            (let [ctx {:inputs {}
                       :steps {}
                       :workflows {}
                       :response {:status 404 :headers {} :body {:count 5}}
                       :request nil}]
              (it "== passes"
                  (fn []
                    (assert.is_true (expr.eval-criterion ctx
                                                         {:condition "$statusCode == 404"}))))
              (it "== fails"
                  (fn []
                    (assert.is_false (expr.eval-criterion ctx
                                                          {:condition "$statusCode == 200"}))))
              (it "!= passes"
                  (fn []
                    (assert.is_true (expr.eval-criterion ctx
                                                         {:condition "$statusCode != 200"}))))
              (it "!= fails"
                  (fn []
                    (assert.is_false (expr.eval-criterion ctx
                                                          {:condition "$statusCode != 404"}))))
              (it "> passes"
                  (fn []
                    (assert.is_true (expr.eval-criterion ctx
                                                         {:condition "$response.body#/count > 4"}))))
              (it "> fails"
                  (fn []
                    (assert.is_false (expr.eval-criterion ctx
                                                          {:condition "$response.body#/count > 5"}))))
              (it ">= passes on equal"
                  (fn []
                    (assert.is_true (expr.eval-criterion ctx
                                                         {:condition "$response.body#/count >= 5"}))))
              (it "< passes"
                  (fn []
                    (assert.is_true (expr.eval-criterion ctx
                                                         {:condition "$response.body#/count < 10"}))))
              (it "<= passes on equal"
                  (fn []
                    (assert.is_true (expr.eval-criterion ctx
                                                         {:condition "$response.body#/count <= 5"}))))
              (it "|| short-circuits on first true"
                  (fn []
                    (assert.is_true (expr.eval-criterion ctx
                                                         {:condition "$statusCode == 200 || $statusCode == 404"}))))
              (it "&& requires both true"
                  (fn []
                    (assert.is_false (expr.eval-criterion ctx
                                                          {:condition "$statusCode == 404 && $statusCode == 200"}))))
              (it "string literal comparison"
                  (fn []
                    (let [ctx2 {:inputs {}
                                :steps {}
                                :workflows {}
                                :response {:status 200
                                           :headers {}
                                           :body {:state "active"}}
                                :request nil}]
                      (assert.is_true (expr.eval-criterion ctx2
                                                           {:condition "$response.body#/state == \"active\""}))))))))

;; ---- expr: $find ----

(describe "expr $find"
          (fn []
            (let [ctx {:inputs {:name "bob"}
                       :steps {}
                       :workflows {}
                       :response {:status 200
                                  :headers {}
                                  :body {:users [{:id "1" :name "alice"}
                                                 {:id "2" :name "bob"}
                                                 {:id "3" :name "carol"}]}}
                       :request nil}]
              (it "returns matching item when return-field omitted"
                  (fn []
                    (assert.are.same {:id "2" :name "bob"}
                                     (expr.resolve-expr ctx
                                                        "$find($response.body#/users, name, $inputs.name)"))))
              (it "returns specific field when return-field given"
                  (fn []
                    (assert.are.equal "2"
                                      (expr.resolve-expr ctx
                                                         "$find($response.body#/users, name, $inputs.name, id)"))))
              (it "returns nil when no match"
                  (fn []
                    (let [ctx2 {:inputs {:name "nobody"}
                                :steps {}
                                :workflows {}
                                :response {:status 200
                                           :headers {}
                                           :body {:users [{:id "1"
                                                           :name "alice"}]}}
                                :request nil}]
                      (assert.is_nil (expr.resolve-expr ctx2
                                                        "$find($response.body#/users, name, $inputs.name, id)")))))
              (it "works as step output expression"
                  (fn []
                    (let [clients {:api (make-client {:list-users (fn []
                                                                    (ok-resp {:users [{:id "u1"
                                                                                       :name "alice"}
                                                                                      {:id "u2"
                                                                                       :name "bob"}]}))})}
                          doc {:arazzo "1.0.0"
                               :info {}
                               :workflows [{:workflowId "find-user"
                                            :steps [{:stepId "list"
                                                     :operationId "list-users"
                                                     :successCriteria [{:condition "$statusCode == 200"}]
                                                     :outputs {:id "$find($response.body#/users, name, $inputs.name, id)"}}]
                                            :outputs {:id "$steps.list.outputs.id"}}]}
                          result (arazzo.run-workflow doc "find-user"
                                                      {:name "bob"} clients {})]
                      (assert.are.equal "u2" result.outputs.id)))))))

;; ---- expr: $workflows output ----

(describe "expr $workflows"
          (fn []
            (it "resolves $workflows.id.outputs.key"
                (fn []
                  (let [ctx {:inputs {}
                             :steps {}
                             :workflows {:myWf {:outputs {:token "wf-tok"}}}
                             :response nil
                             :request nil}]
                    (assert.are.equal "wf-tok"
                                      (expr.resolve-expr ctx
                                                         "$workflows.myWf.outputs.token")))))
            (it "returns nil for unknown workflow"
                (fn []
                  (let [ctx {:inputs {}
                             :steps {}
                             :workflows {}
                             :response nil
                             :request nil}]
                    (assert.is_nil (expr.resolve-expr ctx
                                                      "$workflows.missing.outputs.x")))))))

;; ---- expr: regex criterion ----

(describe "eval-criterion regex"
          (fn []
            (let [ctx {:inputs {}
                       :steps {}
                       :workflows {}
                       :response {:status 201 :headers {} :body {}}
                       :request nil}]
              (it "matches pattern on status"
                  (fn []
                    (assert.is_true (expr.eval-criterion ctx
                                                         {:type :regex
                                                          :context "$statusCode"
                                                          :condition "^2"}))))
              (it "fails when pattern does not match"
                  (fn []
                    (assert.is_false (expr.eval-criterion ctx
                                                          {:type :regex
                                                           :context "$statusCode"
                                                           :condition "^4"}))))
              (it "matches on string body field"
                  (fn []
                    (let [ctx2 {:inputs {}
                                :steps {}
                                :workflows {}
                                :response {:status 200
                                           :headers {}
                                           :body {:msg "hello world"}}
                                :request nil}]
                      (assert.is_true (expr.eval-criterion ctx2
                                                           {:type :regex
                                                            :context "$response.body#/msg"
                                                            :condition "world"}))))))))

;; ---- operation resolution and parameters ----

(fn one-step-doc [step ?wf-params]
  {:arazzo "1.0.0"
   :info {}
   :workflows [{:workflowId "wf"
                :parameters ?wf-params
                :steps [(doto step
                          (tset :stepId "s1")
                          (tset :successCriteria
                                [{:condition "$statusCode == 200"}]))]
                :outputs {}}]})

(describe "run-workflow operation resolution"
          (fn []
            (it "finds camelCase operationId on kebab-keyed client"
                (fn []
                  (let [c (counter)
                        clients {:api {:get-pet-by-id {:operation-id "getPetById"
                                                       :method "get"
                                                       :url-for #"u"
                                                       :invoke (fn [] (c.inc)
                                                                 (ok-resp {}))}}}]
                    (arazzo.run-workflow (one-step-doc {:operationId "getPetById"})
                                         "wf" {} clients {})
                    (assert.are.equal 1 (c.val)))))
            (it "scopes $sourceDescriptions operationId to that source"
                (fn []
                  (let [log []
                        clients {:a (make-client {:op (fn []
                                                        (table.insert log :a)
                                                        (ok-resp {}))})
                                 :b (make-client {:op (fn []
                                                        (table.insert log :b)
                                                        (ok-resp {}))})}]
                    (arazzo.run-workflow (one-step-doc {:operationId "$sourceDescriptions.b.op"})
                                         "wf" {} clients {})
                    (assert.are.same [:b] log))))))

(describe "run-workflow parameters"
          (fn []
            (it "passes path params by name regardless of order"
                (fn []
                  (let [seen []
                        clients {:api (make-client {:op (fn [req]
                                                          (table.insert seen
                                                                        req.path)
                                                          (ok-resp {}))})}]
                    (arazzo.run-workflow (one-step-doc {:operationId "op"
                                                        :parameters [{:in :path
                                                                      :name "petId"
                                                                      :value 2}
                                                                     {:in :path
                                                                      :name "ownerId"
                                                                      :value 1}]})
                                         "wf" {} clients {})
                    (assert.are.same {:petId 2 :ownerId 1} (. seen 1)))))
            (it "lets step parameters override workflow parameters"
                (fn []
                  (let [seen []
                        clients {:api (make-client {:op (fn [req]
                                                          (table.insert seen
                                                                        req.query)
                                                          (ok-resp {}))})}]
                    (arazzo.run-workflow (one-step-doc {:operationId "op"
                                                        :parameters [{:in :query
                                                                      :name "env"
                                                                      :value "step"}]}
                                                       [{:in :query
                                                         :name "env"
                                                         :value "wf"}])
                                         "wf" {} clients {})
                    (assert.are.same {:env "step"} (. seen 1)))))
            (it "sends query params without a body"
                (fn []
                  (let [seen []
                        clients {:api (make-client {:op (fn [req]
                                                          (table.insert seen
                                                                        req)
                                                          (ok-resp {}))})}]
                    (arazzo.run-workflow (one-step-doc {:operationId "op"
                                                        :parameters [{:in :query
                                                                      :name "q"
                                                                      :value "x"}]})
                                         "wf" {} clients {})
                    (assert.is_nil (. seen 1 :body))
                    (assert.are.same {:q "x"} (. seen 1 :query)))))))

(describe "run-workflow workflows and actions"
          (fn []
            (it "exposes sub-workflow outputs via $workflows"
                (fn []
                  (let [clients {:api (make-client {:op (fn [] (ok-resp {:v 7}))})}
                        doc {:arazzo "1.0.0"
                             :info {}
                             :workflows [{:workflowId "inner"
                                          :steps [{:stepId "s1"
                                                   :operationId "op"
                                                   :outputs {:val "$response.body#/v"}}]
                                          :outputs {:result "$steps.s1.outputs.val"}}
                                         {:workflowId "outer"
                                          :steps [{:stepId "sub"
                                                   :workflowId "inner"}]
                                          :outputs {:x "$workflows.inner.outputs.result"}}]}
                        result (arazzo.run-workflow doc "outer" {} clients {})]
                    (assert.are.equal 7 result.outputs.x))))
            (it "retries a failing step up to retryLimit"
                (fn []
                  (let [c (counter)
                        op (fn []
                             (c.inc)
                             (ok-resp {} (if (< (c.val) 3) 503 200)))
                        clients {:api (make-client {:op op})}]
                    (arazzo.run-workflow (one-step-doc {:operationId "op"
                                                        :onFailure [{:name "again"
                                                                     :type :retry
                                                                     :retryAfter 0
                                                                     :retryLimit 2}]})
                                         "wf" {} clients {})
                    (assert.are.equal 3 (c.val)))))
            (it "fails once retryLimit is exhausted"
                (fn []
                  (let [c (counter)
                        clients {:api (make-client {:op (fn [] (c.inc)
                                                          (ok-resp {} 503))})}]
                    (assert.has.error #(arazzo.run-workflow (one-step-doc {:operationId "op"
                                                                           :onFailure [{:name "again"
                                                                                        :type :retry
                                                                                        :retryAfter 0
                                                                                        :retryLimit 1}]})
                                                            "wf" {} clients {}))
                    (assert.are.equal 2 (c.val)))))
            (it "retries once when retryLimit is absent"
                (fn []
                  (let [c (counter)
                        clients {:api (make-client {:op (fn [] (c.inc)
                                                          (ok-resp {} 503))})}]
                    (assert.has.error #(arazzo.run-workflow (one-step-doc {:operationId "op"
                                                                           :onFailure [{:name "again"
                                                                                        :type :retry
                                                                                        :retryAfter 0}]})
                                                            "wf" {} clients {}))
                    (assert.are.equal 2 (c.val)))))
            (it "resolves $components parameter and action references"
                (fn []
                  (let [seen []
                        clients {:api (make-client {:op (fn [req]
                                                          (table.insert seen
                                                                        req.query)
                                                          (ok-resp {}))
                                                    :other (fn []
                                                             (table.insert seen
                                                                           :other)
                                                             (ok-resp {}))})}
                        doc {:arazzo "1.0.0"
                             :info {}
                             :components {:parameters {:env {:name "env"
                                                             :in "query"
                                                             :value "prod"}
                                                       :page {:name "page"
                                                              :in "query"
                                                              :value "1"}}
                                          :successActions {:finish {:name "finish"
                                                                    :type "end"}}}
                             :workflows [{:workflowId "wf"
                                          :steps [{:stepId "s1"
                                                   :operationId "op"
                                                   :parameters [{:reference "$components.parameters.env"}
                                                                {:reference "$components.parameters.page"
                                                                 :value "2"}]
                                                   :onSuccess [{:reference "$components.successActions.finish"}]}
                                                  {:stepId "s2"
                                                   :operationId "other"}]
                                          :outputs {}}]}]
                    (arazzo.run-workflow doc "wf" {} clients {})
                    (assert.are.same [{:env "prod" :page "2"}] seen))))
            (it "applies workflow-level failureActions to steps without their own"
                (fn []
                  (let [c (counter)
                        clients {:api (make-client {:op (fn []
                                                          (c.inc)
                                                          (ok-resp {}
                                                                   (if (< (c.val)
                                                                          2)
                                                                       503
                                                                       200)))})}
                        doc (one-step-doc {:operationId "op"})]
                    (tset (. doc.workflows 1) :failureActions
                          [{:name "r" :type "retry" :retryAfter 0}])
                    (arazzo.run-workflow doc "wf" {} clients {})
                    (assert.are.equal 2 (c.val))))
                (it "exposes $method and $url of the step request"
                    (fn []
                      (let [clients {:api (make-client {:op (fn [] (ok-resp {}))})}
                            result (arazzo.run-workflow {:arazzo "1.0.0"
                                                         :info {}
                                                         :workflows [{:workflowId "wf"
                                                                      :steps [{:stepId "s1"
                                                                               :operationId "op"
                                                                               :parameters [{:in "query"
                                                                                             :name "a"
                                                                                             :value "1"}]
                                                                               :outputs {:m "$method"
                                                                                         :u "$url"}}]
                                                                      :outputs {:m "$steps.s1.outputs.m"
                                                                                :u "$steps.s1.outputs.u"}}]}
                                                        "wf" {} clients {})]
                        (assert.are.same {:m "GET" :u "https://api.test/op?q"}
                                         result.outputs)))))
            (it "records steps in execution order"
                (fn []
                  (let [clients {:api (make-client {:op (fn [] (ok-resp {}))})}
                        result (arazzo.run-workflow {:arazzo "1.0.0"
                                                     :info {}
                                                     :workflows [{:workflowId "wf"
                                                                  :steps [{:stepId "zeta"
                                                                           :operationId "op"}
                                                                          {:stepId "alpha"
                                                                           :operationId "op"}]}]}
                                                    "wf" {} clients {})]
                    (assert.are.same ["zeta" "alpha"] result.step-order)))
                (it "keeps workflow-level actions that a step does not override"
                    (fn []
                      (let [log []
                            clients {:api (make-client {:op (fn []
                                                              (table.insert log
                                                                            :op)
                                                              (ok-resp {} 500))
                                                        :cleanup (fn []
                                                                   (table.insert log
                                                                                 :cleanup)
                                                                   (ok-resp {}))})}
                            doc {:arazzo "1.0.0"
                                 :info {}
                                 :workflows [{:workflowId "wf"
                                              :failureActions [{:name "to-cleanup"
                                                                :type "goto"
                                                                :stepId "c"}]
                                              :steps [{:stepId "s1"
                                                       :operationId "op"
                                                       :successCriteria [{:condition "$statusCode == 200"}]
                                                       :onFailure [{:name "again"
                                                                    :type "retry"
                                                                    :retryAfter 0
                                                                    :retryLimit 1}]
                                                       :onSuccess [{:name "done"
                                                                    :type "end"}]}
                                                      {:stepId "c"
                                                       :operationId "cleanup"}]}]}]
                        (arazzo.run-workflow doc "wf" {} clients {})
                        (assert.are.same [:op :op :cleanup] log))))
                (it "lets a step action replace the workflow action with the same name"
                    (fn []
                      (let [log []
                            clients {:api (make-client {:op (fn []
                                                              (table.insert log
                                                                            :op)
                                                              (ok-resp {} 500))
                                                        :other (fn []
                                                                 (table.insert log
                                                                               :other)
                                                                 (ok-resp {}))})}
                            doc {:arazzo "1.0.0"
                                 :info {}
                                 :workflows [{:workflowId "wf"
                                              :failureActions [{:name "f"
                                                                :type "goto"
                                                                :stepId "other"}]
                                              :steps [{:stepId "s1"
                                                       :operationId "op"
                                                       :successCriteria [{:condition "$statusCode == 200"}]
                                                       :onFailure [{:name "f"
                                                                    :type "end"}]}
                                                      {:stepId "other"
                                                       :operationId "other"}]}]}]
                        (arazzo.run-workflow doc "wf" {} clients {})
                        (assert.are.same [:op] log)))))
            (it "allows raising the goto limit"
                (fn []
                  (let [c (counter)
                        clients {:api (make-client {:op (fn []
                                                          (c.inc)
                                                          (ok-resp {:done (>= (c.val)
                                                                              60)}))})}
                        doc (one-step-doc {:operationId "op"
                                           :onSuccess [{:name "poll"
                                                        :type "goto"
                                                        :stepId "s1"
                                                        :criteria [{:condition "$response.body#/done == false"}]}]})]
                    (assert.has.error #(arazzo.run-workflow doc "wf" {} clients
                                                            {}))
                    (let [c2 (counter)
                          clients2 {:api (make-client {:op (fn []
                                                             (c2.inc)
                                                             (ok-resp {:done (>= (c2.val)
                                                                                 60)}))})}]
                      (arazzo.run-workflow doc "wf" {} clients2
                                           {:max-gotos 100})
                      (assert.are.equal 60 (c2.val))))))))
