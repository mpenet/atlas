;; ABOUTME: Specs for JSON and YAML terminal rendering.
;; ABOUTME: Run with `make test` (busted, Fennel loader).
(local {: pretty : yaml} (require :ezu.pretty))
(local json (require :lunajson))
(fn p [v] (pretty v 0 false))

(describe "pretty"
          (fn []
            (it "renders string with quotes"
                (fn [] (assert.are.equal "\"hello\"" (p "hello"))))
            (it "renders number" (fn [] (assert.are.equal "42" (p 42))))
            (it "renders float" (fn [] (assert.are.equal "3.14" (p 3.14))))
            (it "renders true" (fn [] (assert.are.equal "true" (p true))))
            (it "renders false" (fn [] (assert.are.equal "false" (p false))))
            (it "renders nil as null" (fn [] (assert.are.equal "null" (p nil))))
            (it "renders empty table as {}"
                (fn []
                  (assert.are.equal "{}" (p {}))))
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
                    (assert.is_nil (result:find "\27")))))
            (it "produces JSON that round-trips special characters"
                (fn []
                  (let [v {:s "line\nnext\ttab \"quote\" back\\slash \1 é"}]
                    (assert.are.same v (json.decode (p v))))))
            (it "escapes control characters as \\u sequences"
                (fn [] (assert.are.equal "\"\\u0001\"" (p "\1"))))
            (it "sorts object keys"
                (fn []
                  (assert.are.equal "{\n  \"a\": 1,\n  \"b\": 2\n}"
                                    (p {:b 2 :a 1}))))
            (it "renders non-finite numbers as null"
                (fn []
                  (assert.are.equal "null" (p (/ 1 0)))
                  (assert.are.equal "null" (p (/ 0 0)))))))

(describe "yaml"
          (fn []
            (it "sorts mapping keys"
                (fn []
                  (assert.are.equal "\nb: 1\nc: 2" (yaml {:c 2 :b 1} 0 false)))
                (it "quotes strings that YAML would read as other types"
                    (fn []
                      (let [ayaml (require :ezu.yaml)
                            v {:items ["yes"
                                       "No"
                                       "on"
                                       "OFF"
                                       "True"
                                       "NULL"
                                       "1e3"
                                       ".5"
                                       "-1"
                                       "0x1F"
                                       "a: b"
                                       "- x"
                                       "#c"
                                       "plain"]}]
                        (assert.are.same v (ayaml.parse (yaml v 0 false)))))))))

(describe "yaml keys"
          (fn []
            (it "quotes keys that would not read back as the same string"
                (fn []
                  (let [ayaml (require :ezu.yaml)
                        v {"a: b" 1
                           "#c" 2
                           "true" 3
                           "" 4
                           "- x" 5
                           "plain" 6
                           "007" 7}]
                    (assert.are.same v (ayaml.parse (yaml v 0 false))))))
            (it "quotes control characters and writes infinities as YAML does"
                (fn []
                  (let [ayaml (require :ezu.yaml)
                        v {:a "x\1y" :b math.huge :c (- math.huge)}]
                    (assert.are.same v (ayaml.parse (yaml v 0 false))))))
            (it "quotes a key that YAML would read as a merge"
                (fn []
                  (let [v {"<<" {:a 1} :b 2}]
                    (assert.are.same v
                                     ((. (require :ezu.yaml) :parse) (yaml v 0
                                                                           false))))))))
