;; ABOUTME: Specs for client construction and operation invocation.
;; ABOUTME: Run with `make test` (busted, Fennel loader).
(local atlas (require :atlas))

(fn mock-http [?body ?status]
  (let [calls []
        resp {:status (or ?status 200) :headers {} :body (or ?body {})}]
    (values (fn [req] (table.insert calls req) resp) calls)))

(fn schema [paths ?base-url]
  {:openapi "3.0.0"
   :info {:title "Test" :version "1"}
   :servers [{:url (or ?base-url "https://api.example.com")}]
   :paths paths})

(describe "atlas.client"
          (fn []
            (it "builds operations from schema"
                (fn []
                  (let [(http calls) (mock-http)
                        c (atlas.client (schema {"/pets" {:get {:operationId "listPets"
                                                                :responses {"200" {:description "ok"}}}}})
                                        {:http-fn http})]
                    (assert.is_not_nil c.list-pets)
                    (assert.is_function (. (getmetatable c.list-pets) :__call)))))
            (it "calls correct method and URL"
                (fn []
                  (let [(http calls) (mock-http)
                        c (atlas.client (schema {"/pets" {:get {:operationId "listPets"
                                                                :responses {"200" {:description "ok"}}}}})
                                        {:http-fn http})]
                    (c.list-pets)
                    (assert.are.equal 1 (length calls))
                    (assert.are.equal "GET" (. calls 1 :method))
                    (assert.are.equal "https://api.example.com/pets"
                                      (. calls 1 :url)))))
            (it "substitutes path params"
                (fn []
                  (let [(http calls) (mock-http)
                        c (atlas.client (schema {"/pets/{petId}" {:get {:operationId "getPetById"
                                                                        :parameters [{:name "petId"
                                                                                      :in "path"
                                                                                      :required true
                                                                                      :schema {:type "integer"}}]
                                                                        :responses {"200" {:description "ok"}}}}})
                                        {:http-fn http})]
                    (c.get-pet-by-id 42)
                    (assert.are.equal "https://api.example.com/pets/42"
                                      (. calls 1 :url)))))
            (it "errors on missing path param"
                (fn []
                  (let [(http) (mock-http)
                        c (atlas.client (schema {"/pets/{petId}" {:get {:operationId "getPetById"
                                                                        :parameters [{:name "petId"
                                                                                      :in "path"
                                                                                      :required true
                                                                                      :schema {:type "integer"}}]
                                                                        :responses {"200" {:description "ok"}}}}})
                                        {:http-fn http})]
                    (assert.has.error (fn [] (c.get-pet-by-id))))))
            (it "passes body for operations with requestBody"
                (fn []
                  (let [(http calls) (mock-http)
                        c (atlas.client (schema {"/pets" {:post {:operationId "addPet"
                                                                 :requestBody {:required true
                                                                               :content {:application/json {}}}
                                                                 :responses {"201" {:description "created"}}}}})
                                        {:http-fn http})
                        body {:name "Rex" :status "available"}]
                    (c.add-pet body)
                    (assert.are.same body (. calls 1 :body)))))
            (it "merges default headers"
                (fn []
                  (let [(http calls) (mock-http)
                        c (atlas.client (schema {"/pets" {:get {:operationId "listPets"
                                                                :responses {"200" {:description "ok"}}}}})
                                        {:http-fn http
                                         :headers {:x-api-key "secret"}})]
                    (c.list-pets)
                    (assert.are.equal "secret" (?. calls 1 :headers :x-api-key)))))
            (it "per-request headers override defaults"
                (fn []
                  (let [(http calls) (mock-http)
                        c (atlas.client (schema {"/pets" {:get {:operationId "listPets"
                                                                :responses {"200" {:description "ok"}}}}})
                                        {:http-fn http
                                         :headers {:x-key "default"}})]
                    (c.list-pets {:headers {:x-key "override"}})
                    (assert.are.equal "override" (?. calls 1 :headers :x-key)))))
            (it "respects base-url override"
                (fn []
                  (let [(http calls) (mock-http)
                        c (atlas.client (schema {"/pets" {:get {:operationId "listPets"
                                                                :responses {"200" {:description "ok"}}}}})
                                        {:http-fn http
                                         :base-url "https://staging.example.com"})]
                    (c.list-pets)
                    (assert.are.equal "https://staging.example.com/pets"
                                      (. calls 1 :url)))))
            (it "passes query params"
                (fn []
                  (let [(http calls) (mock-http)
                        c (atlas.client (schema {"/pets" {:get {:operationId "listPets"
                                                                :parameters [{:name "status"
                                                                              :in "query"
                                                                              :schema {:type "string"}}]
                                                                :responses {"200" {:description "ok"}}}}})
                                        {:http-fn http})]
                    (c.list-pets {:query {:status "available"}})
                    (assert.are.equal "available" (?. calls 1 :query :status)))))
            (it "operation names do not clobber internal state"
                (fn []
                  (let [(http calls) (mock-http)
                        ;; operationIds that map to internal client-opts keys
                        c (atlas.client (schema {"/h" {:get {:operationId "headers"
                                                             :responses {"200" {:description "ok"}}}}
                                                 "/b" {:get {:operationId "baseUrl"
                                                             :responses {"200" {:description "ok"}}}}})
                                        {:http-fn http
                                         :base-url "https://api.example.com"
                                         :headers {:x-test "yes"}})]
                    ;; calling the op named "headers" should not break subsequent requests
                    (c.headers)
                    (c.base-url)
                    (assert.are.equal 2 (length calls))
                    (assert.are.equal "https://api.example.com/h"
                                      (. calls 1 :url))
                    (assert.are.equal "https://api.example.com/b"
                                      (. calls 2 :url))
                    ;; default header still present
                    (assert.are.equal "yes" (?. calls 1 :headers :x-test)))))
            (it "sets Content-Type for json body"
                (fn []
                  (let [(http calls) (mock-http)
                        c (atlas.client (schema {"/pets" {:post {:operationId "addPet"
                                                                 :requestBody {:required true
                                                                               :content {:application/json {}}}
                                                                 :responses {"201" {:description "ok"}}}}})
                                        {:http-fn http})]
                    (c.add-pet {:name "Rex"})
                    (assert.are.equal "application/json"
                                      (?. calls 1 :headers :content-type)))))
            (it "sets Accept header from response content types"
                (fn []
                  (let [(http calls) (mock-http)
                        c (atlas.client (schema {"/pets" {:get {:operationId "listPets"
                                                                :responses {"200" {:description "ok"
                                                                                   :content {:application/json {}}}}}}})
                                        {:http-fn http})]
                    (c.list-pets)
                    (assert.are.equal "application/json"
                                      (?. calls 1 :headers :accept)))))))

