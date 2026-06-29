(local preferred
  [:application/json
   :application/x-www-form-urlencoded
   :multipart/form-data])

(fn pick-media-type [content]
  (when content
    (var found nil)
    (each [_ mt (ipairs preferred) :until found]
      (when (. content mt) (set found mt)))
    (when (not found)
      (each [k _ (pairs content) :until found]
        (set found k)))
    found))

(fn pick-content-type [op-spec]
  (when op-spec.requestBody
    (pick-media-type op-spec.requestBody.content)))

(fn pick-accept [op-spec]
  (let [seen {}
        types []]
    (each [_ resp (pairs (or op-spec.responses {}))]
      (each [mt _ (pairs (or resp.content {}))]
        (when (not (. seen mt))
          (tset seen mt true)
          (table.insert types mt))))
    (when (> (length types) 0)
      (table.sort types)
      (table.concat types ", "))))

{: pick-content-type : pick-accept}
