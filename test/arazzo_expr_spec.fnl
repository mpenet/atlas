;; ABOUTME: Specs for Arazzo runtime expressions, templates and criteria.
;; ABOUTME: Run with `make test` (busted, Fennel loader).
(local expr (require :atlas.arazzo.expr))

(fn ctx []
  {:inputs {:host "api.example.com" :userId "42" :limit 10}
   :response {:status 200
              :headers {:content-type "application/json" :x-trace "abc"}
              :body {:token "tok123"
                     :user {:id 1 :name "Rex"}
                     :items [{:id 1} {:id 2}]}}
   :request {:url "https://api.example.com/users"
             :method "GET"
             :body {:q "search"}}
   :steps {:login {:outputs {:token "bearer-tok" :userId 99}
                   :response {:status 200
                              :headers {}
                              :body {:access_token "at123"}}
                   :request {:body {:username "u"} :headers {}}}
           :getUser {:outputs {:name "Rex"} :response nil :request nil}}
   :workflows {}})

;; ---- json-pointer ----

(describe "json-pointer"
          (fn []
            (it "resolves top-level key"
                (fn []
                  (assert.are.equal "tok123"
                                    (expr.json-pointer {:token "tok123"}
                                                       "/token"))))
            (it "resolves nested key"
                (fn []
                  (assert.are.equal "Rex"
                                    (expr.json-pointer {:user {:name "Rex"}}
                                                       "/user/name"))))
            (it "resolves array index (0-based)"
                (fn []
                  (assert.are.equal 2
                                    (expr.json-pointer [{:id 1} {:id 2}]
                                                       "/1/id"))))
            (it "returns nil for missing key"
                (fn []
                  (assert.is_nil (expr.json-pointer {:a 1} "/b"))))
            (it "handles ~1 as / and ~0 as ~"
                (fn []
                  (assert.are.equal "v" (expr.json-pointer {"a/b" "v"} "/a~1b"))))))

;; ---- eval ----

(describe "expr.eval"
          (fn []
            (it "resolves $inputs.key"
                (fn []
                  (assert.are.equal "42" (expr.eval (ctx) "$inputs.userId"))))
            (it "resolves $statusCode"
                (fn []
                  (assert.are.equal 200 (expr.eval (ctx) "$statusCode"))))
            (it "resolves $url"
                (fn []
                  (assert.are.equal "https://api.example.com/users"
                                    (expr.eval (ctx) "$url"))))
            (it "resolves $response.body#/token"
                (fn []
                  (assert.are.equal "tok123"
                                    (expr.eval (ctx) "$response.body#/token"))))
            (it "resolves $response.body#/user/name"
                (fn []
                  (assert.are.equal "Rex"
                                    (expr.eval (ctx)
                                               "$response.body#/user/name"))))
            (it "resolves $response.header.x-trace"
                (fn []
                  (assert.are.equal "abc"
                                    (expr.eval (ctx) "$response.header.x-trace"))))
            (it "resolves $request.body#/q"
                (fn []
                  (assert.are.equal "search"
                                    (expr.eval (ctx) "$request.body#/q"))))
            (it "resolves $steps.login.outputs.token"
                (fn []
                  (assert.are.equal "bearer-tok"
                                    (expr.eval (ctx)
                                               "$steps.login.outputs.token"))))
            (it "resolves $steps.login.response.body#/access_token"
                (fn []
                  (assert.are.equal "at123"
                                    (expr.eval (ctx)
                                               "$steps.login.response.body#/access_token"))))
            (it "resolves $sourceDescriptions sentinel"
                (fn []
                  (let [v (expr.eval (ctx) "$sourceDescriptions.myapi.getPet")]
                    (assert.are.equal "myapi" v.__source)
                    (assert.are.equal "getPet" v.__operationId))))
            (it "returns expr unchanged when not a $ expression"
                (fn []
                  (assert.are.equal "hello" (expr.eval (ctx) "hello"))))
            (it "substitutes {$expr} templates"
                (fn []
                  (let [result (expr.eval (ctx)
                                          "https://{$inputs.host}/users/{$inputs.userId}")]
                    (assert.are.equal "https://api.example.com/users/42" result))))))

;; ---- eval-criterion: simple ----