(local pets-schema
       (schema {"/owners/{ownerId}/pets/{petId}" {:get {:operationId "getOwnerPet"
                                                        :responses {"200" {:description "ok"}}}}
                "/pets" {:post {:operationId "addPet"
                                :requestBody {:content {:application/json {}}}
                                :responses {"201" {:description "ok"
                                                   :content {:application/json {}}}}}}}))

(describe "operation invoke"
          (fn []
            (it "fills path params by name"
                (fn []
                  (let [(http calls) (mock-http)
                        c (atlas.client pets-schema {:http-fn http})]
                    (c.get-owner-pet.invoke {:path {:petId 7 :ownerId "a b"}})
                    (assert.are.equal "https://api.example.com/owners/a%20b/pets/7"
                                      (. calls 1 :url)))))
            (it "sends query without a body on a body operation"
                (fn []
                  (let [(http calls) (mock-http)
                        c (atlas.client pets-schema {:http-fn http})]
                    (c.add-pet.invoke {:query {:dry "1"}})
                    (assert.is_nil (. calls 1 :body))
                    (assert.are.same {:dry "1"} (. calls 1 :query)))))
            (it "exposes operation metadata"
                (fn []
                  (let [c (atlas.client pets-schema {:http-fn (mock-http)})]
                    (assert.are.equal "getOwnerPet"
                                      c.get-owner-pet.operation-id)
                    (assert.are.equal "/owners/{ownerId}/pets/{petId}"
                                      c.get-owner-pet.path)
                    (assert.are.equal "get" c.get-owner-pet.method)
                    (assert.are.same ["ownerId" "petId"]
                                     c.get-owner-pet.path-params))))
            (it "builds the request URL without sending"
                (fn []
                  (let [(http calls) (mock-http)
                        c (atlas.client pets-schema {:http-fn http})]
                    (assert.are.equal "https://api.example.com/owners/o/pets/1?x=y"
                                      (c.get-owner-pet.url-for {:path {:ownerId "o"
                                                                       :petId 1}
                                                                :query {:x "y"}}))
                    (assert.are.equal 0 (length calls)))))
            (it "exposes the negotiated request body schema"
                (fn []
                  (let [c (atlas.client (schema {"/x" {:post {:operationId "mk"
                                                              :requestBody {:content {:application/json {:schema {:type "object"}}}}
                                                              :responses {}}}})
                                        {:http-fn (mock-http)})]
                    (assert.are.same {:type "object"} c.mk.body-schema))))
            (it "lets request headers override negotiated ones, case-insensitively"
                (fn []
                  (let [(http calls) (mock-http)
                        c (atlas.client pets-schema {:http-fn http})]
                    (c.add-pet.invoke {:body {}
                                       :headers {:Content-Type "application/merge-patch+json"
                                                 :Accept "text/plain"}})
                    (assert.are.equal "application/merge-patch+json"
                                      (. calls 1 :headers :content-type))
                    (assert.are.equal "text/plain" (. calls 1 :headers :accept))
                    (assert.is_nil (. calls 1 :headers :Content-Type)))))))

