;; ABOUTME: Specs for validating request values against JSON Schema subsets.
;; ABOUTME: Run with `make test` (busted, Fennel loader).
(local validate (require :atlas.validate))

(fn errors [schema value]
  (validate.check schema value "body"))

(describe "validate.check"
          (fn []
            (it "accepts valid values"
                (fn []
                  (assert.are.same []
                                   (errors {:type "object"
                                            :required ["name"]
                                            :properties {:name {:type "string"}
                                                         :size {:type "integer"}}}
                                           {:name "Rex" :size 3}))))
            (it "reports missing required properties with their path"
                (fn []
                  (assert.are.same ["body.instance-type.id: required"]
                                   (errors {:type "object"
                                            :properties {:instance-type {:type "object"
                                                                         :required ["id"]
                                                                         :properties {:id {:type "string"}}}}}
                                           {:instance-type {}}))))
            (it "reports type mismatches"
                (fn []
                  (assert.are.same ["body.size: expected integer, got string"
                                    "body.tags: expected array, got string"]
                                   (errors {:type "object"
                                            :properties {:size {:type "integer"}
                                                         :tags {:type "array"}}}
                                           {:size "3" :tags "x"}))))
            (it "accepts integral floats as integers and integers as numbers"
                (fn []
                  (assert.are.same [] (errors {:type "integer"} 3.0))
                  (assert.are.same [] (errors {:type "number"} 3))
                  (assert.are.same ["body: expected integer, got number"]
                                   (errors {:type "integer"} 3.5))))
            (it "reports enum violations"
                (fn []
                  (assert.are.same ["body.tier: \"gold\" is not one of small, large"]
                                   (errors {:properties {:tier {:enum ["small"
                                                                       "large"]}}}
                                           {:tier "gold"}))))
            (it "validates array items with 0-based indexed paths"
                (fn []
                  (assert.are.same ["body[1].size: required"]
                                   (errors {:type "array"
                                            :items {:type "object"
                                                    :required ["size"]
                                                    :properties {:size {:type "integer"}}}}
                                           [{:size 1} {}]))))
            (it "rejects extra properties only when additionalProperties is false"
                (fn []
                  (assert.are.same ["body.extra: not allowed"]
                                   (errors {:type "object"
                                            :properties {:a {}}
                                            :additionalProperties false}
                                           {:a 1 :extra 2}))
                  (assert.are.same []
                                   (errors {:type "object" :properties {:a {}}}
                                           {:a 1 :extra 2}))))
            (it "checks length, range and item-count bounds"
                (fn []
                  (assert.are.same ["body.l: more than 2 items"
                                    "body.m: greater than 9"
                                    "body.n: less than 1"
                                    "body.name: shorter than 3 characters"]
                                   (errors {:properties {:name {:minLength 3}
                                                         :n {:minimum 1}
                                                         :m {:maximum 9}
                                                         :l {:maxItems 2}}}
                                           {:name "ab" :n 0 :m 10 :l [1 2 3]}))))
            (it "accepts any branch of anyOf/oneOf and requires every allOf branch"
                (fn []
                  (assert.are.same []
                                   (errors {:oneOf [{:type "string"}
                                                    {:type "integer"}]}
                                           3))
                  (assert.are.same ["body: does not match any of the allowed schemas"]
                                   (errors {:anyOf [{:type "string"}
                                                    {:type "integer"}]}
                                           true))
                  (assert.are.same ["body.b: required"]
                                   (errors {:allOf [{:required ["a"]}
                                                    {:required ["b"]}]}
                                           {:a 1}))))
            (it "supports OpenAPI 3.1 type lists"
                (fn []
                  (assert.are.same [] (errors {:type ["string" "integer"]} 3))))
            (it "accepts anything for an empty schema"
                (fn []
                  (assert.are.same [] (errors {} {:anything [1 2]}))))))

(describe "validate edge cases"
          (fn []
            (it "treats validate.null as a present null"
                (fn []
                  (let [schema {:type "object"
                                :required ["a"]
                                :properties {:a {:type "string" :nullable true}}}]
                    (assert.are.same [] (errors schema {:a validate.null}))
                    (assert.are.same ["body.a: expected string, got null"]
                                     (errors {:properties {:a {:type "string"}}}
                                             {:a validate.null})))))
            (it "does not crash on invalid UTF-8"
                (fn []
                  (assert.are.same []
                                   (errors {:type "string" :minLength 1} "\255"))))))

(describe "validate with odd schemas"
          (fn []
            (it "ignores bounds that are not numbers"
                (fn []
                  (assert.are.same []
                                   (errors {:type "integer"
                                            :maximum "18446744073709551615"
                                            :minLength "x"}
                                           5))))))

(describe "recursive schemas"
          (fn []
            (local refs (require :atlas.refs))

            (fn resolved [schemas name]
              ((refs.resolver {:components {: schemas}}) {:$ref (.. "#/components/schemas/"
                                                                    name)}))

            (it "validates nested data all the way down"
                (fn []
                  (let [node (resolved {:Node {:type "object"
                                               :properties {:name {:type "string"}
                                                            :next {:$ref "#/components/schemas/Node"}}}}
                                       :Node)]
                    (assert.are.same ["value.next.next.name: expected string, got integer"]
                                     (validate.check node
                                                     {:name "a"
                                                      :next {:name "b"
                                                             :next {:name 3}}})))))
            (it "terminates on schemas composed of themselves"
                (fn []
                  (let [a (resolved {:A {:allOf [{:$ref "#/components/schemas/B"}]
                                         :anyOf [{:$ref "#/components/schemas/A"}]}
                                     :B {:allOf [{:$ref "#/components/schemas/A"}]
                                         :type "object"}}
                                    :A)]
                    (assert.are.same [] (validate.check a {}))
                    (assert.are.same ["value: expected object, got string"]
                                     (validate.check a "x")))))))

(describe "schema forms from OpenAPI 3.0 and 3.1"
          (fn []
            (local json (require :atlas.json))
            (it "applies nullable only together with type"
                (fn []
                  (assert.are.same []
                                   (validate.check {:nullable true
                                                    :allOf [{:type "object"}]}
                                                   {:x 1}))
                  (assert.are.same []
                                   (validate.check {:type "string"
                                                    :nullable true}
                                                   validate.null))))
            (it "accepts boolean schemas: true allows anything, false nothing"
                (fn []
                  (assert.are.same []
                                   (validate.check {:type "object"
                                                    :properties {:x true}}
                                                   {:x 1}))
                  (assert.are.same ["value.x: not allowed"]
                                   (validate.check {:type "object"
                                                    :properties {:x false}}
                                                   {:x 1}))))
            (it "tells an empty array from an empty object"
                (fn []
                  (assert.are.same ["value: expected object, got array"]
                                   (validate.check {:type "object"}
                                                   (json.array [])))
                  (assert.are.same [] (validate.check {:type "object"} {}))))))
