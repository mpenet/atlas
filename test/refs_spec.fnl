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
            (it "keeps recursive schemas as cycles"
                (fn []
                  (let [root {:components {:schemas {:Node {:properties {:next {:$ref "#/components/schemas/Node"}}}}}}
                        node (deref root {:$ref "#/components/schemas/Node"})]
                    (assert.are.equal node node.properties.next))))
            (it "keeps mutually recursive schemas as cycles"
                (fn []
                  (let [root {:components {:schemas {:A {:properties {:b {:$ref "#/components/schemas/B"}}}
                                                     :B {:properties {:a {:$ref "#/components/schemas/A"}}}}}}
                        a (deref root {:$ref "#/components/schemas/A"})]
                    (assert.are.equal a a.properties.b.properties.a))))
            (it "resolves a ref to a ref to the same schema"
                (fn []
                  (let [root {:components {:schemas {:Alias {:$ref "#/components/schemas/Pet"}
                                                     :Pet {:properties {:self {:$ref "#/components/schemas/Alias"}}}}}}
                        v (deref root
                                 {:alias {:$ref "#/components/schemas/Alias"}
                                  :pet {:$ref "#/components/schemas/Pet"}})]
                    (assert.are.equal v.pet v.alias)
                    (assert.are.equal v.pet v.pet.properties.self))))
            (it "rejects refs that only point at each other"
                (fn []
                  (let [root {:components {:schemas {:A {:$ref "#/components/schemas/B"}
                                                     :B {:$ref "#/components/schemas/A"}}}}
                        (ok err) (pcall deref root
                                        {:$ref "#/components/schemas/A"})]
                    (assert.is_false ok)
                    (assert.is_truthy (: (tostring err) :find "circular $ref" 1
                                         true)))))
            (it "expands each reference once and shares the result"
                (fn []
                  (let [root {:components {:schemas {:Meta {:properties {:name {:type "string"}}}}}}
                        meta {:$ref "#/components/schemas/Meta"}
                        v (deref root {:a meta :b meta})]
                    (assert.are.same {:properties {:name {:type "string"}}} v.a)
                    (assert.are.equal v.a v.b))))
            (it "resolves schemas that reach a shared schema along many paths"
                (fn []
                  ;; S1 refers to S2 twice, S2 to S3 twice...: copying every
                  ;; path would take 2^40 steps
                  (let [schemas {:S41 {:type "string"}}
                        _ (for [i 1 40]
                            (let [next {:$ref (.. "#/components/schemas/S"
                                                  (+ i 1))}]
                              (tset schemas (.. "S" i)
                                    {:properties {:l next :r next}})))
                        v (deref {:components {: schemas}}
                                 {:$ref "#/components/schemas/S1"})]
                    (var node v)
                    (for [_ 1 40]
                      (set node node.properties.r))
                    (assert.are.same {:type "string"} node))))
            (it "shares recursive schemas between their uses"
                (fn []
                  (let [root {:components {:schemas {:Node {:properties {:next {:$ref "#/components/schemas/Node"}
                                                                         :meta {:$ref "#/components/schemas/Meta"}}}
                                                     :Meta {:type "object"}}}}
                        v (deref root
                                 {:x {:$ref "#/components/schemas/Node"}
                                  :y {:$ref "#/components/schemas/Node"}})]
                    (assert.are.equal v.x v.y)
                    (assert.are.equal v.x v.x.properties.next)
                    (assert.are.same {:type "object"} v.y.properties.meta))))
            (it "copies values that are already cyclic"
                (fn []
                  (let [node {:type "object"}]
                    (tset node :properties {:next node})
                    (let [v (deref {} {:schema node})]
                      (assert.are.equal v.schema v.schema.properties.next)))))
            (it "keeps credentials of a document's URL out of errors"
                (fn []
                  (let [(ok err) (pcall deref {} {:$ref "ext.json#/Nope"}
                                        {:base "http://user:SECRETPW@h/spec.json"
                                         :load (fn [_] {})})]
                    (assert.is_false ok)
                    (assert.is_nil (: (tostring err) :find "SECRETPW" 1 true)))))
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
