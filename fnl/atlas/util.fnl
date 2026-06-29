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

{: camel->kebab : extract-path-params : resolve-path}
