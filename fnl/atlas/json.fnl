;; ABOUTME: JSON encoding and decoding that keeps arrays apart from objects, even
;; ABOUTME: empty ones; encoding is deterministic (sorted keys) and exact for numbers.
(local lunajson (require :lunajson))

;; lunajson's encoder reads an array's length from index 0; answering it here
;; keeps it out of the table's contents
(local array-mt {:__index (fn [t k]
                            (when (= k 0)
                              (rawlen t)))})

(fn array [t]
  "t marked as a JSON array, so that it encodes as one even when empty."
  (setmetatable t array-mt))

(fn array? [v]
  "Whether v is a JSON array: marked as one, or a table with a first element."
  (and (= (type v) :table)
       (or (= (getmetatable v) array-mt) (not= nil (rawget v 1)))))

(fn mark-arrays [v]
  "v with every array lunajson decoded (length at index 0) marked instead."
  (when (= (type v) :table)
    (when (= (type (rawget v 0)) :number)
      (rawset v 0 nil)
      (array v))
    (each [_ x (pairs v)]
      (mark-arrays x)))
  v)

(fn decode [text ?null]
  "Value of JSON text; JSON null decodes to ?null (default nil, which drops
null object members)."
  (mark-arrays (lunajson.decode text nil ?null true)))

(local escapes {"\"" "\\\""
                "\\" "\\\\"
                "\n" "\\n"
                "\r" "\\r"
                "\t" "\\t"
                "\b" "\\b"
                "\f" "\\f"})

(fn encode-string [s]
  (.. "\"" (pick-values 1 (s:gsub "[%c\"\\]"
                                  #(or (. escapes $)
                                       (if (< (string.byte $) 32)
                                           (string.format "\\u%04x"
                                                          (string.byte $))
                                           $)))) "\""))

(fn encode-number [n]
  (if (= (math.type n) :integer) (string.format "%d" n)
      (or (not= n n) (= n math.huge) (= n (- math.huge)))
      (error (.. "cannot encode " (tostring n) " as JSON") 0)
      ;; the shortest form that reads back as the same number
      (let [s (accumulate [found nil _ digits (ipairs [15 16 17]) &until found]
                (let [s (string.format (.. "%." digits "g") n)]
                  (when (= (tonumber s) n) s)))]
        ;; keep integral floats recognisable as floats
        (if (s:find "[%.eEn]") s (.. s ".0")))))

(fn encode-value [v out active]
  (match (type v)
    :nil (table.insert out "null")
    :boolean (table.insert out (tostring v))
    :number (table.insert out (encode-number v))
    :string (table.insert out (encode-string v))
    :table (do
             (when (. active v)
               (error "cannot encode a table that contains itself as JSON" 0))
             (tset active v true)
             (if (array? v)
                 (do
                   (table.insert out "[")
                   (for [i 1 (length v)]
                     (when (> i 1) (table.insert out ","))
                     (encode-value (. v i) out active))
                   (table.insert out "]"))
                 (let [keys (icollect [k (pairs v)]
                              (if (= (type k) :string) k
                                  (error (.. "cannot encode key " (tostring k)
                                             " as JSON: keys must be strings")
                                         0)))]
                   (table.sort keys)
                   (table.insert out "{")
                   (each [i k (ipairs keys)]
                     (when (> i 1) (table.insert out ","))
                     (table.insert out (encode-string k))
                     (table.insert out ":")
                     (encode-value (. v k) out active))
                   (table.insert out "}")))
             (tset active v nil))
    other (error (.. "cannot encode a " other " as JSON") 0)))

(fn encode [v]
  "Compact JSON for v: object keys sorted, integers exact, floats in their
shortest exact form, and empty tables as {} unless marked as arrays."
  (let [out []]
    (encode-value v out {})
    (table.concat out)))

{: decode : encode : array : array?}
