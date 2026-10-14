;; ABOUTME: Shared helpers: JSON pointers, URL/form encoding, path templating,
;; ABOUTME: URL resolution, header lookup, secrets and atlas directories.
(fn unescape-pointer [segment]
  "A JSON Pointer segment with ~1 and ~0 unescaped (in that order)."
  (pick-values 1 (-> segment (: :gsub "~1" "/") (: :gsub "~0" "~"))))

(fn success? [status]
  "True for 2xx HTTP statuses."
  (and (= (type status) :number) (>= status 200) (< status 300)))

(fn json-pointer [obj ptr]
  "Value at JSON Pointer ptr (RFC 6901) in obj: \"\" is obj itself, ~1 and ~0
are unescaped, numeric segments index arrays 0-based."
  (accumulate [cur obj seg (ptr:gmatch "/([^/]*)")]
    (when (= (type cur) :table)
      (let [key (unescape-pointer seg)
            n (when (key:match "^%d+$") (tonumber key))]
        (if (and n (= nil (. cur key)))
            (. cur (+ n 1))
            (. cur key))))))

(fn camel->kebab [s]
  (let [(s) (s:gsub "(%u+)(%u%l)" "%1-%2")
        (s) (s:gsub "(%l)(%u)" "%1-%2")]
    (s:lower)))

(fn operation-name [method path op-spec]
  "Kebab-case name of an operation: its operationId, or method and path words
when it has none (get /pets/{petId} → get-pets-pet-id)."
  (if op-spec.operationId (camel->kebab op-spec.operationId)
      (let [words [(method:lower)]]
        (each [word (path:gmatch "[%w_]+")]
          (table.insert words (camel->kebab word)))
        (table.concat words "-"))))

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

(fn shell-quote [s]
  "Quote s as a single POSIX shell word."
  (.. "'" (pick-values 1 (: (tostring s) :gsub "'" "'\\''")) "'"))

(fn origin [url]
  "scheme://host:port as the transport will connect, default port explicit.
Parsed by luasocket so it agrees with where requests actually go."
  (let [parsed ((. (require :socket.url) :parse) url)]
    (when (and parsed parsed.scheme parsed.host)
      (let [scheme (parsed.scheme:lower)]
        (.. scheme "://" (parsed.host:lower) ":"
            (or parsed.port (if (= scheme "https") "443" "80")))))))

(fn header [headers name]
  "Case-insensitive header lookup."
  (let [wanted (name:lower)]
    (accumulate [found nil k v (pairs (or headers {})) &until found]
      (when (= (k:lower) wanted) v))))

(fn url-encode [s]
  (pick-values 1
               (: (tostring s) :gsub "[^%w%-%.%_%~]"
                  (fn [c] (string.format "%%%02X" (string.byte c))))))

(fn percent-decode [s]
  "s with %XX escapes decoded; + is left as is (URI syntax)."
  (pick-values 1 (s:gsub "%%(%x%x)" (fn [h] (string.char (tonumber h 16))))))

(fn url-decode [s]
  "Decode form/query text: + is a space, then %XX escapes."
  (percent-decode (pick-values 1 (s:gsub "+" " "))))

(fn secret-name? [name]
  "True when a header or query parameter name looks like it carries a credential."
  (let [n (name:lower)]
    (not= nil (or (n:match "auth") (n:match "cookie") (n:match "key")
                  (n:match "token") (n:match "secret") (n:match "sig")
                  (n:match "passw")))))

(fn redact-url [url]
  "url with the values of credential-like query parameters masked."
  (pick-values 1 (url:gsub "([?&])([^=&#]+)=([^&#]*)"
                           (fn [sep name value]
                             (.. sep name "="
                                 (if (secret-name? (url-decode name))
                                     "<redacted>"
                                     value))))))

(fn form-encode [params]
  "Encode params as application/x-www-form-urlencoded, keys sorted.
Array values repeat the key (OpenAPI style=form, explode=true)."
  (let [keys (icollect [k (pairs params)] k)
        parts []]
    (table.sort keys #(< (tostring $1) (tostring $2)))
    (each [_ k (ipairs keys)]
      (let [v (. params k)
            vs (if (= (type v) :table) v [v])]
        (when (and (= (type v) :table) (= nil (. v 1)) (not= nil (next v)))
          (error (.. "'" (tostring k)
                     "' is an object; query and form values must be scalars or lists")
                 0))
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
 : operation-name
 : extract-path-params
 : resolve-path
 : url-encode
 : url-decode
 : form-encode
 : resolve-reference
 : header
 : append-query
 : cache-dir
 : config-dir
 : merge-parameters
 : replace-all
 : shell-quote
 : secret-name?
 : redact-url
 : origin
 : json-pointer
 : unescape-pointer
 : success?
 : percent-decode}
