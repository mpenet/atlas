;; ABOUTME: Specs for atlas.json: decoded arrays stay arrays (even empty ones)
;; ABOUTME: through printing, validation, YAML and re-encoding.
(local json (require :atlas.json))
(local pretty (require :atlas.pretty))
(local yaml (require :atlas.yaml))
(local validate (require :atlas.validate))
(local http (require :atlas.http))

(describe "atlas.json"
          (fn []
            (it "keeps empty arrays and objects apart when re-encoding"
                (fn []
                  (let [v (json.decode "{\"a\":[],\"b\":{},\"c\":[[],{}]}")]
                    (assert.is_true (json.array? v.a))
                    (assert.is_false (json.array? v.b))
                    (assert.are.same {:a "[]" :b "{}" :c "[[],{}]"}
                                     (collect [k x (pairs v)]
                                       k
                                       (json.encode x))))))
            (it "marks tables built in Lua as arrays"
                (fn []
                  (assert.are.equal "{\"tags\":[]}"
                                    (json.encode {:tags (json.array [])}))
                  (assert.are.equal "[1,2]" (json.encode (json.array [1 2])))))
            (it "leaves array contents untouched"
                (fn []
                  (let [v (json.decode "[10,20]")]
                    (assert.are.same [10 20] (icollect [_ x (ipairs v)] x))
                    (assert.is_nil (rawget v 0))
                    (assert.are.equal 2 (length v)))))))

(describe "json.encode"
          (fn []
            (it "writes object keys in sorted order"
                (fn []
                  (assert.are.equal "{\"a\":1,\"b\":{\"x\":true,\"y\":[]},\"c\":\"s\"}"
                                    (json.encode {:c "s"
                                                  :a 1
                                                  :b {:y (json.array [])
                                                      :x true}}))))
            (it "writes integers exactly"
                (fn []
                  (assert.are.equal "[1234567890123456789,-42,0]"
                                    (json.encode (json.array [1234567890123456789
                                                              -42
                                                              0])))))
            (it "writes floats in their shortest exact form"
                (fn []
                  (assert.are.equal "[0.1,0.3333333333333333,1e+300,2.0,-1.5]"
                                    (json.encode (json.array [0.1
                                                              (/ 1 3)
                                                              1e300
                                                              2.0
                                                              -1.5])))))
            (it "escapes strings"
                (fn []
                  (assert.are.equal "\"q\\\"b\\\\n\\nt\\tc\\u0001é/\""
                                    (json.encode "q\"b\\n\nt\tc\1é/"))))
            (it "refuses what JSON cannot express"
                (fn []
                  (assert.has.error #(json.encode (/ 1 0)))
                  (assert.has.error #(json.encode {1.5 "x"}))
                  (let [t {}]
                    (tset t :self t)
                    (assert.has.error #(json.encode t)))))))

(describe "empty arrays elsewhere"
          (fn []
            (it "print as [] in JSON and YAML"
                (fn []
                  (let [v (json.decode "{\"a\":[],\"b\":{}}")]
                    (assert.are.equal "{\n  \"a\": [],\n  \"b\": {}\n}"
                                      (pretty.pretty v 0 false))
                    (assert.are.same v (json.decode (pretty.pretty v 0 false)))
                    (assert.is_true (json.array? (. (yaml.parse (pretty.yaml v
                                                                             0
                                                                             false))
                                                    :a))))))
            (it "come out of YAML as arrays"
                (fn []
                  (let [v (yaml.parse "a: []\nb: {}\nc:\n  - 1\n")]
                    (assert.is_true (json.array? v.a))
                    (assert.is_false (json.array? v.b))
                    (assert.are.same {:a "[]" :b "{}" :c "[1]"}
                                     (collect [k x (pairs v)]
                                       k
                                       (json.encode x))))))
            (it "validate as arrays, and empty objects as objects"
                (fn []
                  (let [v (json.decode "{\"a\":[],\"b\":{}}")]
                    (assert.are.same []
                                     (validate.check {:properties {:a {:type "array"}
                                                                   :b {:type "object"}}}
                                                     v)))))
            (it "are sent as [] in request bodies"
                (fn []
                  (let [(_ payload) (http.encode-request {:method "POST"
                                                          :url "https://h/x"
                                                          :headers {:content-type "application/json"}
                                                          :body (json.decode "{\"tags\":[]}")})]
                    (assert.are.equal "{\"tags\":[]}" payload))))
            (it "survive response decoding"
                (fn []
                  (let [r (http.decode-response 200
                                                {:content-type "application/json"}
                                                "{\"tags\":[]}")]
                    (assert.is_true (json.array? r.body.tags)))))))
