;; ABOUTME: Shared helpers: $ref resolution, URL/form encoding, path templating,
;; ABOUTME: reference resolution, header lookup and atlas directories.
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
                      seen (collect [k v (pairs (or ?seen {}))]
                             k
                             v)]
                  (tset seen ref true)
                  (deref-deep root (or resolved {}) seen)))
            (collect [k v (pairs obj)]
              k
              (deref-deep root v ?seen))))))

(fn camel->kebab [s]
  (let [(s) (s:gsub "(%u+)(%u%l)" "%1-%2")
        (s) (s:gsub "(%l)(%u)" "%1-%2")]
    (s:lower)))

(fn extract-path-params [template]
  (icollect [p (template:gmatch "{([^}]+)}")] p))

(fn xdg-dir [env-var fallback]
  (let [base (os.getenv env-var)]
    (.. (if (and base (not= base ""))
            base
            (.. (or (os.getenv "HOME") ".") "/" fallback)) "/atlas")))

(fn cache-dir []
  "Atlas cache directory: $XDG_CACHE_HOME/atlas, default ~/.cache/atlas."
  (xdg-dir "XDG_CACHE_HOME" ".cache"))

(fn config-dir []
  "Atlas config directory: $XDG_CONFIG_HOME/atlas, default ~/.config/atlas."
  (xdg-dir "XDG_CONFIG_HOME" ".config"))

(fn replace-all [s needle replacement]
  "Replace every literal occurrence of needle in s."
  (let [out []]
    (var pos 1)
    (var i (s:find needle pos true))
    (while i
      (table.insert out (s:sub pos (- i 1)))
      (table.insert out replacement)
      (set pos (+ i (length needle)))
      (set i (s:find needle pos true)))
    (table.insert out (s:sub pos))
    (table.concat out)))

(fn header [headers name]
  "Case-insensitive header lookup."
  (let [wanted (name:lower)]
    (accumulate [found nil k v (pairs (or headers {})) &until found]
      (when (= (k:lower) wanted) v))))

(fn url-encode [s]
  (pick-values 1
               (: (tostring s) :gsub "[^%w%-%.%_%~]"
                  (fn [c] (string.format "%%%02X" (string.byte c))))))

(fn url-decode [s]
  (pick-values 1
               (-> s
                   (: :gsub "+" " ")
                   (: :gsub "%%(%x%x)" (fn [h] (string.char (tonumber h 16)))))))

(fn form-encode [params]
  "Encode params as application/x-www-form-urlencoded, keys sorted.
Array values repeat the key (OpenAPI style=form, explode=true)."
  (let [keys (icollect [k (pairs params)] k)
        parts []]
    (table.sort keys #(< (tostring $1) (tostring $2)))
    (each [_ k (ipairs keys)]
      (let [v (. params k)
            vs (if (= (type v) :table) v [v])]
        (each [_ x (ipairs vs)]
          (table.insert parts (.. (url-encode k) "=" (url-encode x))))))
    (table.concat parts "&")))

(fn append-query [url params]
  "Append form-encoded params to url, extending any existing query string."
  (let [qs (form-encode params)]
    (if (= qs "") url
        (url:find "?" 1 true) (.. url "&" qs)
        (.. url "?" qs))))

(fn normalize-segments [path]
  "Collapse ./ and ../ segments in a slash-separated path; ../ never climbs
above the root of an absolute path."
  (let [absolute? (= (path:sub 1 1) "/")
        out []]
    (each [seg (path:gmatch "[^/]+")]
      (if (= seg ".") nil (= seg "..")
          (if (and (> (length out) 0) (not= (. out (length out)) ".."))
              (table.remove out)
              (when (not absolute?) (table.insert out seg)))
          (table.insert out seg)))
    (.. (if absolute? "/" "") (table.concat out "/"))))

(fn resolve-reference [base ref]
  "Resolve ref (URL or path) relative to the document located at base."
  (let [(origin base-path) (base:match "^(%a[%w+.-]*://[^/?#]*)([^?#]*)")]
    (if (ref:match "^%a[%w+.-]*://") ref origin
        (let [dir (if (= (ref:sub 1 1) "/")
                      ""
                      (or (base-path:match "^(.*/)") "/"))]
          (.. origin (normalize-segments (.. dir ref))))
        (= (ref:sub 1 1) "/") ref
        (normalize-segments (.. (or (base:match "^(.*/)") "") ref)))))

(fn merge-parameters [base override]
  "Concatenate OpenAPI/Arazzo parameter lists; override entries replace base entries
with the same name and location."
  (let [param-key (fn [p] (.. (tostring p.in) ":" p.name))
        replaced (collect [_ p (ipairs (or override []))]
                   (param-key p)
                   true)
        out (icollect [_ p (ipairs (or base []))]
              (when (not (. replaced (param-key p)))
                p))]
    (each [_ p (ipairs (or override []))]
      (table.insert out p))
    out))

(fn resolve-path [template params]
  "Substitute {name} segments in template with url-encoded params[name]."
  (pick-values 1 (template:gsub "{([^}]+)}"
                                (fn [param]
                                  (let [v (. params param)]
                                    (assert (not= nil v)
                                            (.. "missing required path parameter: "
                                                param))
                                    (url-encode v))))))

{: camel->kebab
 : extract-path-params
 : resolve-path
 : deref-deep
 : url-encode
 : url-decode
 : form-encode
 : resolve-reference
 : header
 : append-query
 : cache-dir
 : config-dir
 : merge-parameters
 : replace-all}
