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
            (it "names operations without operationId after method and path"
                (fn []
                  (let [(http calls) (mock-http)
                        c (atlas.client (schema {"/pets/{petId}/toys" {:get {:responses {}}}
                                                 "/" {:post {:responses {}}}
                                                 "/listPets" {:get {:responses {}}}
                                                 "/other" {:get {:operationId "getListPets"
                                                                 :responses {}}}})
                                        {:http-fn http})]
                    (assert.are.equal "/pets/{petId}/toys"
                                      c.get-pets-pet-id-toys.path)
                    (assert.is_nil c.get-pets-pet-id-toys.operation-id)
                    (assert.are.equal "get-pets-pet-id-toys"
                                      c.get-pets-pet-id-toys.name)
                    (assert.are.equal "/" c.post.path)
                    ;; operationIds win over derived names
                    (assert.are.equal "/other" c.get-list-pets.path))))
            (it "gives operationIds that normalise alike distinct names, the same way every time"
                (fn []
                  (for [_ 1 5]
                    (let [c (atlas.client (schema {"/a" {:get {:operationId "getPet"
                                                               :responses {}}}
                                                   "/b" {:get {:operationId "get_pet"
                                                               :responses {}}}
                                                   "/c" {:get {:operationId "get-pet"
                                                               :responses {}}}})
                                          {:http-fn (mock-http)})]
                      ;; the first by path keeps the name, the others fall
                      ;; back to their method and path
                      (assert.are.equal "/a" c.get-pet.path)
                      (assert.are.equal "/b" c.get-b.path)
                      (assert.are.equal "/c" c.get-c.path)))))
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
                                     c.get-owner-pet.path-params)
                    (assert.is_false c.get-owner-pet.has-body)
                    (assert.is_true c.add-pet.has-body)
                    (assert.is_nil c.get-owner-pet.n-path))))
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
                        help (. c.get-pet :fnl/docstring)]
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
                                       (. seen 1))))))
            (it "passes ssl and headers to a custom loader as an opts table"
                (fn []
                  (let [seen []]
                    (atlas.client "https://h/openapi.json"
                                  {:ssl {:cafile "ca.pem"}
                                   :headers {:authorization "t"}
                                   :load-schema (fn [location opts]
                                                  (table.insert seen
                                                                [location opts])
                                                  (schema {}))})
                    (assert.are.same [["https://h/openapi.json"
                                       {:ssl {:cafile "ca.pem"}
                                        :headers {:authorization "t"}}]]
                                     seen))))))

(describe "query parameter styles"
          (fn []
            (it "follow each parameter's style and explode"
                (fn []
                  (let [(http calls) (mock-http)
                        c (atlas.client (schema {"/p" {:get {:operationId "p"
                                                             :parameters [{:name "tags"
                                                                           :in "query"
                                                                           :explode false}
                                                                          {:name "filter"
                                                                           :in "query"
                                                                           :style "deepObject"}]
                                                             :responses {}}}})
                                        {:http-fn http})]
                    (assert.are.equal "https://api.example.com/p?filter[a]=1&tags=x,y"
                                      (c.p.url-for {:query {:tags ["x" "y"]
                                                            :filter {:a 1}}}))
                    (c.p.invoke {:query {:tags ["x" "y"] :filter {:a 1}}})
                    (let [http-mod (require :atlas.http)
                          (url) (http-mod.encode-request (. calls 1))]
                      (assert.are.equal "https://api.example.com/p?filter[a]=1&tags=x,y"
                                        url)))))))

(describe "bodyless calls"
          (fn []
            (it "send no Content-Type"
                (fn []
                  (let [(http calls) (mock-http)
                        c (atlas.client (schema {"/p" {:post {:operationId "p"
                                                              :requestBody {:content {"application/json" {:schema {:type "object"}}}}
                                                              :responses {}}}})
                                        {:http-fn http})]
                    (c.p.invoke {})
                    (assert.is_nil (. calls 1 :headers :content-type))
                    (c.p.invoke {:body {:a 1}})
                    (assert.are.equal "application/json"
                                      (. calls 2 :headers :content-type)))))))

