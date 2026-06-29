(local util (require :atlas.util))

(describe "camel->kebab"
  (fn []
    (it "simple camelCase"
      (fn [] (assert.are.equal "get-pet" (util.camel->kebab "getPet"))))
    (it "multi-word"
      (fn [] (assert.are.equal "get-pet-by-id" (util.camel->kebab "getPetById"))))
    (it "consecutive caps"
      (fn [] (assert.are.equal "get-api-key" (util.camel->kebab "getAPIKey"))))
    (it "all lowercase passthrough"
      (fn [] (assert.are.equal "listpets" (util.camel->kebab "listpets"))))))

(describe "extract-path-params"
  (fn []
    (it "extracts single param"
      (fn [] (assert.are.same ["petId"] (util.extract-path-params "/pet/{petId}"))))
    (it "extracts multiple params"
      (fn []
        (assert.are.same ["userId" "postId"]
          (util.extract-path-params "/users/{userId}/posts/{postId}"))))
    (it "returns empty for no params"
      (fn [] (assert.are.same [] (util.extract-path-params "/pets"))))))

(describe "resolve-path"
  (fn []
    (it "substitutes a single param"
      (fn []
        (let [result (util.resolve-path "/pet/{petId}" [42])]
          (assert.are.equal "/pet/42" result))))
    (it "substitutes multiple params"
      (fn []
        (let [result (util.resolve-path "/users/{userId}/posts/{postId}" [1 99])]
          (assert.are.equal "/users/1/posts/99" result))))
    (it "coerces numbers to strings"
      (fn []
        (let [result (util.resolve-path "/items/{id}" [7])]
          (assert.are.equal "/items/7" result))))
    (it "errors on missing param"
      (fn []
        (assert.has.error (fn [] (util.resolve-path "/pet/{petId}" [])))
        (assert.has.error (fn [] (util.resolve-path "/a/{x}/b/{y}" [1])))))))
