;; ABOUTME: Parses YAML (or JSON) documents into plain Lua tables with JSON
;; ABOUTME: semantics: nulls dropped, keys stringified.
(local lyaml (require :lyaml))
(local json (require :lunajson))

(fn array? [t]
  (let [n (length t)]
    (if (= n 0)
        (do
          (var empty? true)
          (each [_ _ (pairs t) &until (not empty?)]
            (set empty? false))
          empty?)
        (do
          (var count 0)
          (each [_ _ (pairs t)] (set count (+ count 1)))
          (= count n)))))

(fn normalize [v]
  (if (= v lyaml.null) nil (not= (type v) :table) v (array? v)
      (icollect [_ x (ipairs v)] (normalize x))
      (let [out {}]
        (each [k x (pairs v)]
          (let [nx (normalize x)]
            (when (not= nx nil)
              (tset out (if (= (type k) :string) k (tostring k)) nx))))
        out)))

(fn parse [content]
  "Parse YAML text → Lua table with JSON-parity semantics."
  (let [(ok parsed) (pcall lyaml.load content)]
    (assert ok (.. "YAML parse error: " (tostring parsed)))
    (normalize parsed)))

(fn decode [content]
  "Try JSON first (faster, stricter); fall back to YAML on parse failure."
  (let [(ok parsed) (pcall json.decode content)]
    (if ok parsed (parse content))))

{: parse : decode : normalize}
