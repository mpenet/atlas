;; ABOUTME: Specs for JSONPath (RFC 9535): the official compliance test suite
;; ABOUTME: (test/fixtures/jsonpath-cts.json), values and normalized paths.
(local jsonpath (require :atlas.jsonpath))
(local json (require :atlas.json))

(local cts (with-open [f (io.open "test/fixtures/jsonpath-cts.json")]
             (json.decode (f:read :*a) true)))

;; The suite expects ^ and $ to be anchors in these two; RFC 9485 makes them
;; ordinary characters, as one of its authors confirmed, and the suite is to
;; change: https://github.com/jsonpath-standard/jsonpath-compliance-test-suite/issues/122
(local corrections
       {"functions, match, explicit caret" {:result [] :result_paths []}
        "functions, match, explicit dollar" {:result [] :result_paths []}})

(each [_ t (ipairs cts.tests)]
  (let [c (. corrections t.name)]
    (when c
      (set t.result (json.array c.result))
      (set t.result_paths (json.array c.result_paths)))))

(fn same? [a b]
  (= (json.encode a) (json.encode b)))

(fn outcome [selector document]
  "(values paths) of the nodes selector selects in document."
  (let [nodes (jsonpath.query selector document)]
    (values (json.array (icollect [_ n (ipairs nodes)] n.value))
            (json.array (icollect [_ n (ipairs nodes)]
                          (jsonpath.normalized-path n.path))))))

(describe "the JSONPath compliance test suite"
          (fn []
            (each [_ t (ipairs cts.tests)]
              (it t.name
                  (fn []
                    (if t.invalid_selector
                        (assert.is_false (pcall jsonpath.compile t.selector)
                                         t.selector)
                        (let [(got paths) (outcome t.selector t.document)]
                          (if t.result
                              (do
                                (assert.is_true (same? t.result got)
                                                (.. t.selector " gave "
                                                    (json.encode got)))
                                (when t.result_paths
                                  (assert.is_true (same? t.result_paths paths)
                                                  (.. t.selector " gave "
                                                      (json.encode paths)))))
                              (assert.is_true (accumulate [ok false i r (ipairs t.results)
                                                           &until ok]
                                                (and (same? r got)
                                                     (or (= nil t.results_paths)
                                                         (same? (. t.results_paths
                                                                   i)
                                                                paths))))
                                              (.. t.selector " gave "
                                                  (json.encode got)))))))))))
