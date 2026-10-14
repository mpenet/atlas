;; ABOUTME: Property specs: random values must round-trip through the encoders,
;; ABOUTME: and random input must never crash the parsers. ATLAS_SEED reproduces a run.
(local json (require :lunajson))
(local pretty (require :atlas.pretty))
(local yaml (require :atlas.yaml))
(local util (require :atlas.util))
(local expr (require :atlas.arazzo.expr))
(local validate (require :atlas.validate))
(local http (require :atlas.http))
(local {: select-path} (require :atlas.cli.output))
(local {: parse-args} (require :atlas.cli.args))

(local seed (tonumber (or (os.getenv :ATLAS_SEED) (os.time))))
(local runs 300)

(fn pick [items]
  (. items (math.random 1 (length items))))

;; characters and words that tend to need quoting or escaping somewhere
(local fragments ["a"
                  "Z"
                  "7"
                  " "
                  "\""
                  "\\"
                  "/"
                  "\n"
                  "\t"
                  ":"
                  "#"
                  "-"
                  ","
                  "'"
                  "{"
                  "}"
                  "["
                  "]"
                  "&"
                  "*"
                  "!"
                  "%"
                  "@"
                  "`"
                  "|"
                  ">"
                  "?"
                  "="
                  "é"
                  "日本"
                  "true"
                  "null"
                  "~"
                  "yes"
                  "1e3"
                  "0x1F"
                  ".inf"
                  "<<"
                  "---"
                  "- "
                  ": "
                  " #"
                  "$"
                  "%20"])

(fn gen-string []
  (table.concat (fcollect [_ 1 (math.random 0 6)]
                  (pick fragments))))

(fn gen-key []
  (let [k (gen-string)]
    (if (= k "") "k" k)))

(fn gen-value [depth]
  (match (math.random 1 (if (> depth 2) 4 6))
    1
    (= 1 (math.random 0 1))
    2
    (math.random -1000000 1000000)
    3
    (/ (math.random -4000 4000) 4)
    4
    (gen-string)
    ;; containers are never empty: {} and [] look alike once decoded
    5
    (fcollect [_ 1 (math.random 1 4)]
      (gen-value (+ depth 1)))
    _
    (collect [_ _ (ipairs [1 2 3])]
      (values (gen-key) (gen-value (+ depth 1))))))

(fn crash? [err]
  "Whether err is a Lua runtime error rather than a reported problem."
  (let [msg (tostring err)]
    (or (msg:find "attempt to" 1 true) (msg:find "bad argument" 1 true)
        (msg:find "stack overflow" 1 true))))

(fn for-all [gen property]
  (math.randomseed seed)
  (for [i 1 runs]
    (let [input (gen)
          (ok err) (pcall property input)]
      (when (not ok)
        (error (string.format "seed %d, run %d, input %s: %s" seed i
                              (pretty.pretty input 0 false) (tostring err)))))))

(describe "round trips"
          (fn []
            (it "JSON output decodes to the same value"
                (fn []
                  (for-all #(gen-value 0)
                           (fn [v]
                             (assert.are.same v
                                              (json.decode (pretty.pretty v 0
                                                                          false)))))))
            (it "YAML output parses to the same value"
                (fn []
                  (for-all #(gen-value 0)
                           (fn [v]
                             (assert.are.same v
                                              (yaml.parse (pretty.yaml v 0
                                                                       false)))))))
            (it "URL encoding decodes to the same string"
                (fn []
                  (for-all gen-string
                           (fn [s]
                             (assert.are.equal s
                                               (util.url-decode (util.url-encode s)))))))))

