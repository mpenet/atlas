(local {: pretty} (require :atlas.pretty))
(fn p [v] (pretty v 0 false))

(describe "pretty"
  (fn []
    (it "renders string with quotes"
      (fn [] (assert.are.equal "\"hello\"" (p "hello"))))
    (it "renders number"
      (fn [] (assert.are.equal "42" (p 42))))
    (it "renders float"
      (fn [] (assert.are.equal "3.14" (p 3.14))))
    (it "renders true"
      (fn [] (assert.are.equal "true" (p true))))
    (it "renders false"
      (fn [] (assert.are.equal "false" (p false))))
    (it "renders nil as null"
      (fn [] (assert.are.equal "null" (p nil))))
    (it "renders empty table as {}"
      (fn [] (assert.are.equal "{}" (p {}))))
    (it "renders array with brackets"
      (fn []
        (let [result (p [1 2 3])]
          (assert.is_truthy (result:find "%["))
          (assert.is_truthy (result:find "%]"))
          (assert.is_truthy (result:find "1"))
          (assert.is_truthy (result:find "2"))
          (assert.is_truthy (result:find "3")))))
    (it "renders object with braces and quoted keys"
      (fn []
        (let [result (p {:foo "bar"})]
          (assert.is_truthy (result:find "{" 1 true))
          (assert.is_truthy (result:find "}" 1 true))
          (assert.is_truthy (result:find "\"foo\""))
          (assert.is_truthy (result:find "\"bar\"")))))
    (it "nested object renders correctly"
      (fn []
        (let [result (p {:a {:b 1}})]
          (assert.is_truthy (result:find "\"a\""))
          (assert.is_truthy (result:find "\"b\""))
          (assert.is_truthy (result:find "1")))))
    (it "no-color produces no escape codes"
      (fn []
        (let [result (p {:x 1})]
          (assert.is_nil (result:find "\27")))))))
