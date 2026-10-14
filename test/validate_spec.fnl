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
