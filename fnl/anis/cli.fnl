(local anis (require :anis))
(local json (require :lunajson))
(local pretty-mod (require :anis.pretty))

(fn config-path []
  (.. (or (os.getenv :HOME) ".") "/.config/anis/config.json"))

(fn load-config []
  (let [f (io.open (config-path) :r)]
    (if f
        (let [cfg (json.decode (f:read :*a))]
          (f:close)
          cfg)
        {})))

(fn parse-args [args]
  (let [r {:path-params [] :query {} :headers {}}]
    (var i 1)
    (while (<= i (length args))
      (let [a (. args i)]
        (if
          (a:match "^%-%-query%.(.-)=(.+)")
          (let [(k v) (a:match "^%-%-query%.(.-)=(.+)")]
            (tset r.query k v))

          (a:match "^%-%-header%.(.-)=(.+)")
          (let [(k v) (a:match "^%-%-header%.(.-)=(.+)")]
            (tset r.headers k v))

          (a:match "^%-%-body=(.*)")
          (let [(v) (a:match "^%-%-body=(.*)")
                (ok parsed err) (pcall json.decode v)]
            (assert ok (.. "invalid JSON in --body: " (tostring err)))
            (tset r :body parsed))

          (= a :-d)
          (do (set i (+ i 1))
              (let [(ok parsed err) (pcall json.decode (. args i))]
                (assert ok (.. "invalid JSON in -d: " (tostring err)))
                (tset r :body parsed)))

          (a:match "^%-%-timeout=(.+)")
          (let [(v) (a:match "^%-%-timeout=(.+)")]
            (tset r :timeout (tonumber v)))

          (a:match "^%-%-base%-url=(.+)")
          (let [(v) (a:match "^%-%-base%-url=(.+)")]
            (tset r :base-url v))

          (a:match "^%-%-output=(.+)")
          (let [(v) (a:match "^%-%-output=(.+)")]
            (tset r :output v))

          (= a :--list)     (tset r :list true)
          (= a :--help)     (tset r :help true)
          (= a :--no-color) (tset r :no-color true)
          (or (= a :-v) (= a :--verbose)) (tset r :verbose true)

          (not (a:match "^%-"))
          (if (not r.schema)    (tset r :schema a)
              (not r.operation) (tset r :operation a)
              (table.insert r.path-params a))))
      (set i (+ i 1)))
    r))

(fn coerce [s]
  (or (tonumber s) s))

(fn op? [v]
  (and (= (type v) :table) (~= nil (. v :has-body?))))

(fn list-ops [c]
  (let [ops []]
    (each [k v (pairs c)]
      (when (op? v)
        (let [doc (. v :fnl/docstring)
              summary (when doc (doc:match "^([^\n]+)"))]
          (table.insert ops {: k : summary}))))
    (table.sort ops (fn [a b] (< a.k b.k)))
    (each [_ op (ipairs ops)]
      (print (.. op.k (if op.summary (.. "\t" op.summary) ""))))))

(fn print-resp [resp output no-color verbose]
  (when verbose
    (print (.. "HTTP " resp.status))
    (each [k v (pairs (or resp.headers {}))]
      (print (.. k ": " v)))
    (print ""))
  (match (or output :json)
    :raw    (print (tostring resp.body))
    :status (print resp.status)
    :headers (each [k v (pairs (or resp.headers {}))]
               (print (.. k ": " v)))
    _ (if resp.body
          (print (pretty-mod.pretty resp.body 0 (not no-color)))
          (when (not verbose)
            (io.stderr:write (.. "HTTP " resp.status "\n"))))))

(fn die [msg]
  (io.stderr:write (.. msg "\n"))
  (os.exit 1))

(fn usage []
  (print "Usage: anis <schema-or-profile> [operation] [path-params...] [options]")
  (print "")
  (print "Options:")
  (print "  --list                List all operations")
  (print "  --help                Show operation documentation")
  (print "  --body=JSON           Request body")
  (print "  -d JSON               Request body (alternative)")
  (print "  --query.KEY=VAL       Query parameter")
  (print "  --header.KEY=VAL      Per-request header")
  (print "  --timeout=N           Timeout in seconds")
  (print "  --base-url=URL        Override base URL")
  (print "  --output=json|raw|status|headers  Output format (default: json)")
  (print "  --no-color            Disable colored output")
  (print "  -v, --verbose         Show status and response headers")
  (print "")
  (print "Config: ~/.config/anis/config.json")
  (print "  { \"profiles\": { \"myapi\": { \"schema\": \"https://...\", \"headers\": {} } } }"))

(fn run [args]
  (let [p (parse-args args)]
    (when (not p.schema)
      (usage)
      (os.exit 0))
    (let [config  (load-config)
          profile (?. config :profiles p.schema)
          schema  (or (?. profile :schema) p.schema)
          opts    {:headers (or (?. profile :headers) {})
                   :timeout (or p.timeout (?. profile :timeout))
                   :ssl     (?. profile :ssl)}]
      (when (or p.base-url (?. profile :base-url))
        (tset opts :base-url (or p.base-url (?. profile :base-url))))
      (let [(ok-c c) (pcall anis.client schema opts)]
        (when (not ok-c) (die (.. "failed to build client: " (tostring c))))
        (if
          p.list
          (list-ops c)

          (and p.help (not p.operation))
          (list-ops c)

          p.help
          (let [op (. c p.operation)]
            (if op
                (print (or op.fnl/docstring "No documentation available."))
                (die (.. "Unknown operation: " p.operation))))

          p.operation
          (let [op (. c p.operation)]
            (when (not op) (die (.. "Unknown operation: " p.operation)))
            (let [path-args (icollect [_ v (ipairs p.path-params)] (coerce v))
                  call-args (icollect [_ v (ipairs path-args)] v)
                  req-opts  (let [o {}]
                              (when (next p.query)   (tset o :query p.query))
                              (when (next p.headers) (tset o :headers p.headers))
                              (when p.timeout        (tset o :timeout p.timeout))
                              (when (next o) o))]
              (when op.has-body? (table.insert call-args p.body))
              (when req-opts     (table.insert call-args req-opts))
              (let [(ok-r resp) (pcall op (table.unpack call-args))]
                (if ok-r
                    (print-resp resp p.output p.no-color p.verbose)
                    (die (.. "request failed: " (tostring resp)))))))

          (die "No operation specified. Use --list to see available operations."))))))

(fn main [args]
  (let [(ok err) (pcall run args)]
    (when (not ok) (die (tostring err)))))

{: main}
