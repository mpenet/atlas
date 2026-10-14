;; ABOUTME: Specs for operation help rendering.
;; ABOUTME: Run with `make test` (busted, Fennel loader).
(local {: build} (require :atlas.doc))

(local simple-op
       {:operationId "getPetById"
        :summary "Find pet by ID"
        :parameters [{:name "petId"
                      :in "path"
                      :required true
                      :schema {:type "integer"}
                      :description "ID of pet to return"}]
        :responses {"200" {:description "successful operation"}
                    "404" {:description "Pet not found"}}})

(local body-op {:operationId "addPet"
                :summary "Add a new pet"
                :requestBody {:required true
                              :content {:application/json {:schema {:type "object"
                                                                    :required ["name"]
                                                                    :properties {:name {:type "string"
                                                                                        :description "pet name"}
                                                                                 :status {:type "string"}}}}}}
                :responses {"200" {:description "ok"}}})

(describe "doc.build"
          (fn []
            (it "includes method and path"
                (fn []
                  (let [result (build "/pet/{petId}" :get simple-op)]
                    (assert.is_truthy (result:find "GET /pet/{petId}" 1 true)))))
            (it "includes summary"
                (fn []
                  (let [result (build "/pet/{petId}" :get simple-op)]
                    (assert.is_truthy (result:find "Find pet by ID" 1 true)))))
            (it "includes kebab-case usage line"
                (fn []
                  (let [result (build "/pet/{petId}" :get simple-op)]
                    (assert.is_truthy (result:find "get-pet-by-id" 1 true)))))
            (it "includes path params section"
                (fn []
                  (let [result (build "/pet/{petId}" :get simple-op)]
                    (assert.is_truthy (result:find "Path params" 1 true))
                    (assert.is_truthy (result:find "petId" 1 true))
                    (assert.is_truthy (result:find "integer" 1 true)))))
            (it "includes response codes"
                (fn []
                  (let [result (build "/pet/{petId}" :get simple-op)]
                    (assert.is_truthy (result:find "200" 1 true))
                    (assert.is_truthy (result:find "404" 1 true)))))
            (it "includes body section for requestBody ops"
                (fn []
                  (let [result (build "/pet" :post body-op)]
                    (assert.is_truthy (result:find "Body" 1 true))
                    (assert.is_truthy (result:find "name" 1 true)))))
            (it "marks body as required/optional"
                (fn []
                  (let [result (build "/pet" :post body-op)]
                    (assert.is_truthy (result:find "required" 1 true)))))
            (it "no-body op has no Body section"
                (fn []
                  (let [result (build "/pet/{petId}" :get simple-op)]
                    (assert.is_nil (result:find "^Body" 1 true)))))
            (it "leads usage with invoke, positional shorthand second"
                (fn []
                  (let [result (build "/pet/{petId}" :get simple-op)]
                    (assert.is_truthy (result:find "Usage: (get-pet-by-id.invoke {:path {:petId …}})\n       (get-pet-by-id petId)"
                                                   1 true)))))
            (it "shows body and query in the invoke form"
                (fn []
                  (let [op {:operationId "updatePet"
                            :parameters [{:name "ownerId" :in "path"}
                                         {:name "petId" :in "path"}
                                         {:name "dry" :in "query"}]
                            :requestBody {:content {:application/json {}}}
                            :responses {}}
                        result (build "/owners/{ownerId}/pets/{petId}" :put op)]
                    (assert.is_truthy (result:find "Usage: (update-pet.invoke {:path {:ownerId … :petId …} :body … :query {…}})\n       (update-pet ownerId petId body ?opts)"
                                                   1 true)))))
            (it "omits the map for operations without inputs"
                (fn []
                  (let [result (build "/pets" :get
                                      {:operationId "listPets" :responses {}})]
                    (assert.is_truthy (result:find "Usage: (list-pets.invoke)\n       (list-pets)"
                                                   1 true))))
                (it "lists template path params even when undeclared, in template order"
                    (fn []
                      (let [op {:operationId "getOwnerPet"
                                :parameters [{:name "petId"
                                              :in "path"
                                              :description "the pet"}]
                                :responses {}}
                            result (build "/owners/{ownerId}/pets/{petId}" :get
                                          op)]
                        (assert.is_truthy (result:find "(get-owner-pet ownerId petId)"
                                                       1 true))
                        (assert.is_truthy (result:find "the pet" 1 true))))))))

(local {: build-workflow} (require :atlas.doc))

(local workflow
       {:workflowId "createAndWait"
        :summary "Create a resource and wait until ready"
        :description "Polls until the operation finishes."
        :steps [{:stepId "create" :operationId "createResource"}
                {:stepId "poll"
                 :operationPath "{$sourceDescriptions.api.url}#/paths/~1ops~1{id}/get"}
                {:stepId "notify" :workflowId "sendNotice"}]})

(local inputs {:type "object"
               :required ["id" "name"]
               :properties {:id {:type "string" :description "resource id"}
                            :name {:type "string"}
                            :size {:type "integer" :default 0}
                            :dry {:type "boolean"
                                  :enum [true false]
                                  :default false}}})

(describe "doc.build-workflow"
          (fn []
            (let [text (build-workflow workflow inputs ["id"])]
              (it "starts with id and summary"
                  (fn []
                    (assert.is_truthy (text:find "^createAndWait\n\nCreate a resource and wait until ready\nPolls until the operation finishes%.\n"))))
              (it "shows usage with positional inputs"
                  (fn []
                    (assert.is_truthy (text:find "Usage: atlas az <name-or-file> createAndWait <id> [-i KEY=VAL ...]"
                                                 1 true))))
              (it "lists inputs sorted, required first, with details"
                  (fn []
                    (assert.is_truthy (text:find "Inputs:\n  id               string [required] — resource id\n  name             string [required]\n  dry              boolean [true|false] (default: false)\n  size             integer (default: 0)\n"
                                                 1 true))))
              (it "lists steps with what they call"
                  (fn []
                    (assert.is_truthy (text:find "Steps:\n  1. create   createResource\n  2. poll     GET /ops/{id}\n  3. notify   workflow sendNotice"
                                                 1 true)))))
            (it "says when a workflow takes no inputs"
                (fn []
                  (assert.is_truthy (: (build-workflow {:workflowId "w"
                                                        :steps []}
                                                       nil [])
                                       :find "Inputs: none" 1 true))))))