(describe "positional call"
          (fn []
            (it "treats a nil body slot as no body and still reads opts"
                (fn []
                  (let [(http calls) (mock-http)
                        c (atlas.client pets-schema {:http-fn http})]
                    (c.add-pet nil {:query {:dry "1"}})
                    (assert.is_nil (. calls 1 :body))
                    (assert.are.same {:dry "1"} (. calls 1 :query)))))))

(describe "path-level parameters"
          (fn []
            (it "are merged into each operation, operation-level winning"
                (fn []
                  (let [c (atlas.client (schema {"/pets/{petId}" {:parameters [{:name "petId"
                                                                                :in "path"
                                                                                :required true
                                                                                :description "shared id"
                                                                                :schema {:type "string"}}
                                                                               {:name "v"
                                                                                :in "query"
                                                                                :description "path-level v"}]
                                                                  :get {:operationId "getPet"
                                                                        :parameters [{:name "v"
                                                                                      :in "query"
                                                                                      :description "op-level v"}]
                                                                        :responses {}}}})
                                        {:http-fn (mock-http)})
                        help (. c.get-pet :cli/help)]
                    (assert.is_truthy (help:find "shared id" 1 true))
                    (assert.is_truthy (help:find "op-level v" 1 true))
                    (assert.is_nil (help:find "path-level v" 1 true)))))))

(describe "server variables"
          (fn []
            (it "substitutes names containing pattern characters"
                (fn []
                  (let [(http calls) (mock-http)
                        c (atlas.client {:openapi "3.0.0"
                                         :info {}
                                         :servers [{:url "https://{api-host}/{ver.sion}"
                                                    :variables {:api-host {:default "h.example.com"}
                                                                :ver.sion {:default "v%1"}}}]
                                         :paths {"/x" {:get {:operationId "getX"
                                                             :responses {}}}}}
                                        {:http-fn http})]
                    (c.get-x)
                    (assert.are.equal "https://h.example.com/v%1/x"
                                      (. calls 1 :url)))))))
