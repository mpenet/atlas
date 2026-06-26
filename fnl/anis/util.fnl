(fn camel->kebab [s]
  (let [(s) (s:gsub "(%u+)(%u%l)" "%1-%2")
        (s) (s:gsub "(%l)(%u)" "%1-%2")]
    (s:lower)))

(fn extract-path-params [template]
  (icollect [p (template:gmatch "{([^}]+)}")] p))

(fn resolve-path [template args]
  (var i 0)
  (template:gsub "{[^}]+}"
    (fn [_]
      (set i (+ i 1))
      (tostring (. args i)))))

{: camel->kebab : extract-path-params : resolve-path}
