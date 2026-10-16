;; ABOUTME: Renders decoded values as colorized JSON or YAML for terminal output.
;; ABOUTME: Output is deterministic: object keys are sorted.
(local json (require :atlas.json))

(local colors {:reset "\27[0m"
               :key "\27[36m"
               :string "\27[32m"
               :number "\27[33m"
               :bool "\27[35m"
               :null "\27[31m"
               :punct "\27[90m"
               :dim "\27[2m"
               :ok "\27[32m"
               :warn "\27[33m"
               :fail "\27[31m"})

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

(local json-escapes {"\"" "\\\""
                     "\\" "\\\\"
                     "\b" "\\b"
                     "\f" "\\f"
                     "\n" "\\n"
                     "\r" "\\r"
                     "\t" "\\t"})

(fn json-string [s]
  (.. "\""
      (pick-values 1
                   (s:gsub "[%c\"\\]"
                           (fn [ch]
                             (or (. json-escapes ch)
                                 (string.format "\\u%04x" (string.byte ch))))))
      "\""))

(fn json-number [n]
  (if (or (not= n n) (= n math.huge) (= n (- math.huge)))
      "null"
      (tostring n)))

(fn sorted-keys [t]
  (let [ks (icollect [k (pairs t)] k)]
    (table.sort ks #(< (tostring $1) (tostring $2)))
    ks))

(fn pretty [v indent use-color]
  (let [ind (or indent 0)
        uc (not= use-color false)
        pad (string.rep "  " ind)
        pad+ (string.rep "  " (+ ind 1))]
    (match (if (= v json.null) :nil (type v))
      :table (if (= (next v) nil)
                 (c :punct (if (json.array? v) "[]" "{}") uc)
                 (array? v)
                 (let [items (icollect [_ x (ipairs v)]
                               (.. pad+ (pretty x (+ ind 1) uc)))]
                   (.. (c :punct "[" uc) "\n"
                       (table.concat items (.. (c :punct "," uc) "\n")) "\n" pad
                       (c :punct "]" uc)))
                 (let [items []]
                   (each [_ k (ipairs (sorted-keys v))]
                     (table.insert items
                                   (.. pad+
                                       (c :key (json-string (tostring k)) uc)
                                       (c :punct ": " uc)
                                       (pretty (. v k) (+ ind 1) uc))))
                   (.. (c :punct "{" uc) "\n"
                       (table.concat items (.. (c :punct "," uc) "\n")) "\n" pad
                       (c :punct "}" uc))))
      :string (c :string (json-string v) uc)
      :number (c :number (json-number v) uc)
      :boolean (c :bool (tostring v) uc)
      :nil (c :null "null" uc)
      _ (tostring v))))

(local yaml-reserved (collect [_ w (ipairs ["y"
                                            "n"
                                            "yes"
                                            "no"
                                            "true"
                                            "false"
                                            "on"
                                            "off"
                                            "null"
                                            "~"
                                            ".inf"
                                            "-.inf"
                                            "+.inf"
                                            ".nan"])]
                       w
                       true))

(fn yaml-needs-quotes? [s]
  "True when s would not read back as the same string from a plain scalar."
  (or (= s "") (. yaml-reserved (s:lower)) (not= nil (tonumber s))
      (s:match "^[0-9]") (s:match "^[-?:,%[%]{}#&*!|>'\"%%@`.+~]")
      (s:match "%c") (s:match ":[ \t]") (s:match ":$") (s:match " #")
      (s:match "^%s") (s:match "%s$")))

(local yaml-escapes {"\\" "\\\\" "\"" "\\\"" "\n" "\\n" "\r" "\\r" "\t" "\\t"})

(fn yaml-escape [s]
  "s for a double-quoted YAML scalar; other control characters as \\xNN."
  (pick-values 1
               (s:gsub "[%c\"\\]"
                       #(or (. yaml-escapes $)
                            (string.format "\\x%02X" (string.byte $))))))

(fn yaml-number [n]
  "n as YAML writes it: infinities and NaN have names of their own."
  (if (not= n n) ".nan"
      (= n math.huge) ".inf"
      (= n (- math.huge)) "-.inf"
      (tostring n)))

(fn yaml-key [k]
  "k as a mapping key that reads back as the same string; canonical integers
such as response codes stay bare."
  (if (and (k:match "^%d+$") (= k (tostring (math.tointeger (tonumber k))))) k
      ;; a plain << key is a merge
      (or (= k "<<") (yaml-needs-quotes? k)) (.. "\"" (yaml-escape k) "\"") k))

(fn yaml [v ?indent ?use-color]
  (let [ind (or ?indent 0)
        uc (not= ?use-color false)
        pad (string.rep "  " ind)]
    (match (if (= v json.null) :nil (type v))
      :table (if (= (next v) nil)
                 (c :punct (if (json.array? v) "[]" "{}") uc)
                 (array? v)
                 (let [lines []]
                   (each [_ x (ipairs v)]
                     (let [rendered (yaml x (+ ind 1) uc)]
                       (if (rendered:match "^\n")
                           (table.insert lines
                                         (.. pad (c :punct "-" uc) " "
                                             (rendered:gsub "^\n%s*" "")))
                           (table.insert lines
                                         (.. pad (c :punct "-" uc) " " rendered)))))
                   (.. "\n" (table.concat lines "\n")))
                 (let [lines []]
                   (each [_ k (ipairs (sorted-keys v))]
                     (let [key (yaml-key (tostring k))
                           rendered (yaml (. v k) (+ ind 1) uc)]
                       (if (rendered:match "^\n")
                           (table.insert lines
                                         (.. pad (c :key key uc)
                                             (c :punct ":" uc) rendered))
                           (table.insert lines
                                         (.. pad (c :key key uc)
                                             (c :punct ":" uc) " " rendered)))))
                   (.. "\n" (table.concat lines "\n"))))
      :string (let [s (if (yaml-needs-quotes? v)
                          (.. "\"" (yaml-escape v) "\"")
                          v)]
                (c :string s uc))
      :number (c :number (yaml-number v) uc)
      :boolean (c :bool (tostring v) uc)
      _ (c :null "null" uc))))

{: pretty : yaml :paint c}