(describe "referenced path items"
          (fn []
            (it "build operations whose schemas are recursive"
                (fn []
                  (let [doc (schema {"/a" {:$ref "#/components/pathItems/A"}})]
                    (set doc.components
                         {:pathItems {:A {:get {:operationId "getA"
                                                :responses {"200" {:description "ok"
                                                                   :content {"application/json" {:schema {:$ref "#/components/schemas/Node"}}}}}}}}
                          :schemas {:Node {:type "object"
                                           :properties {:next {:$ref "#/components/schemas/Node"}}}}})
                    (let [c (atlas.client doc {:http-fn (mock-http)})]
                      (assert.are.equal "/a" c.get-a.path)))))
            (it "share the tables of the schemas they refer to"
                (fn []
                  (let [body {:content {"application/json" {:schema {:$ref "#/components/schemas/Node"}}}}
                        doc (schema {"/a" {:$ref "#/components/pathItems/A"}
                                     "/b" {:post {:operationId "postB"
                                                  :requestBody body
                                                  :responses {}}}})]
                    (set doc.components
                         {:pathItems {:A {:post {:operationId "postA"
                                                 :requestBody body
                                                 :responses {}}}}
                          :schemas {:Node {:type "object"
                                           :properties {:next {:$ref "#/components/schemas/Node"}}}}})
                    (let [c (atlas.client doc {:http-fn (mock-http)})]
                      (assert.are.equal c.post-b.body-schema
                                        c.post-a.body-schema)
                      (assert.are.equal c.post-a.body-schema
                                        c.post-a.body-schema.properties.next)))))))

(describe "operations whose name was taken"
          (fn []
            (it "show their own name in their docstring"
                (fn []
                  (let [c (atlas.client (schema {"/a" {:get {:operationId "listPets"
                                                             :responses {}}}
                                                 "/b" {:get {:operationId "list_pets"
                                                             :responses {}}}})
                                        {:http-fn (mock-http)})]
                    (assert.is_truthy (: (. c.get-b :fnl/docstring) :find
                                         "(get-b.invoke" 1 true)))))))

(describe "servers of path items and operations"
          (fn []
            (let [doc (schema {"/upload" {:servers [{:url "https://{region}.uploads.example.com"
                                                     :variables {:region {:default "eu"}}}]
                                          :post {:operationId "upload"
                                                 :responses {}}}
                               "/files" {:get {:operationId "listFiles"
                                               :servers [{:url "/files-api"}]
                                               :responses {}}}
                               "/x" {:get {:operationId "getX" :responses {}}}})]
              (it "override the client's"
                  (fn []
                    (let [c (atlas.client doc {:http-fn (mock-http)})]
                      (assert.are.equal "https://eu.uploads.example.com/upload"
                                        (c.upload.url-for))
                      (assert.are.equal "https://api.example.com/files-api/files"
                                        (c.list-files.url-for))
                      (assert.are.equal "https://api.example.com/x"
                                        (c.get-x.url-for)))))
              (it "follow the server index and take their own variables"
                  (fn []
                    (let [doc {:openapi "3.0.0"
                               :info {}
                               :servers [{:url "https://api.example.com"}
                                         {:url "https://sandbox.example.com"}]
                               :paths {"/up" {:servers [{:url "https://upload.example.com"}
                                                        {:url "https://{region}.upload-sandbox.example.com"
                                                         :variables {:region {:default "us"}}}]
                                              :post {:operationId "up"
                                                     :responses {}}}
                                       "/x" {:get {:operationId "getX"
                                                   :responses {}}}}}
                          c (atlas.client doc
                                          {:http-fn (mock-http)
                                           :server-index 2
                                           :server-vars {:region "eu"}})]
                      (assert.are.equal "https://eu.upload-sandbox.example.com/up"
                                        (c.up.url-for))
                      (assert.are.equal "https://sandbox.example.com/x"
                                        (c.get-x.url-for))
                      (assert.has.error #(atlas.client doc
                                                       {:http-fn (mock-http)
                                                        :server-vars {:nope "x"}})))))
              (it "but not an explicit base-url"
                  (fn []
                    (let [c (atlas.client doc
                                          {:http-fn (mock-http)
                                           :base-url "http://localhost:8080"})]
                      (assert.are.equal "http://localhost:8080/upload"
                                        (c.upload.url-for))))))))

