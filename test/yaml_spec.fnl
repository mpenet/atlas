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

(describe "yaml.parse YAML 1.2 core schema"
          (fn []
            (local yaml (require :atlas.yaml))
            (it "keeps YAML 1.1 booleans and sexagesimals as strings"
                (fn []
                  (assert.are.same {:a "no"
                                    :b "on"
                                    :c "yes"
                                    :d "Off"
                                    :e "1:20"}
                                   (yaml.parse "a: no\nb: on\nc: yes\nd: Off\ne: 1:20\n"))))
            (it "resolves core booleans, numbers and nulls"
                (fn []
                  (let [v (yaml.parse "t: true\nf: False\ni: 42\nneg: -7\nhex: 0x1F\noct: 0o17\nfl: 1.5e3\ninf: .inf\nn: null\nt2: ~\n")]
                    (assert.are.equal true v.t)
                    (assert.are.equal false v.f)
                    (assert.are.equal 42 v.i)
                    (assert.are.equal -7 v.neg)
                    (assert.are.equal 31 v.hex)
                    (assert.are.equal 15 v.oct)
                    (assert.are.equal 1500 v.fl)
                    (assert.are.equal math.huge v.inf)
                    (assert.is_nil v.n)
                    (assert.is_nil v.t2))))
            (it "keeps quoted and !!str scalars as strings"
                (fn []
                  (assert.are.same {:a "true" :b "3" :c "007"}
                                   (yaml.parse "a: \"true\"\nb: !!str 3\nc: '007'\n"))))
            (it "keeps maps with numeric keys as maps"
                (fn []
                  (let [v (yaml.parse "m: {1: a, 2: b}\nr:\n  200: ok\n  404: missing\n")]
                    (assert.are.same {"1" "a" "2" "b"} v.m)
                    (assert.are.same {"200" "ok" "404" "missing"} v.r))))
            (it "keeps sequences as arrays"
                (fn []
                  (assert.are.same {:s ["a" "b"]} (yaml.parse "s: [a, b]\n"))))
            (it "resolves anchors, aliases and merge keys"
                (fn []
                  (let [v (yaml.parse "base: &b {x: 1, y: 2}\ncopy: *b\nmerged:\n  <<: *b\n  y: 3\n")]
                    (assert.are.same {:x 1 :y 2} v.copy)
                    (assert.are.same {:x 1 :y 3} v.merged))))
            (it "reports parse errors with a line number"
                (fn []
                  (let [(ok err) (pcall yaml.parse "a: [1, 2\nb: 3\n")]
                    (assert.is_false ok)
                    (assert.is_truthy (: (tostring err) :find
                                         "YAML parse error" 1 true))
                    (assert.is_truthy (: (tostring err) :find "line" 1 true)))))))

(describe "yaml.parse edge cases"
          (fn []
            (local yaml (require :atlas.yaml))
            (it "turns integers too large for Lua into floats"
                (fn []
                  (assert.are.equal 18446744073709551615.0
                                    (. (yaml.parse "m: 18446744073709551615\n")
                                       :m))))
            (it "keeps mapping keys as written"
                (fn []
                  (assert.are.same {"null" 1
                                    "~" 2
                                    ".inf" 3
                                    "1.10" 4
                                    "010" 5
                                    "0x1F" 6
                                    "true" 7}
                                   (yaml.parse "null: 1\n~: 2\n.inf: 3\n1.10: 4\n010: 5\n0x1F: 6\ntrue: 7\n"))))
            (it "rejects mappings and sequences used as keys"
                (fn []
                  (let [(ok err) (pcall yaml.parse "? [a, b]\n: 1\n")]
                    (assert.is_false ok)
                    (assert.is_truthy (: (tostring err) :find
                                         "keys must be scalars" 1 true)))))
            (it "resolves aliases of false and null"
                (fn []
                  (assert.are.same {:a false :b false}
                                   (yaml.parse "a: &f false\nb: *f\n"))
                  (assert.are.same {} (yaml.parse "a: &n null\nb: *n\n"))))))
