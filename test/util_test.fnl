(local util (require :atlas.util))

(describe "camel->kebab"
  #(do
    (it "simple camel case"
      #(assert.equal "get-pet-by-id" (util.camel->kebab "getPetById")))
    (it "consecutive uppercase"
      #(assert.equal "find-pets-by-status" (util.camel->kebab "findPetsByStatus")))
    (it "leading uppercase run"
      #(assert.equal "http-request" (util.camel->kebab "HTTPRequest")))
    (it "uppercase acronym before word"
      #(assert.equal "get-https-url" (util.camel->kebab "getHTTPSUrl")))
    (it "already lowercase passthrough"
      #(assert.equal "foo" (util.camel->kebab "foo")))))

(describe "extract-path-params"
  #(do
    (it "single param"
      #(assert.same ["petId"] (util.extract-path-params "/pet/{petId}")))
    (it "multiple params"
      #(assert.same ["username" "orderId"]
                    (util.extract-path-params "/user/{username}/orders/{orderId}")))
    (it "no params"
      #(assert.same [] (util.extract-path-params "/pets")))
    (it "root path"
      #(assert.same [] (util.extract-path-params "/")))))

(describe "resolve-path"
  #(do
    (it "substitutes single param"
      #(assert.equal "/pet/42" (util.resolve-path "/pet/{petId}" [42])))
    (it "substitutes multiple params in order"
      #(assert.equal "/user/bob/orders/7"
                     (util.resolve-path "/user/{username}/orders/{orderId}" ["bob" 7])))
    (it "coerces numbers to strings"
      #(assert.equal "/pet/99" (util.resolve-path "/pet/{petId}" [99])))))