(describe "operationIds without ASCII letters or digits"
          (fn []
            (it "are named after their method and path"
                (fn []
                  (let [c (atlas.client (schema {"/a" {:get {:operationId "获取用户"
                                                             :responses {}}}})
                                        {:http-fn (mock-http)})]
                    (assert.is_nil (. c ""))
                    (assert.are.equal "/a" (. c :get-a :path)))))))

(describe "request bodies declared with a media type range"
          (fn []
            (it "are sent as JSON"
                (fn []
                  (let [(http calls) (mock-http)
                        c (atlas.client (schema {"/x" {:post {:operationId "postX"
                                                              :requestBody {:content {"*/*" {:schema {:type "object"}}}}
                                                              :responses {}}}})
                                        {:http-fn http})]
                    (c.post-x.invoke {:body {:a 1}})
                    (assert.are.equal "application/json"
                                      (. calls 1 :headers :content-type))
                    (assert.are.same {:type "object"} c.post-x.body-schema))))))

(describe "query parameters with content"
          (fn []
            (it "are sent as JSON text"
                (fn []
                  (let [c (atlas.client (schema {"/search" {:get {:operationId "search"
                                                                  :parameters [{:name "filter"
                                                                                :in "query"
                                                                                :content {"application/json" {:schema {:type "object"}}}}]
                                                                  :responses {}}}})
                                        {:http-fn (mock-http)})]
                    (assert.are.equal "https://api.example.com/search?filter=%7B%22owner%22%3A%22me%22%7D"
                                      (c.search.url-for {:query {:filter {:owner "me"}}})))))))

(describe "root-relative server URLs"
          (fn []
            (it "make a server index an error when the spec declares none"
                (fn []
                  (let [doc (schema {"/x" {:get {:operationId "getX"
                                                 :responses {}}}})]
                    (set doc.servers nil)
                    (let [(ok err) (pcall atlas.client doc
                                          {:server-index 2
                                           :source-url "https://api.example.com/openapi.json"
                                           :http-fn (mock-http)})]
                      (assert.is_false ok)
                      (assert.is_truthy (: (tostring err) :find
                                           "server index 2 out of range (schema has 0 servers)"
                                           1 true))))))
            (it "default to / when the spec declares no servers"
                (fn []
                  (each [_ servers (ipairs [:absent []])]
                    (let [doc (schema {"/items/{id}" {:get {:operationId "readItem"
                                                            :responses {}}}})]
                      (set doc.servers (when (not= servers :absent) servers))
                      (let [c (atlas.client doc
                                            {:source-url "http://localhost:8000/openapi.json"
                                             :http-fn (mock-http)})]
                        (assert.are.equal "http://localhost:8000/items/1"
                                          (c.read-item.url-for {:path {:id 1}})))))))
            (it "may name another host (//host/path)"
                (fn []
                  (let [c (atlas.client (schema {"/pets" {:get {:operationId "listPets"
                                                                :responses {}}}}
                                                "//api.example.com/v1")
                                        {:source-url "https://specs.example.com/openapi.json"
                                         :http-fn (mock-http)})]
                    (assert.are.equal "https://api.example.com/v1/pets"
                                      (c.list-pets.url-for)))))
            (it "need the spec's origin"
                (fn []
                  (let [(ok err) (pcall atlas.client
                                        (schema {"/a" {:get {:operationId "getA"
                                                             :responses {}}}}
                                                "/v1")
                                        {:source-url "/tmp/spec.yaml"
                                         :http-fn (mock-http)})]
                    (assert.is_false ok)
                    (assert.is_truthy (: (tostring err) :find "no base-url" 1
                                         true)))))))

