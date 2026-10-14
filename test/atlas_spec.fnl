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
            (it "exposes declared parameters, path-level ones merged"
                (fn []
                  (let [c (atlas.client (schema {"/p/{id}" {:parameters [{:name "id"
                                                                          :in "path"
                                                                          :required true}]
                                                            :get {:operationId "getP"
                                                                  :parameters [{:name "q"
                                                                                :in "query"
                                                                                :required true
                                                                                :schema {:type "string"}}]
                                                                  :responses {}}}})
                                        {:http-fn (mock-http)})]
                    (assert.are.same [{:name "id" :in "path" :required true}
                                      {:name "q"
                                       :in "query"
                                       :required true
                                       :schema {:type "string"}}]
                                     c.get-p.parameters))))
            (it "exposes the negotiated request content type"
                (fn []
                  (let [c (atlas.client pets-schema {:http-fn (mock-http)})]
                    (assert.are.equal "application/json" c.add-pet.content-type)
                    (assert.is_nil c.get-owner-pet.content-type))))
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

(local zoned-schema
       {:openapi "3.0.0"
        :info {}
        :servers [{:url "https://api-{zone}.example.com/{version}"
                   :variables {:zone {:default "ch-gva-2"
                                      :enum ["ch-gva-2" "de-fra-1"]}
                               :version {:default "v2"}}}]
        :paths {"/x" {:get {:operationId "getX" :responses {}}}}})

(describe "server variable overrides"
          (fn []
            (it "uses defaults when no override is given"
                (fn []
                  (let [(http calls) (mock-http)
                        c (atlas.client zoned-schema {:http-fn http})]
                    (c.get-x.invoke)
                    (assert.are.equal "https://api-ch-gva-2.example.com/v2/x"
                                      (. calls 1 :url)))))
            (it "substitutes overrides"
                (fn []
                  (let [(http calls) (mock-http)
                        c (atlas.client zoned-schema
                                        {:http-fn http
                                         :server-vars {:zone "de-fra-1"
                                                       :version "v3"}})]
                    (c.get-x.invoke)
                    (assert.are.equal "https://api-de-fra-1.example.com/v3/x"
                                      (. calls 1 :url)))))
            (it "rejects values outside the enum, listing allowed ones"
                (fn []
                  (let [(ok err) (pcall atlas.client zoned-schema
                                        {:http-fn (mock-http)
                                         :server-vars {:zone "mars-1"}})]
                    (assert.is_false ok)
                    (assert.is_truthy (: (tostring err) :find
                                         "server variable zone: 'mars-1' is not one of ch-gva-2, de-fra-1"
                                         1 true)))))
            (it "rejects unknown variables, listing known ones"
                (fn []
                  (let [(ok err) (pcall atlas.client zoned-schema
                                        {:http-fn (mock-http)
                                         :server-vars {:region "x"}})]
                    (assert.is_false ok)
                    (assert.is_truthy (: (tostring err) :find
                                         "unknown server variable 'region' (known: version, zone)"
                                         1 true)))))
            (it "is ignored when base-url is given"
                (fn []
                  (let [(http calls) (mock-http)
                        c (atlas.client zoned-schema
                                        {:http-fn http
                                         :base-url "https://b"
                                         :server-vars {:zone "de-fra-1"}})]
                    (c.get-x.invoke)
                    (assert.are.equal "https://b/x" (. calls 1 :url)))))))

(local multi-server-schema
       {:openapi "3.0.0"
        :info {}
        :servers [{:url "https://{env}root.internal.test/api"
                   :variables {:env {:default "" :enum ["" "pp"]}}}
                  {:url "https://{env}root.service.test/api"
                   :description "service network"
                   :variables {:env {:default "" :enum ["" "pp"]}}}
                  {:url "/api"}]
        :paths {"/x" {:get {:operationId "getX" :responses {}}}}})

(describe "server choice"
          (fn []
            (it "uses the first server by default"
                (fn []
                  (let [(http calls) (mock-http)
                        c (atlas.client multi-server-schema {:http-fn http})]
                    (c.get-x.invoke)
                    (assert.are.equal "https://root.internal.test/api/x"
                                      (. calls 1 :url)))))
            (it "selects a server by index, with its variables"
                (fn []
                  (let [(http calls) (mock-http)
                        c (atlas.client multi-server-schema
                                        {:http-fn http
                                         :server-index 2
                                         :server-vars {:env "pp"}})]
                    (c.get-x.invoke)
                    (assert.are.equal "https://pproot.service.test/api/x"
                                      (. calls 1 :url)))))
            (it "rejects an index out of range"
                (fn []
                  (let [(ok err) (pcall atlas.client multi-server-schema
                                        {:http-fn (mock-http) :server-index 4})]
                    (assert.is_false ok)
                    (assert.is_truthy (: (tostring err) :find
                                         "server index 4 out of range (schema has 3 servers)"
                                         1 true)))))
            (it "lists servers with their variables"
                (fn []
                  (let [servers (atlas.servers multi-server-schema)]
                    (assert.are.equal 3 (length servers))
                    (assert.are.equal "service network"
                                      (. servers 2 :description))
                    (assert.are.same {:default "" :enum ["" "pp"]}
                                     (. servers 1 :variables :env))
                    (assert.are.same {} (. servers 3 :variables)))))))