(describe "parsers never crash"
          (fn []
            (it "YAML: parses or reports a parse error"
                (fn []
                  (for-all gen-string
                           (fn [text]
                             (let [(ok err) (pcall yaml.parse text)]
                               (assert (or ok (not (crash? err))) err))))))
            (it "Arazzo conditions: evaluate or report the problem"
                (fn []
                  (let [ctx {:inputs {:n 3 :s "x"}
                             :response {:status 200
                                        :headers {:x-a "1"}
                                        :body {:list [1 2] :n 2}}
                             :steps {}
                             :workflows {}}
                        tokens ["$statusCode"
                                "$inputs.n"
                                "$inputs.s"
                                "$response.body#/n"
                                "$response.header.x-a"
                                "$response.body#/list/0"
                                "=="
                                "!="
                                "<"
                                ">="
                                "&&"
                                "||"
                                "!"
                                "("
                                ")"
                                "200"
                                "3"
                                "'x'"
                                "\"y\""
                                "null"
                                "true"
                                "false"
                                "$nope"
                                "#"
                                "'"
                                "1.5"
                                "-2"]]
                    (for-all #(table.concat (fcollect [_ 1 (math.random 1 7)]
                                              (pick tokens))
                                            " ")
                             (fn [condition]
                               (let [(ok err) (pcall expr.eval-criterion ctx
                                                     {: condition})]
                                 (assert (or ok (not (crash? err))) err)))))))
            (it "--select paths: select something or nothing"
                (fn []
                  (let [parts [".a"
                               ".b"
                               "[0]"
                               "[1]"
                               "[]"
                               "{a,b}"
                               "{a}"
                               "."
                               "["
                               "]"
                               "{"
                               "}"
                               ".0"
                               "[x]"
                               "[-1]"]]
                    (for-all #[(gen-value 0)
                               (table.concat (fcollect [_ 1 (math.random 0 5)]
                                               (pick parts)))]
                             (fn [[data path]]
                               (select-path data path))))))
            (it "validation: returns a list of errors"
                (fn []
                  (let [types ["string"
                               "integer"
                               "number"
                               "boolean"
                               "object"
                               "array"]
                        gen-schema (fn gen-schema [depth]
                                     (let [s {}]
                                       (when (= 1 (math.random 0 1))
                                         (set s.type (pick types)))
                                       (when (= 1 (math.random 0 4))
                                         (set s.enum
                                              [(gen-value 2) (gen-value 2)]))
                                       (when (= 1 (math.random 0 3))
                                         (set s.minimum (math.random -5 5)))
                                       (when (= 1 (math.random 0 3))
                                         (set s.maxLength (math.random 0 5)))
                                       (when (< depth 3)
                                         (when (= 1 (math.random 0 2))
                                           (set s.properties
                                                {:a (gen-schema (+ depth 1))
                                                 :b (gen-schema (+ depth 1))})
                                           (set s.required [:a]))
                                         (when (= 1 (math.random 0 3))
                                           (set s.items
                                                (gen-schema (+ depth 1))))
                                         (when (= 1 (math.random 0 4))
                                           (set s.anyOf
                                                [(gen-schema (+ depth 1))
                                                 (gen-schema (+ depth 1))])))
                                       s))]
                    (for-all #[(gen-schema 0) (gen-value 0)]
                             (fn [[schema value]]
                               (assert.is_table (validate.check schema value)))))))
            (it "response headers: parse whatever comes back"
                (fn []
                  (for-all gen-string
                           (fn [text]
                             (assert.is_table (http.parse-headers text))))))
            (it "arguments: parse or report the problem"
                (fn []
                  (let [args ["op"
                              "az"
                              "profile"
                              "x"
                              "--q.a=1"
                              "--b.x.y=2"
                              "-d"
                              "{}"
                              "--body"
                              "--select"
                              ".a"
                              "-v"
                              "--output"
                              "yaml"
                              "--timeout"
                              "abc"
                              "--"
                              "-i"
                              "a=b"
                              "--i."
                              "--server.z=1"
                              "--ssl.verify=none"
                              "--nope"
                              "="
                              "--h.X=1"]]
                    (for-all #(fcollect [_ 1 (math.random 0 6)]
                                (pick args))
                             (fn [argv]
                               (let [(ok err) (pcall parse-args argv)]
                                 (assert (or ok (not (crash? err))) err)))))))))

(describe "multipart bodies"
          (fn []
            (it "never contain their boundary inside a part"
                (fn []
                  (for-all #(collect [_ _ (ipairs [1 2 3])]
                              (values (gen-key) (gen-string)))
                           (fn [fields]
                             (let [(payload content-type) (http.encode-body {:headers {:content-type "multipart/form-data"}
                                                                             :body fields})
                                   boundary (content-type:match "boundary=(.+)$")
                                   ;; the delimiter appears once per field plus
                                   ;; the closing one
                                   (_ n) (payload:gsub (.. "%-%-"
                                                           (boundary:gsub "%p"
                                                                          "%%%0"))
                                                       "")
                                   fields-n (accumulate [c 0 _ (pairs fields)]
                                              (+ c 1))]
                               (assert.are.equal (+ fields-n 1) n))))))))