(describe "specification extensions"
          (fn []
            (it "may hold any value in paths and responses"
                (fn []
                  (let [doc (schema {"/a" {:get {:operationId "getA"
                                                 :responses {"200" {:description "ok"
                                                                    :content {"application/json" {:schema {:type "object"}}}}
                                                             :x-count 5}}}})]
                    (set doc.paths.x-internal true)
                    (let [(http calls) (mock-http)
                          c (atlas.client doc {:http-fn http})]
                      (assert.are.equal "/a" c.get-a.path)
                      (assert.are.equal "application/json"
                                        (do
                                          (c.get-a.invoke)
                                          (. calls 1 :headers :accept)))
                      (assert.is_truthy (: (. c.get-a :fnl/docstring) :find
                                           "200" 1 true))
                      (assert.is_nil (: (. c.get-a :fnl/docstring) :find
                                        "x-count" 1 true))))))))

(describe "credentials for referenced documents"
          (fn []
            (it "go only to the spec's own origin"
                (fn []
                  (let [seen {}
                        docs {"https://api.test/openapi.json" (schema {"/a" {:get {:operationId "a"
                                                                                   :responses {"200" {:$ref "https://api.test/common.json#/ok"}
                                                                                               "404" {:$ref "https://other.test/common.json#/nf"}}}}})
                              "https://api.test/common.json" {:ok {:description "ok"}}
                              "https://other.test/common.json" {:nf {:description "nf"}}}]
                    (atlas.client "https://api.test/openapi.json"
                                  {:headers {:x-api-key "k"}
                                   :load-schema (fn [location opts]
                                                  (tset seen location opts)
                                                  (. docs location))})
                    (assert.are.same {:headers {:x-api-key "k"}}
                                     (. seen "https://api.test/openapi.json"))
                    (assert.are.same {:headers {:x-api-key "k"}}
                                     (. seen "https://api.test/common.json"))
                    (assert.are.same {:credentials false}
                                     (. seen "https://other.test/common.json")))))
            (it "get the client's timeout"
                (fn []
                  (let [seen {}
                        docs {"https://api.test/openapi.json" (schema {"/a" {:get {:operationId "a"
                                                                                   :responses {"200" {:$ref "https://api.test/common.json#/ok"}
                                                                                               "404" {:$ref "https://other.test/common.json#/nf"}}}}})
                              "https://api.test/common.json" {:ok {:description "ok"}}
                              "https://other.test/common.json" {:nf {:description "nf"}}}]
                    (atlas.client "https://api.test/openapi.json"
                                  {:timeout 5
                                   :load-schema (fn [location opts]
                                                  (tset seen location opts)
                                                  (. docs location))})
                    (each [_ opts (pairs seen)]
                      (assert.are.equal 5 opts.timeout)))))))

(describe "schema documents"
          (fn []
            (it "rejects null and arrays"
                (fn []
                  (each [_ text (ipairs ["null" "[1]"])]
                    (let [(ok err) (pcall atlas.parse-schema text "x.json")]
                      (assert.is_false ok)
                      (assert.is_truthy (: (tostring err) :find
                                           "is not an OpenAPI document" 1 true))))))
            (it "skip null parameter entries"
                (fn []
                  (let [json (require :atlas.json)
                        c (atlas.client (atlas.parse-schema "{\"openapi\":\"3.0.0\",\"info\":{},\"servers\":[{\"url\":\"https://h\"}],\"paths\":{\"/a\":{\"parameters\":[null],\"get\":{\"operationId\":\"getA\",\"parameters\":[null,{\"name\":\"q\",\"in\":\"query\"}],\"responses\":{}}}}}"
                                                            "x.json")
                                        {:http-fn (mock-http)})]
                    (assert.are.same ["q"]
                                     (icollect [_ p (ipairs c.get-a.parameters)]
                                       p.name)))))
            (it "rejects text that is not a mapping"
                (fn []
                  (let [path (os.tmpname)]
                    (with-open [f (io.open path :w)]
                      (f:write "<!doctype html><html></html>"))
                    (let [(ok err) (pcall atlas.load-schema path)]
                      (os.remove path)
                      (assert.is_false ok)
                      (assert.is_truthy (: (tostring err) :find
                                           (.. "'" path
                                               "' is not an OpenAPI document")
                                           1 true))))))))

