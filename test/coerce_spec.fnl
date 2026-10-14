;; ABOUTME: Specs for schema-guided conversion of command-line values.
;; ABOUTME: Run with `make test` (busted, Fennel loader).
(local coerce (require :atlas.coerce))

(describe "coerce.from-string with schema"
          (fn []
            (it "keeps strings for string schemas"
                (fn []
                  (assert.are.equal "007"
                                    (coerce.from-string "007" {:type "string"}))
                  (assert.are.equal "true"
                                    (coerce.from-string "true" {:type "string"}))))
            (it "parses integers"
                (fn []
                  (assert.are.equal (math.tointeger 42)
                                    (coerce.from-string "42" {:type "integer"}))))
            (it "parses numbers"
                (fn []
                  (assert.are.equal 1.5
                                    (coerce.from-string "1.5" {:type "number"}))))
            (it "parses booleans"
                (fn []
                  (assert.are.equal false
                                    (coerce.from-string "false"
                                                        {:type "boolean"}))))
            (it "parses JSON for arrays and objects"
                (fn []
                  (assert.are.same [1 2]
                                   (coerce.from-string "[1,2]" {:type "array"}))))
            (it "leaves unparseable values as strings"
                (fn []
                  (assert.are.equal "abc"
                                    (coerce.from-string "abc" {:type "integer"}))))))

(describe "coerce.from-string without schema"
          (fn []
            (it "parses strict JSON numbers"
                (fn []
                  (assert.are.equal (math.tointeger 42)
                                    (coerce.from-string "42"))
                  (assert.are.equal -1.5 (coerce.from-string "-1.5"))))
            (it "keeps leading-zero and hex-like values as strings"
                (fn []
                  (assert.are.equal "007" (coerce.from-string "007"))
                  (assert.are.equal "0x10" (coerce.from-string "0x10"))
                  (assert.are.equal "1." (coerce.from-string "1."))))
            (it "parses true and false"
                (fn [] (assert.are.equal true (coerce.from-string "true"))))
            (it "keeps other text as strings"
                (fn [] (assert.are.equal "hello" (coerce.from-string "hello"))))))

(describe "coerce.schema-at"
          (fn []
            (it "walks object properties"
                (fn []
                  (let [s {:type "object"
                           :properties {:a {:type "object"
                                            :properties {:b {:type "string"}}}}}]
                    (assert.are.same {:type "string"}
                                     (coerce.schema-at s ["a" "b"])))))
            (it "returns nil for unknown paths"
                (fn []
                  (assert.is_nil (coerce.schema-at {:type "object"} ["x"]))))))

(describe "numbers from the command line"
          (fn []
            (it "follow JSON's syntax and stay exact"
                (fn []
                  ;; typed: only JSON numbers convert; the rest stays text and
                  ;; validation reports it
                  (assert.are.equal "0x10"
                                    (coerce.from-string "0x10"
                                                        {:type "integer"}))
                  (assert.are.equal "1e400"
                                    (coerce.from-string "1e400"
                                                        {:type "number"}))
                  (assert.are.equal 16
                                    (coerce.from-string "16" {:type "integer"}))
                  ;; untyped: an integer too large for 64 bits stays text
                  (assert.are.equal "12345678901234567890"
                                    (coerce.from-string "12345678901234567890"))
                  (assert.are.equal 9007199254740993
                                    (coerce.from-string "9007199254740993"))))))