(describe "client $ref handling"
          (fn []
            (it "resolves path items defined by $ref"
                (fn []
                  (let [c (atlas.client {:openapi "3.1.0"
                                         :info {}
                                         :servers [{:url "https://h"}]
                                         :paths {"/a" {:$ref "#/components/pathItems/A"}}
                                         :components {:pathItems {:A {:get {:operationId "getA"
                                                                            :responses {}}}}}}
                                        {:http-fn (mock-http)})]
                    (assert.is_not_nil c.get-a))))
            (it "raises for refs that resolve to nothing"
                (fn []
                  (let [(ok err) (pcall atlas.client
                                        (schema {"/x" {:get {:operationId "getX"
                                                             :parameters [{:$ref "#/components/parameters/Nope"}]
                                                             :responses {}}}})
                                        {:http-fn (mock-http)})]
                    (assert.is_false ok)
                    (assert.is_truthy (: (tostring err) :find
                                         "unresolved $ref '#/components/parameters/Nope'"
                                         1 true)))))
            (it "follows refs into other files relative to the schema file"
                (fn []
                  (let [dir (os.tmpname)
                        write (fn [name text]
                                (let [f (io.open (.. dir "-" name) :w)]
                                  (f:write text)
                                  (f:close)))
                        common (.. (dir:match "[^/]+$") "-common.yaml")]
                    (write "common.yaml"
                           "Pet:\n  type: object\n  required: [name]\n  properties:\n    name: {type: string}\n")
                    (write "api.yaml"
                           (.. "openapi: 3.0.0\ninfo: {}\nservers: [{url: 'https://h'}]\npaths:\n  /pets:\n    post:\n      operationId: addPet\n      requestBody:\n        content:\n          application/json:\n            schema: {$ref: '"
                               common "#/Pet'}\n      responses: {}\n"))
                    (let [c (atlas.client (.. dir "-api.yaml")
                                          {:http-fn (mock-http)})]
                      (os.remove (.. dir "-common.yaml"))
                      (os.remove (.. dir "-api.yaml"))
                      (assert.are.same ["name"] c.add-pet.body-schema.required)))))))

(describe "URL joining and schema fetching"
          (fn []
            (it "joins a base URL with a trailing slash without doubling it"
                (fn []
                  (let [(http calls) (mock-http)
                        c (atlas.client (schema {"/pets/{id}" {:get {:operationId "getPet"
                                                                     :responses {}}}}
                                                "https://h/v1/")
                                        {:http-fn http})]
                    (c.get-pet.invoke {:path {:id 1}})
                    (assert.are.equal "https://h/v1/pets/1" (. calls 1 :url)))))
            (it "does the same for a --base-url override"
                (fn []
                  (let [(http calls) (mock-http)
                        c (atlas.client (schema {"/pets" {:get {:operationId "listPets"
                                                                :responses {}}}})
                                        {:http-fn http :base-url "https://x/"})]
                    (c.list-pets.invoke)
                    (assert.are.equal "https://x/pets" (. calls 1 :url)))))
            (it "fetches a schema URL with the client's ssl and headers"
                (fn []
                  (let [seen []
                        real-http (require :atlas.http)
                        fake (collect [k v (pairs real-http)] k v)]
                    (tset fake :fetch-text
                          (fn [location opts]
                            (table.insert seen opts)
                            "{\"openapi\":\"3.0.0\",\"info\":{},\"servers\":[{\"url\":\"https://h\"}],\"paths\":{}}"))
                    (tset package.loaded :atlas.http fake)
                    (tset package.loaded :atlas nil)
                    (let [fresh (require :atlas)]
                      (fresh.client "https://h/openapi.json"
                                    {:ssl {:cafile "ca.pem"}
                                     :headers {:authorization "t"}})
                      (tset package.loaded :atlas.http real-http)
                      (tset package.loaded :atlas nil)
                      (assert.are.same {:ssl {:cafile "ca.pem"}
                                        :headers {:authorization "t"}}
                                       (. seen 1))))))))
