;; ABOUTME: Shared helpers: JSON pointers, URL/form encoding, path templating,
;; ABOUTME: URL resolution, header lookup, secrets and atlas directories.
(local json (require :atlas.json))
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
  "Name of an operation: its operationId, or its method and path when it has
none (get /pets/{petId} → get-pets-pet-id), in lowercase words joined by
dashes (getPetById → get-pet-by-id, projects/list_cards → projects-list-cards)."
  (let [words (if op-spec.operationId
                  (camel->kebab (tostring op-spec.operationId))
                  (table.concat (icollect [word (path:gmatch "%w+")]
                                  (camel->kebab word))
                                "-"))
        name (if op-spec.operationId words (.. (method:lower) "-" words))]
    (pick-values 1 (: (: (name:lower) :gsub "[^%w]+" "-") :gsub "^%-*(.-)%-*$"
                      "%1"))))

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

(local default-ports {:http "80" :https "443"})

(fn origin [url]
  "scheme://host:port of an http(s) URL, port explicit, as libcurl connects:
the authority ends at the first / ? #, and user info before its last @ is
dropped. nil for anything else, and for an authority holding a \\, which
URL parsers read differently: such a URL matches no origin."
  (let [(scheme rest) (url:match "^(%a[%w+.-]*)://(.*)$")
        scheme (and scheme (scheme:lower))]
    ;; control characters (a NUL ends the URL libcurl sees) match no origin
    (when (and scheme (. default-ports scheme) (not (url:find "%c")))
      (let [authority (rest:match "^([^/?#]*)")
            hostport (or (authority:match "^.*@(.*)$") authority)
            (host port) (if (hostport:match "^%[")
                            (hostport:match "^(%[[^%]]*%]):?(%d*)$")
                            (hostport:match "^([^:]*):?(%d*)$"))]
        (when (and host (not= host "") (not (authority:find "\\" 1 true)))
          (.. scheme "://" (host:lower) ":"
              (if (= port "") (. default-ports scheme) port)))))))

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

(fn redact-url [url ?names]
  "url with its user info masked, and the values of query parameters that look
like credentials or are in the set ?names (lowercase)."
  (let [(without-userinfo) (url:gsub "^(%a[%w+.-]*://)[^/?#]*@" "%1<redacted>@")]
    (pick-values 1 (without-userinfo:gsub "([?&])([^=&#]+)=([^&#]*)"
                     (fn [sep name value]
                       (let [n (url-decode name)]
                         (.. sep name "="
                             (if (or (secret-name? n) (?. ?names (n:lower)))
                                 "<redacted>"
                                 value))))))))

(fn without-nulls [v]
  "v without its null elements or members: null is no value to send."
  (if (or (not= (type v) :table) (= v json.null)) v (json.array? v)
      (icollect [_ x (ipairs v)] (when (not= x json.null) x))
      (collect [k x (pairs v)] (when (not= x json.null) (values k x)))))

(fn form-encode [params]
  "Encode params as application/x-www-form-urlencoded, keys sorted.
Array values repeat the key (OpenAPI style=form, explode=true)."
  (let [keys (icollect [k (pairs params)] k)
        parts []]
    (table.sort keys #(< (tostring $1) (tostring $2)))
    (each [_ k (ipairs keys)]
      (let [v (. params k)
            vs (if (= (type v) :table) (without-nulls v) [v])]
        (when (and (= (type v) :table) (= nil (. v 1)) (not= nil (next v)))
          (error (.. "'" (tostring k)
                     "' is an object; query and form values must be scalars or lists")
                 0))
        (each [_ x (ipairs vs)]
          (table.insert parts (.. (url-encode k) "=" (url-encode x))))))
    (table.concat parts "&")))

(local delimiters {:form "," :spaceDelimited "%20" :pipeDelimited "|"})

(fn query-pairs [name raw style explode]
  "\"key=value\" strings for one query parameter in an OpenAPI style
(form, spaceDelimited, pipeDelimited, deepObject); values are encoded,
delimiters are not."
  (let [value (without-nulls raw)
        k (url-encode name)
        enc url-encode]
    (if (not= (type value) :table) [(.. k "=" (enc value))]
        (not= nil (. value 1))
        (if explode
            (icollect [_ x (ipairs value)] (.. k "=" (enc x)))
            [(.. k "="
                 (table.concat (icollect [_ x (ipairs value)] (enc x))
                               (. delimiters style)))])
        (let [keys (doto (icollect [p (pairs value)] p)
                     (table.sort))]
          (if (= style :deepObject)
              (icollect [_ p (ipairs keys)]
                (.. k "[" (enc p) "]=" (enc (. value p))))
              explode
              (icollect [_ p (ipairs keys)]
                (.. (enc p) "=" (enc (. value p))))
              (let [d (. delimiters style)]
                [(.. k "=" (table.concat (icollect [_ p (ipairs keys)]
                                           (.. (enc p) d (enc (. value p))))
                                         d))]))))))

(fn query-string [params ?styles]
  "Query string for params, keys sorted; ?styles maps a parameter name to
its {:style :explode} (default: form, exploded)."
  (let [names (doto (icollect [k (pairs params)] k)
                (table.sort #(< (tostring $1) (tostring $2))))
        parts []]
    (each [_ name (ipairs names)]
      (let [{: style : explode} (or (?. ?styles name) {})
            style (or style :form)
            explode (if (= nil explode) (= style :form) explode)
            ;; null is no value: left out, as are null list elements
            raw (. params name)
            value (if (= raw json.null) nil (json.array? raw)
                      (icollect [_ x (ipairs raw)]
                        (when (not= x json.null) x)) raw)]
        (each [_ part (ipairs (if (= nil value) []
                                  (query-pairs name value style explode)))]
          (table.insert parts part))))
    (table.concat parts "&")))

(fn append-query [url params ?styles]
  "Append params to url as a query string (see query-string), extending any
existing one."
  (let [qs (query-string params ?styles)]
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

(fn simple-style [raw]
  "A path parameter value in OpenAPI's default simple style: arrays as
a,b and objects as k1,v1,k2,v2 (keys sorted), each part url-encoded."
  (local v (without-nulls raw))
  (if (not= (type v) :table) (url-encode v) (not= nil (. v 1))
      (table.concat (icollect [_ x (ipairs v)] (url-encode x)) ",")
      (let [keys (doto (icollect [k (pairs v)] k)
                   (table.sort))]
        (table.concat (icollect [_ k (ipairs keys)]
                        (.. (url-encode k) "," (url-encode (. v k))))
                      ","))))

(fn resolve-path [template params]
  "Substitute {name} segments in template with params[name], url-encoded."
  (pick-values 1 (template:gsub "{([^}]+)}"
                                (fn [param]
                                  (let [v (. params param)]
                                    (assert (and (not= nil v)
                                                 (not= v json.null))
                                            (.. "missing required path parameter: "
                                                param))
                                    (simple-style v))))))

{: camel->kebab
 : query-string
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
