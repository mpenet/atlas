(fn resolve-ref [root ref-str]
  (when (and root (ref-str:match "^#/"))
    (var cur root)
    (let [path (ref-str:sub 3)]
      (each [part (path:gmatch "[^/]+")]
        (when cur (set cur (. cur part)))))
    cur))

(fn deref-deep [root obj ?seen]
  (if (not= (type obj) :table)
      obj
      (let [ref (. obj "$ref")]
        (if ref
            (if (?. ?seen ref)
                {}
                (let [resolved (resolve-ref root ref)
                      seen (collect [k v (pairs (or ?seen {}))] k v)]
                  (tset seen ref true)
                  (deref-deep root (or resolved {}) seen)))
            (collect [k v (pairs obj)]
              k (deref-deep root v ?seen))))))

(fn camel->kebab [s]
  (let [(s) (s:gsub "(%u+)(%u%l)" "%1-%2")
        (s) (s:gsub "(%l)(%u)" "%1-%2")]
    (s:lower)))

(fn extract-path-params [template]
  (icollect [p (template:gmatch "{([^}]+)}")] p))

(fn resolve-path [template args]
  (var i 0)
  (template:gsub "{([^}]+)}"
    (fn [param]
      (set i (+ i 1))
      (let [v (. args i)]
        (assert v (.. "missing required path parameter: " param))
        (tostring v)))))

{: camel->kebab : extract-path-params : resolve-path : deref-deep}