(describe "eval-criterion simple"
          (fn []
            (it "== true for matching status"
                (fn []
                  (assert.is_true (expr.eval-criterion (ctx)
                                                       {:condition "$statusCode == 200"}))))
            (it "== false for non-matching status"
                (fn []
                  (assert.is_false (expr.eval-criterion (ctx)
                                                        {:condition "$statusCode == 404"}))))
            (it "!= works"
                (fn []
                  (assert.is_true (expr.eval-criterion (ctx)
                                                       {:condition "$statusCode != 404"}))))
            (it ">= works"
                (fn []
                  (assert.is_true (expr.eval-criterion (ctx)
                                                       {:condition "$statusCode >= 200"}))
                  (assert.is_false (expr.eval-criterion (ctx)
                                                        {:condition "$statusCode >= 300"}))))
            (it "&& requires both true"
                (fn []
                  (assert.is_true (expr.eval-criterion (ctx)
                                                       {:condition "$statusCode == 200 && $statusCode != 404"}))
                  (assert.is_false (expr.eval-criterion (ctx)
                                                        {:condition "$statusCode == 200 && $statusCode == 404"}))))
            (it "|| requires at least one true"
                (fn []
                  (assert.is_true (expr.eval-criterion (ctx)
                                                       {:condition "$statusCode == 404 || $statusCode == 200"}))
                  (assert.is_false (expr.eval-criterion (ctx)
                                                        {:condition "$statusCode == 404 || $statusCode == 500"}))))
            (it "string comparison"
                (fn []
                  (assert.is_true (expr.eval-criterion (ctx)
                                                       {:condition "$response.body#/token == \"tok123\""}))))
            (it "missing value is falsy"
                (fn []
                  (assert.is_false (expr.eval-criterion (ctx)
                                                        {:condition "$response.body#/missing == \"x\""})))))
          ;; ---- eval-criterion: regex ----
          (describe "eval-criterion regex"
                    (fn []
                      (it "matches 2xx pattern on status code"
                          (fn []
                            (assert.is_true (expr.eval-criterion (ctx)
                                                                 {:type :regex
                                                                  :context "$statusCode"
                                                                  :condition "^2"}))))
                      (it "fails when no match"
                          (fn []
                            (assert.is_false (expr.eval-criterion (ctx)
                                                                  {:type :regex
                                                                   :context "$statusCode"
                                                                   :condition "^4"}))))))
          ;; ---- eval-criteria ----
          (describe "eval-criteria"
                    (fn []
                      (it "empty criteria always passes"
                          (fn []
                            (assert.is_true (expr.eval-criteria (ctx) []))))
                      (it "all must pass (AND)"
                          (fn []
                            (assert.is_true (expr.eval-criteria (ctx)
                                                                [{:condition "$statusCode == 200"}
                                                                 {:condition "$statusCode != 500"}]))
                            (assert.is_false (expr.eval-criteria (ctx)
                                                                 [{:condition "$statusCode == 200"}
                                                                  {:condition "$statusCode == 500"}])))))))

;; ---- simple condition grammar ----

(describe "eval-criterion simple grammar"
          (fn []
            (let [ctx {:inputs {}
                       :steps {}
                       :workflows {}
                       :response {:status 200
                                  :headers {}
                                  :body {:state "active"
                                         :ok true
                                         :n 3
                                         :s "a && b"
                                         :evil "x\" || \"a\" == \"a"}}}
                  check #(expr.eval-criterion ctx {:condition $})]
              (it "does not let response data change the condition"
                  (fn []
                    (assert.is_false (check "$response.body#/evil == \"safe\""))))
              (it "supports single-quoted strings"
                  (fn []
                    (assert.is_true (check "$response.body#/state == 'active'"))))
              (it "keeps operators inside string literals"
                  (fn []
                    (assert.is_true (check "$response.body#/s == 'a && b'"))))
              (it "groups with parentheses"
                  (fn []
                    (assert.is_true (check "($statusCode == 201 || $statusCode == 200) && $response.body#/ok == true"))
                    (assert.is_false (check "$statusCode == 201 || ($statusCode == 200 && $response.body#/ok == false)"))))
              (it "negates with !"
                  (fn []
                    (assert.is_true (check "!($statusCode == 500)"))
                    (assert.is_false (check "!$response.body#/ok"))))
              (it "binds && tighter than ||"
                  (fn []
                    (assert.is_true (check "$statusCode == 200 || $statusCode == 1 && $statusCode == 2"))))
              (it "compares with null"
                  (fn []
                    (assert.is_true (check "$response.body#/missing == null"))
                    (assert.is_true (check "$response.body#/state != null"))))
              (it "treats a bare expression as a truthiness test"
                  (fn [] (assert.is_true (check "$response.body#/ok"))))
              (it "compares numbers numerically"
                  (fn [] (assert.is_true (check "$response.body#/n < 10"))))
              (it "raises on malformed conditions"
                  (fn []
                    (assert.has.error #(check "$statusCode =="))
                    (assert.has.error #(check "($statusCode == 200"))
                    (assert.has.error #(check "$statusCode == 200 junk ==")))))))

(describe "ordered comparisons with numeric strings"
          (fn []
            (let [ctx {:response {:status 200
                                  :headers {:x-count "10"}
                                  :body {:n 5
                                         :items [{:id "a,b" :v 1}
                                                 {:id "c" :v 2}]}}}
                  check #(expr.eval-criterion ctx {:condition $})]
              (it "compares a numeric header with a number"
                  (fn []
                    (assert.is_true (check "$response.header.X-Count > 5"))))
              (it "compares a number with a numeric string literal"
                  (fn [] (assert.is_true (check "$response.body#/n > '3'"))))
              (it "reports a stray null token readably"
                  (fn []
                    (let [(ok err) (pcall check "$statusCode == 200 null")]
                      (assert.is_false ok)
                      (assert.is_truthy (: (tostring err) :find
                                           "unexpected 'null'" 1 true)))))
              (it "$find accepts a quoted match value"
                  (fn []
                    (assert.are.equal 2
                                      (expr.resolve-expr ctx
                                                         "$find($response.body#/items, id, 'c', v)")))))))

;; ---- expr: json-pointer ----

(describe "json-pointer on nil"
          (fn []
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

(describe "eval-criterion ordered comparisons"
          (fn []
            (let [ctx {:inputs {}
                       :steps {}
                       :workflows {}
                       :response {:status 404 :headers {} :body {:count 5}}
                       :request nil}]
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
                                                         {:condition "$response.body#/count <= 5"})))))))

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
                                                        "$find($response.body#/users, name, $inputs.name, id)"))))))))

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

(describe "eval-criterion regex on body fields"
          (fn []
            (let [ctx {:inputs {}
                       :steps {}
                       :workflows {}
                       :response {:status 201 :headers {} :body {}}
                       :request nil}]
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