(describe "operation help"
          (fn []
            (it "exposes the resolved spec and renders the docstring only when asked"
                (fn []
                  (let [doc (require :atlas.doc)
                        real-build doc.build
                        calls []]
                    (set doc.build
                         (fn [...] (table.insert calls 1) (real-build ...)))
                    (let [c (atlas.client pets-schema {:http-fn (mock-http)})]
                      (assert.are.equal 0 (length calls))
                      (assert.are.equal "addPet" c.add-pet.spec.operationId)
                      (assert.is_truthy (: (. c.add-pet :fnl/docstring) :find
                                           "POST /pets" 1 true))
                      (assert.are.equal 1 (length calls))
                      (assert.is_nil (. c.add-pet :cli/help)))
                    (set doc.build real-build))))))

(describe "base-url"
          (fn []
            (it "is the chosen server's URL with its variables"
                (fn []
                  (assert.are.equal "https://root.internal.test/api"
                                    (atlas.base-url multi-server-schema))
                  (assert.are.equal "https://pproot.service.test/api"
                                    (atlas.base-url multi-server-schema
                                                    {:server-index 2
                                                     :server-vars {:env "pp"}}))))
            (it "prefers :base-url"
                (fn []
                  (assert.are.equal "https://o.test"
                                    (atlas.base-url multi-server-schema
                                                    {:base-url "https://o.test"}))))
            (it "resolves a relative server against the spec's location"
                (fn []
                  (assert.are.equal "https://specs.test/v2"
                                    (atlas.base-url {:openapi "3.0.0"
                                                     :servers [{:url "/v2"}]}
                                                    {:source-url "https://specs.test/openapi.json"}))
                  (assert.are.equal "https://specs.test/"
                                    (atlas.base-url {:openapi "3.0.0"}
                                                    {:source-url "https://specs.test/openapi.json"}))))
            (it "takes the variables of other servers in use, as clients do"
                (fn []
                  (let [schema {:openapi "3.0.0"
                                :servers [{:url "https://h.test/{ver}"
                                           :variables {:ver {:default "v1"}}}]
                                :paths {"/echo" {:servers [{:url "https://{zone}.h.test"
                                                            :variables {:zone {:default "a"}}}]
                                                 :get {:operationId "echo"}}}}]
                    (assert.are.equal "https://h.test/v1"
                                      (atlas.base-url schema
                                                      {:server-vars {:zone "b"}}))
                    (assert.are.equal "https://b.h.test/echo"
                                      ((. (atlas.client schema
                                                        {:server-vars {:zone "b"}
                                                         :http-fn #nil})
                                          :echo :url-for))))))
            (it "takes the variables of servers in referenced path items"
                (fn []
                  (let [schema {:openapi "3.1.0"
                                :servers [{:url "https://h.test/{ver}"
                                           :variables {:ver {:default "v1"}}}]
                                :components {:pathItems {:echo {:servers [{:url "https://{zone}.h.test"
                                                                           :variables {:zone {:default "a"}}}]
                                                                :get {:operationId "echo"}}}}
                                :paths {"/echo" {"$ref" "#/components/pathItems/echo"}}}]
                    (assert.are.equal "https://h.test/v1"
                                      (atlas.base-url schema
                                                      {:server-vars {:zone "b"}})))))
            (it "rejects unknown server variables"
                (fn []
                  (let [(ok err) (pcall atlas.base-url multi-server-schema
                                        {:server-vars {:nope "x"}})]
                    (assert.is_false ok)
                    (assert.is_truthy (: (tostring err) :find
                                         "unknown server variable 'nope'" 1 true)))))))

(describe "querystring"
          (fn []
            (it "is sent as the whole query string"
                (fn []
                  (let [(http calls) (mock-http)
                        c (atlas.client (schema {"/items" {:get {:operationId "listItems"}}}
                                                "https://api.test")
                                        {:http-fn http})]
                    (c.list-items.invoke {:querystring "a=1&b=x%20y"})
                    (assert.are.equal "https://api.test/items?a=1&b=x%20y"
                                      (. calls 1 :url))
                    (assert.is_nil (. calls 1 :query))
                    (assert.are.equal "https://api.test/items?a=1&b=x%20y"
                                      (c.list-items.url-for {:querystring "a=1&b=x%20y"})))))))
