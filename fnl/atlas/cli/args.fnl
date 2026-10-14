;; ABOUTME: Parses atlas command-line arguments into a plain table, including
;; ABOUTME: the --query./--q. style field prefixes.
(local {: read-body : decode-structured} (require :atlas.cli.request))

(local field-prefixes {:query :query
                       :q :query
                       :header :header
                       :h :header
                       :body :body
                       :b :body
                       :input :input
                       :i :input})

(fn field-arg [a]
  "For --PREFIX.KEY=VAL arguments with a known prefix (long or short form),
returns (kind key value); kind is :query, :header, :body or :input."
  (let [(prefix k v) (a:match "^%-%-(%a+)%.(.-)=(.*)$")
        kind (when prefix (. field-prefixes prefix))]
    (when kind
      (values kind k v))))

(fn parse-args [args]
  (let [r {:path-params []
           :query {}
           :headers {}
           :ssl {}
           :server-vars {}
           :body-fields []
           :input-fields []}
        positional (fn [a]
                     (if (not r.cmd) (tset r :cmd a)
                         (not r.schema) (tset r :schema a)
                         (not r.operation) (tset r :operation a)
                         (table.insert r.path-params a)))
        value-after (fn [flag i]
                      (or (. args (+ i 1))
                          (error (.. flag " requires a value") 0)))]
    (var i 1)
    (var options-done false)
    (while (<= i (length args))
      (let [a (. args i)]
        (if options-done
            (positional a)
            (= a "--")
            (set options-done true)
            (field-arg a)
            (let [(kind k v) (field-arg a)]
              (match kind
                :query (tset r.query k v)
                :header (tset r.headers k v)
                :body (table.insert r.body-fields [k v])
                :input (table.insert r.input-fields [k v])))
            (a:match "^%-%-server%.(.-)=(.+)")
            (let [(k v) (a:match "^%-%-server%.(.-)=(.+)")]
              (tset r.server-vars k v))
            (a:match "^%-%-ssl%.(.-)=(.+)")
            (let [(k v) (a:match "^%-%-ssl%.(.-)=(.+)")]
              (tset r.ssl k v))
            (a:match "^%-%-body=(.*)")
            (let [(v) (a:match "^%-%-body=(.*)")]
              (tset r :body (read-body v)))
            (= a :-d)
            (do
              (tset r :body (read-body (value-after a i)))
              (set i (+ i 1)))
            (a:match "^%-%-schema=(.+)")
            (let [(v) (a:match "^%-%-schema=(.+)")]
              (tset r :schema-url v))
            (a:match "^%-%-retry=(%d+)$")
            (tset r :retry (tonumber (a:match "^%-%-retry=(%d+)$")))
            (a:match "^%-%-retry%-max%-wait=(%d+)$")
            (tset r :retry-max-wait
                  (tonumber (a:match "^%-%-retry%-max%-wait=(%d+)$")))
            (a:match "^%-%-max%-pages=(%d+)$")
            (tset r :max-pages (tonumber (a:match "^%-%-max%-pages=(%d+)$")))
            (= a :--no-paginate)
            (tset r :no-paginate true)
            (= a :--retry-unsafe)
            (tset r :retry-unsafe true)
            (a:match "^%-%-timeout=(.+)")
            (let [(v) (a:match "^%-%-timeout=(.+)")]
              (tset r :timeout (tonumber v)))
            (a:match "^%-%-base%-url=(.+)")
            (let [(v) (a:match "^%-%-base%-url=(.+)")]
              (tset r :base-url v))
            (a:match "^%-%-output=(.+)")
            (let [(v) (a:match "^%-%-output=(.+)")]
              (tset r :output v))
            (= a :--list)
            (tset r :list true)
            (= a :--help)
            (tset r :help true)
            (= a :--no-color)
            (tset r :no-color true)
            (= a :--reload)
            (tset r :reload true)
            (= a :--dry-run)
            (tset r :dry-run true)
            (= a :--curl)
            (tset r :curl true)
            (a:match "^%-%-server%-index=(%d+)$")
            (tset r :server-index
                  (tonumber (a:match "^%-%-server%-index=(%d+)$")))
            (= a :--servers)
            (tset r :servers true)
            (= a :--no-validate)
            (tset r :no-validate true)
            (= a :--ignore-status)
            (tset r :ignore-status true)
            (= a :--logout)
            (tset r :logout true)
            (or (= a :-v) (= a :--verbose))
            (tset r :verbose true)
            (a:match "^%-%-cache%-ttl=(.+)")
            (let [(v) (a:match "^%-%-cache%-ttl=(.+)")]
              (tset r :cache-ttl (tonumber v)))
            (a:match "^%-%-select=(.+)")
            (let [(v) (a:match "^%-%-select=(.+)")]
              (tset r :select v))
            (= a :-i)
            (let [kv (value-after a i)
                  (k v) (kv:match "^(.-)=(.*)")]
              (assert k (.. "invalid -i argument (expected KEY=VAL): "
                            (tostring kv)))
              (table.insert r.input-fields [k v])
              (set i (+ i 1)))
            (a:match "^%-i(.-)=(.*)")
            (let [(k v) (a:match "^%-i(.-)=(.*)")]
              (table.insert r.input-fields [k v]))
            (a:match "^%-%-inputs=(.*)")
            (let [(v) (a:match "^%-%-inputs=(.*)")]
              (tset r :arazzo-inputs-blob (decode-structured (read-body v))))
            (a:match "^%-%-arazzo%-output=(.+)")
            (let [(v) (a:match "^%-%-arazzo%-output=(.+)")]
              (tset r :arazzo-output v))
            (a:match "^%-%-max%-gotos=(%d+)$")
            (tset r :max-gotos (tonumber (a:match "^%-%-max%-gotos=(%d+)$")))
            (a:match "^%-%-profile=(.+)")
            (let [(v) (a:match "^%-%-profile=(.+)")]
              (tset r :profile v))
            (not (a:match "^%-"))
            (positional a)
            (error (.. "unknown option: " a) 0)))
      (set i (+ i 1)))
    r))

{: field-prefixes : field-arg : parse-args}
