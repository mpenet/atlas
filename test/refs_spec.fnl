;; ABOUTME: Specs for resolving $refs: JSON-pointer escapes, cycles, errors,
;; ABOUTME: and references into other files. Run with `make test`.
(local refs (require :atlas.refs))

(fn deref [root value ?opts]
  ((refs.resolver root ?opts) value))

(describe "refs.resolver"
          (fn []
            (it "resolves local refs, recursively"
                (fn []
                  (let [root {:components {:schemas {:Pet {:properties {:owner {:$ref "#/components/schemas/Owner"}}}
                                                     :Owner {:type "string"}}}}]
                    (assert.are.same {:properties {:owner {:type "string"}}}
                                     (deref root
                                            {:$ref "#/components/schemas/Pet"})))))
            (it "decodes ~1 and ~0 escapes"
                (fn []
                  (let [root {:paths {"/pets" {:get {:operationId "x"}}}
                              :components {:schemas {"a/b~c" {:type "integer"}}}}]
                    (assert.are.same {:operationId "x"}
                                     (deref root {:$ref "#/paths/~1pets/get"}))
                    (assert.are.same {:type "integer"}
                                     (deref root
                                            {:$ref "#/components/schemas/a~1b~0c"})))))
            (it "decodes percent-escapes in the fragment"
                (fn []
                  (let [root {:paths {"/a/{id}" {:x 1}}}]
                    (assert.are.same {:x 1}
                                     (deref root
                                            {:$ref "#/paths/~1a~1%7Bid%7D"})))))
            (it "indexes arrays 0-based"
                (fn []
                  (assert.are.same {:a 1}
                                   (deref {:list [{:a 0} {:a 1}]}
                                          {:$ref "#/list/1"}))))
            (it "turns cycles into empty schemas instead of looping"
                (fn []
                  (let [root {:components {:schemas {:Node {:properties {:next {:$ref "#/components/schemas/Node"}}}}}}
                        node (deref root {:$ref "#/components/schemas/Node"})]
                    (assert.are.same {} node.properties.next))))
            (it "raises for refs that resolve to nothing"
                (fn []
                  (let [(ok err) (pcall deref {:components {}}
                                        {:$ref "#/components/schemas/Missing"})]
                    (assert.is_false ok)
                    (assert.is_truthy (: (tostring err) :find
                                         "unresolved $ref '#/components/schemas/Missing'"
                                         1 true)))))
            (it "loads refs into other documents relative to the base"
                (fn []
                  (let [loaded []
                        docs {"specs/common.yaml" {:Id {:type "string"}
                                                   :Pet {:properties {:id {:$ref "#/Id"}}}}}
                        root {:x {:$ref "common.yaml#/Pet"}}
                        opts {:base "specs/api.yaml"
                              :load (fn [loc] (table.insert loaded loc)
                                      (. docs loc))}]
                    (assert.are.same {:properties {:id {:type "string"}}}
                                     (deref root root.x opts))
                    (assert.are.same ["specs/common.yaml"] loaded))))
            (it "loads each other document once"
                (fn []
                  (let [loaded []
                        resolve (refs.resolver {}
                                               {:base "a.yaml"
                                                :load (fn [loc]
                                                        (table.insert loaded
                                                                      loc)
                                                        {:A 1 :B 2})})]
                    (resolve {:$ref "b.yaml#/A"})
                    (resolve {:$ref "b.yaml#/B"})
                    (assert.are.same ["b.yaml"] loaded))))
            (it "explains when another document can't be located"
                (fn []
                  (let [(ok err) (pcall deref {} {:$ref "other.yaml#/X"})]
                    (assert.is_false ok)
                    (assert.is_truthy (: (tostring err) :find
                                         "cannot resolve $ref 'other.yaml#/X': the schema's location is unknown"
                                         1 true)))))))

(describe "refs edge cases"
          (fn []
            (it "keeps + literal in fragments"
                (fn []
                  (assert.are.same {:x 1}
                                   (deref {:c {"A+B" {:x 1}}} {:$ref "#/c/A+B"}))))
            (it "rejects fragments that are not JSON pointers"
                (fn []
                  (let [(ok err) (pcall deref {:Pet {}} {:$ref "#Pet"})]
                    (assert.is_false ok)
                    (assert.is_truthy (: (tostring err) :find
                                         "unsupported $ref '#Pet'" 1 true)))))
            (it "does not reload the root when another document refers back to it"
                (fn []
                  (let [loaded []
                        root {:Id {:type "string"}
                              :x {:$ref "other.yaml#/Pet"}}
                        docs {"other.yaml" {:Pet {:properties {:id {:$ref "api.yaml#/Id"}}}}}
                        resolve (refs.resolver root
                                               {:base "api.yaml"
                                                :load (fn [loc]
                                                        (table.insert loaded
                                                                      loc)
                                                        (. docs loc))})]
                    (assert.are.same {:properties {:id {:type "string"}}}
                                     (resolve root.x))
                    (assert.are.same ["other.yaml"] loaded))))))
