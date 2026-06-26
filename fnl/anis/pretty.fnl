(local colors
  {:reset  "\27[0m"
   :key    "\27[36m"
   :string "\27[32m"
   :number "\27[33m"
   :bool   "\27[35m"
   :null   "\27[31m"
   :punct  "\27[90m"})

(fn c [color s use-color]
  (if use-color (.. (. colors color) s colors.reset) s))

(fn array? [t]
  (var count 0)
  (var max-n 0)
  (each [k _ (pairs t)]
    (set count (+ count 1))
    (when (and (= (type k) :number) (> k max-n))
      (set max-n k)))
  (= count max-n))

(fn pretty [v indent use-color]
  (let [ind (or indent 0)
        uc (not= use-color false)
        pad  (string.rep "  " ind)
        pad+ (string.rep "  " (+ ind 1))]
    (match (type v)
      :table
      (if (= (next v) nil)
          (c :punct "{}" uc)
          (array? v)
          (let [items (icollect [_ x (ipairs v)]
                        (.. pad+ (pretty x (+ ind 1) uc)))]
            (.. (c :punct "[" uc) "\n"
                (table.concat items (.. (c :punct "," uc) "\n"))
                "\n" pad (c :punct "]" uc)))
          (let [items []]
            (each [k x (pairs v)]
              (table.insert items
                (.. pad+
                    (c :key (string.format "%q" (tostring k)) uc)
                    (c :punct ": " uc)
                    (pretty x (+ ind 1) uc))))
            (.. (c :punct "{" uc) "\n"
                (table.concat items (.. (c :punct "," uc) "\n"))
                "\n" pad (c :punct "}" uc))))
      :string (c :string (string.format "%q" v) uc)
      :number (c :number (tostring v) uc)
      :boolean (c :bool (tostring v) uc)
      :nil (c :null "null" uc)
      _ (tostring v))))

{: pretty}
