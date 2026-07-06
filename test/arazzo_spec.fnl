(local arazzo (require :atlas.arazzo))
(local expr (require :atlas.arazzo.expr))

;; ---- helpers ----

(fn make-client [ops]
  ops)

(fn ok-resp [body ?status]
  {:status (or ?status 200)
   :headers {:content-type "application/json"}
   :body body})

(fn counter []
  (let [n [0]]
    {:inc (fn [] (tset n 1 (+ (. n 1) 1)))
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
          (assert.is_nil (. clients :someSource))
          (assert.is_not_nil (. clients :__path_index)))))

    (it "skips non-openapi sources"
      (fn []
        (let [doc {:sourceDescriptions [{:name "ext" :type "arazzo" :url "other.yaml"}]
                   :workflows []}
              clients (arazzo.build-clients doc {})]
          (assert.is_nil (. clients :ext))
          (assert.is_not_nil (. clients :__path_index)))))))

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
                   :workflows
                   [{:workflowId "auth"
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
              clients {:api (make-client
                              {:op1 (make-op :s1)
                               :op2 (make-op :s2)
                               :op3 (make-op :s3)})}
              doc {:arazzo "1.0.0"
                   :info {}
                   :workflows
                   [{:workflowId "wf"
                     :steps
                     [{:stepId "s1" :operationId "op1"
                       :successCriteria [{:condition "$statusCode == 200"}]
                       :onSuccess [{:type :goto :stepId "s3"}]}
                      {:stepId "s2" :operationId "op2"
                       :successCriteria [{:condition "$statusCode == 200"}]}
                      {:stepId "s3" :operationId "op3"
                       :successCriteria [{:condition "$statusCode == 200"}]}]
                     :outputs {}}]}]
          (arazzo.run-workflow doc "wf" {} clients {})
          (assert.are.same [:s1 :s3] call-log))))

    (it "executes onFailure end action"
      (fn []
        (let [clients {:api (make-client
                              {:failop (fn [] (ok-resp {:e "err"} 500))})}
              doc {:arazzo "1.0.0"
                   :info {}
                   :workflows
                   [{:workflowId "wf"
                     :steps
                     [{:stepId "s1"
                       :operationId "failop"
                       :successCriteria [{:condition "$statusCode == 200"}]
                       :onFailure [{:type :end}]}]
                     :outputs {}}]}
              result (arazzo.run-workflow doc "wf" {} clients {})]
          (assert.are.same {} result.outputs))))

    (it "raises on step failure with no action"
      (fn []
        (let [clients {:api (make-client
                              {:failop (fn [] (ok-resp {} 500))})}
              doc {:arazzo "1.0.0"
                   :info {}
                   :workflows
                   [{:workflowId "wf"
                     :steps [{:stepId "s1"
                              :operationId "failop"
                              :successCriteria [{:condition "$statusCode == 200"}]}]
                     :outputs {}}]}]
          (assert.has.error
            (fn [] (arazzo.run-workflow doc "wf" {} clients {}))
            "step 's1' failed success criteria (HTTP 500 {})"))))

    (it "passes inputs to steps via path parameters"
      (fn []
        (let [received []
              op (fn [v] (table.insert received v) (ok-resp {}))
              clients {:api (make-client {:getUser op})}
              doc {:arazzo "1.0.0"
                   :info {}
                   :workflows
                   [{:workflowId "wf"
                     :steps [{:stepId "s1"
                              :operationId "getUser"
                              :parameters [{:in :path :name "id" :value "$inputs.userId"}]
                              :successCriteria [{:condition "$statusCode == 200"}]}]
                     :outputs {}}]}]
          (arazzo.run-workflow doc "wf" {:userId "42"} clients {})
          (assert.are.equal "42" (. received 1)))))

    (it "merges workflow-level parameters into steps"
      (fn []
        (let [received []
              op (fn [v] (table.insert received v) (ok-resp {}))
              clients {:api (make-client {:op op})}
              doc {:arazzo "1.0.0"
                   :info {}
                   :workflows
                   [{:workflowId "wf"
                     :parameters [{:in :path :name "env" :value "$inputs.env"}]
                     :steps [{:stepId "s1"
                              :operationId "op"
                              :successCriteria [{:condition "$statusCode == 200"}]}]
                     :outputs {}}]}]
          (arazzo.run-workflow doc "wf" {:env "prod"} clients {})
          (assert.are.equal "prod" (. received 1)))))

    (it "resolves requestBody.payload expression"
      (fn []
        (let [received []
              op (fn [body] (table.insert received body) (ok-resp {}))
              clients {:api (make-client {:createUser op})}
              doc {:arazzo "1.0.0"
                   :info {}
                   :workflows
                   [{:workflowId "wf"
                     :steps [{:stepId "s1"
                              :operationId "createUser"
                              :requestBody {:payload "$inputs.user"}
                              :successCriteria [{:condition "$statusCode == 200"}]}]
                     :outputs {}}]}]
          (arazzo.run-workflow doc "wf" {:user {:name "alice"}} clients {})
          (assert.are.same {:name "alice"} (. received 1)))))

    (it "propagates step outputs via $steps expression"
      (fn []
        (let [login-resp (ok-resp {:access_token "tok-abc"})
              use-resp (ok-resp {:ok true})
              token-used []
              clients {:api (make-client
                              {:login (fn [] login-resp)
                               :use   (fn [t] (table.insert token-used t) use-resp)})}
              doc {:arazzo "1.0.0"
                   :info {}
                   :workflows
                   [{:workflowId "wf"
                     :steps
                     [{:stepId "login"
                       :operationId "login"
                       :successCriteria [{:condition "$statusCode == 200"}]
                       :outputs {:token "$response.body#/access_token"}}
                      {:stepId "use"
                       :operationId "use"
                       :parameters [{:in :path :name "t"
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
                   :workflows
                   [{:workflowId "inner"
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
        (let [clients {:api (make-client
                              {:op (fn [] (ok-resp {}))})}
              doc {:arazzo "1.0.0"
                   :info {}
                   :workflows
                   [{:workflowId "wf"
                     :steps [{:stepId "s1"
                              :operationId "op"
                              :successCriteria [{:condition "$statusCode == 200"}]
                              :onSuccess [{:type :goto :stepId "s1"}]}]
                     :outputs {}}]}]
          (assert.has.error
            (fn [] (arazzo.run-workflow doc "wf" {} clients {}))
            "goto loop detected at: s1"))))

    (it "resolves operationPath via path index"
      (fn []
        (let [resp (ok-resp {:id 1})
              c (counter)
              op (fn [] (c.inc) resp)
              clients {:api {}
                       :__path_index {:api {"get /users" op}}}
              doc {:arazzo "1.0.0"
                   :info {}
                   :workflows
                   [{:workflowId "wf"
                     :steps [{:stepId "s1"
                              :operationPath "{$sourceDescriptions.api.url}#/paths/~1users/get"
                              :successCriteria [{:condition "$statusCode == 200"}]}]
                     :outputs {}}]}]
          (arazzo.run-workflow doc "wf" {} clients {})
          (assert.are.equal 1 (c.val)))))

    (it "raises on operationPath with missing source"
      (fn []
        (let [clients {:__path_index {}}
              doc {:arazzo "1.0.0"
                   :info {}
                   :workflows
                   [{:workflowId "wf"
                     :steps [{:stepId "s1"
                              :operationPath "{$sourceDescriptions.missing.url}#/paths/~1users/get"}]
                     :outputs {}}]}]
          (assert.has.error
            (fn [] (arazzo.run-workflow doc "wf" {} clients {}))
            "operationPath: no path index for source 'missing'"))))

    (it "calls on-step callback with running and done events"
      (fn []
        (let [events []
              clients {:api (make-client {:op (fn [] (ok-resp {}))})}
              doc {:arazzo "1.0.0"
                   :info {}
                   :workflows
                   [{:workflowId "wf"
                     :steps [{:stepId "s1"
                              :operationId "op"
                              :successCriteria [{:condition "$statusCode == 200"}]}]
                     :outputs {}}]}
              on-step (fn [ev] (table.insert events ev.status))]
          (arazzo.run-workflow doc "wf" {} clients {:on-step on-step})
          (assert.are.same [:running :done] events))))))

;; ---- expr: $workflows output ----

(describe "expr $workflows"
  (fn []
    (it "resolves $workflows.id.outputs.key"
      (fn []
        (let [ctx {:inputs {}
                   :steps {}
                   :workflows {:myWf {:outputs {:token "wf-tok"}}}
                   :response nil :request nil}]
          (assert.are.equal "wf-tok"
            (expr.resolve-expr ctx "$workflows.myWf.outputs.token")))))

    (it "returns nil for unknown workflow"
      (fn []
        (let [ctx {:inputs {} :steps {} :workflows {} :response nil :request nil}]
          (assert.is_nil (expr.resolve-expr ctx "$workflows.missing.outputs.x")))))))

;; ---- expr: regex criterion ----

(describe "eval-criterion regex"
  (fn []
    (let [ctx {:inputs {} :steps {} :workflows {}
               :response {:status 201 :headers {} :body {}}
               :request nil}]
      (it "matches pattern on status"
        (fn []
          (assert.is_true (expr.eval-criterion ctx
                            {:type :regex :context "$statusCode" :condition "^2"}))))
      (it "fails when pattern does not match"
        (fn []
          (assert.is_false (expr.eval-criterion ctx
                             {:type :regex :context "$statusCode" :condition "^4"}))))
      (it "matches on string body field"
        (fn []
          (let [ctx2 {:inputs {} :steps {} :workflows {}
                      :response {:status 200 :headers {}
                                 :body {:msg "hello world"}}
                      :request nil}]
            (assert.is_true (expr.eval-criterion ctx2
                              {:type :regex
                               :context "$response.body#/msg"
                               :condition "world"}))))))))
