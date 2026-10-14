;; ABOUTME: Specs for YAML parsing and YAML-backed schema loading.
;; ABOUTME: Run with `make test` (busted, Fennel loader).
(local yaml (require :atlas.yaml))
(local atlas (require :atlas))

(describe "atlas.yaml"
          (fn []
            (it "parses YAML with numeric keys as strings"
                (fn []
                  (let [t (yaml.parse "responses:\n  200: {description: ok}\n  \"404\": {description: nope}\n")]
                    (assert.are.equal "ok" (?. t :responses "200" :description))
                    (assert.are.equal "nope"
                                      (?. t :responses "404" :description)))))
            (it "preserves arrays"
                (fn []
                  (let [t (yaml.parse "required: [id, name]\n")]
                    (assert.are.equal 2 (length t.required))
                    (assert.are.equal "id" (. t.required 1))
                    (assert.are.equal "name" (. t.required 2)))))
            (it "drops null map values"
                (fn []
                  (let [t (yaml.parse "a: 1\nb: null\n")]
                    (assert.are.equal 1 t.a)
                    (assert.is_nil t.b))))
            (it "keeps booleans and numbers"
                (fn []
                  (let [t (yaml.parse "flag: true\nnum: 1.5\n")]
                    (assert.is_true t.flag)
                    (assert.are.equal 1.5 t.num))))
            (it "decode falls back from JSON to YAML"
                (fn []
                  (let [j (yaml.decode "{\"a\":1}")
                        y (yaml.decode "a: 1\n")]
                    (assert.are.equal 1 j.a)
                    (assert.are.equal 1 y.a))))))

(describe "atlas.load-schema (YAML)"
          (fn []
            (it "loads a YAML OpenAPI fixture"
                (fn []
                  (let [s (atlas.load-schema "test/fixtures/petstore.yaml")]
                    (assert.are.equal "3.0.0" s.openapi)
                    (assert.is_not_nil (?. s :paths "/pets" :get))
                    (assert.are.equal "listPets"
                                      (?. s :paths "/pets" :get :operationId))
                    (assert.are.equal "ok"
                                      (?. s :paths "/pets" :get :responses
                                          "200" :description)))))
            (it "builds client from YAML schema"
                (fn []
                  (let [calls []
                        http (fn [req] (table.insert calls req)
                               {:status 200 :headers {} :body {}})
                        c (atlas.client "test/fixtures/petstore.yaml"
                                        {:http-fn http})]
                    (assert.is_not_nil c.list-pets)
                    (assert.is_not_nil c.get-pet-by-id)
                    (c.get-pet-by-id 7)
                    (assert.are.equal "https://api.example.com/pets/7"
                                      (. calls 1 :url)))))))
