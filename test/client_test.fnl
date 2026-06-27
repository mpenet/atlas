(local atlas (require :atlas))

(local schema
  {:openapi "3.0.0"
   :info {:title "Test" :version "1.0.0"}
   :servers [{:url "https://api.example.com"}]
   :paths
   {"/pets/{petId}"
    {:get {:operationId "getPetById"
           :parameters [{:name "petId" :in "path" :required true
                         :schema {:type "integer"}}]
           :responses {"200" {:description "ok"
                               :content {:application/json {}}}}}}
    "/pets"
    {:post {:operationId "createPet"
            :requestBody {:required true
                          :content {:application/json
                                    {:schema {:type "object"
                                              :properties {:name {:type "string"}}}}}}
            :responses {"201" {:description "created"}}}
     :get  {:operationId "listPets"
            :parameters [{:name "status" :in "query"
                          :schema {:type "string"
                                   :enum ["available" "sold"]}}]
            :responses {"200" {:description "ok"
                                :content {:application/json {}}}}}}}})

(local calls [])

(fn mock-http [req]
  (table.insert calls req)
  {:status 200 :headers {} :body {:ok true}})

(describe "atlas.client"
  #(do
    (before_each #(while (> (length calls) 0) (table.remove calls)))

    (describe "operation discovery"
      #(do
        (it "creates operations for each operationId"
          #(let [c (atlas.client schema {:http-fn mock-http})]
             (assert.is_not_nil c.get-pet-by-id)
             (assert.is_not_nil c.create-pet)
             (assert.is_not_nil c.list-pets)))
        (it "exposes has-body? metadata"
          #(let [c (atlas.client schema {:http-fn mock-http})]
             (assert.is_false c.get-pet-by-id.has-body?)
             (assert.is_truthy c.create-pet.has-body?)))
        (it "exposes docstring"
          #(let [c (atlas.client schema {:http-fn mock-http})]
             (assert.is_not_nil (. c.get-pet-by-id :fnl/docstring))))))

    (describe "url building"
      #(do
        (it "resolves path params"
          #(let [c (atlas.client schema {:http-fn mock-http})]
             (c.get-pet-by-id 42)
             (assert.equal "https://api.example.com/pets/42"
                           (. calls 1 :url))))
        (it "uses base-url override over schema server"
          #(let [c (atlas.client schema {:http-fn mock-http
                                         :base-url "https://staging.example.com"})]
             (c.list-pets)
             (assert.truthy (string.match (. calls 1 :url) "^https://staging.example.com"))))
        (it "passes query params"
          #(let [c (atlas.client schema {:http-fn mock-http})]
             (c.list-pets {:query {:status "available"}})
             (assert.same {:status "available"} (. calls 1 :query))))))

    (describe "request body"
      #(do
        (it "sends body for operations with requestBody"
          #(let [c (atlas.client schema {:http-fn mock-http})]
             (c.create-pet {:name "Rex"})
             (assert.same {:name "Rex"} (. calls 1 :body))))
        (it "sends nil body for GET operations"
          #(let [c (atlas.client schema {:http-fn mock-http})]
             (c.get-pet-by-id 1)
             (assert.is_nil (. calls 1 :body))))
        (it "sets content-type from requestBody schema"
          #(let [c (atlas.client schema {:http-fn mock-http})]
             (c.create-pet {:name "Rex"})
             (assert.equal "application/json"
                           (. calls 1 :headers :content-type))))))

    (describe "headers"
      #(do
        (it "sends client default headers"
          #(let [c (atlas.client schema {:http-fn mock-http
                                         :headers {:authorization "Bearer tok"}})]
             (c.list-pets)
             (assert.equal "Bearer tok" (. calls 1 :headers :authorization))))
        (it "merges per-request headers over client defaults"
          #(let [c (atlas.client schema {:http-fn mock-http
                                         :headers {:x-client "anis"}})]
             (c.list-pets {:headers {:x-request-id "abc"}})
             (assert.equal "anis" (. calls 1 :headers :x-client))
             (assert.equal "abc" (. calls 1 :headers :x-request-id))))
        (it "per-request header overrides client default"
          #(let [c (atlas.client schema {:http-fn mock-http
                                         :headers {:x-foo "default"}})]
             (c.list-pets {:headers {:x-foo "override"}})
             (assert.equal "override" (. calls 1 :headers :x-foo))))
        (it "sets accept from response content types"
          #(let [c (atlas.client schema {:http-fn mock-http})]
             (c.list-pets)
             (assert.equal "application/json" (. calls 1 :headers :accept))))))

    (describe "timeout"
      #(do
        (it "uses client timeout"
          #(let [c (atlas.client schema {:http-fn mock-http :timeout 30})]
             (c.list-pets)
             (assert.equal 30 (. calls 1 :timeout))))
        (it "per-request timeout overrides client timeout"
          #(let [c (atlas.client schema {:http-fn mock-http :timeout 30})]
             (c.list-pets {:timeout 5})
             (assert.equal 5 (. calls 1 :timeout))))
        (it "no timeout when unset"
          #(let [c (atlas.client schema {:http-fn mock-http})]
             (c.list-pets)
             (assert.is_nil (. calls 1 :timeout))))))))
