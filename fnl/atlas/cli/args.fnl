;; ABOUTME: The CLI option table and the argument parser driven by it; the
;; ABOUTME: same table feeds usage text and shell completion.
(local {: read-body : decode-structured} (require :atlas.cli.request))

(local field-prefixes ;; --PREFIX.NAME=VALUE families, long and short forms
       {:query :query
        :q :query
        :header :header
        :h :header
        :body :body
        :b :body
        :input :input
        :i :input
        :server :server
        :ssl :ssl})

(local options ;; :names        spellings accepted on the command line
       ;; :key          where the value goes in the parsed table
       ;; :value        nil for switches, else :number, :string, :body or :inputs
       ;; :arg          placeholder for the value in usage (default N or VALUE)
       ;; :shown        how usage displays it, when the default form doesn't fit
       ;; :scope        :op, :az, :auth or :any
       ;; :also         other commands that take it
       ;; :explained    commands that refuse it with an explanation: parsed,
       ;;               but never offered
       ;; :family       a --PREFIX.NAME=VALUE family (its scope applies to all names)
       [{:names ["--list"] :key :list :scope :op :help "List all operations"}
        {:names ["--help"]
         :key :help
         :scope :any
         :also [:auth :profile]
         :help "Show documentation for an operation or workflow (or list them)"}
        {:names ["--body" "-d"]
         :key :body
         :value :body
         :shown "--body=JSON, -d JSON"
         :scope :any
         :help "Request body: inline JSON/YAML, @file or @- for stdin"}
        {:family "--b."
         :shown "--body.KEY=VAL"
         :scope :any
         :help "Body field, deep dot paths (short: --b.KEY=VAL)"}
        {:family "--q."
         :shown "--query.KEY=VAL"
         :scope :op
         :help "Query parameter; repeat for a list (short: --q.KEY=VAL)"}
        {:family "--h."
         :shown "--header.KEY=VAL"
         :scope :op
         :help "Request header (short: --h.KEY=VAL)"}
        {:names ["--timeout"]
         :key :timeout
         :value :number
         :scope :any
         :help "Timeout in seconds"}
        {:names ["--max-pages"]
         :key :max-pages
         :value :number
         :scope :op
         :help "Max pages to follow via Link rel=next (default: 25)"}
        {:names ["--no-paginate"]
         :key :no-paginate
         :scope :op
         :help "Return only the first page"}
        {:names ["--retry"]
         :key :retry
         :value :number
         :scope :any
         :help "Retries for 408/429/5xx and network errors (default: 2)"}
        {:names ["--retry-unsafe"]
         :key :retry-unsafe
         :scope :any
         :help "Also retry POST/PUT/PATCH/DELETE"}
        {:names ["--retry-max-wait"]
         :key :retry-max-wait
         :value :number
         :scope :any
         :help "Max seconds to wait between retries (default: 300)"}
        {:names ["--base-url"]
         :key :base-url
         :value :string
         :arg "URL"
         :scope :any
         :help "Override base URL"}
        {:names ["--servers"]
         :key :servers
         :scope :op
         :help "List the schema's servers and their variables"}
        {:names ["--server-index"]
         :key :server-index
         :value :number
         :scope :any
         :help "Use the schema's Nth server (default: 1)"}
        {:family "--server."
         :shown "--server.NAME=VAL"
         :scope :any
         :help "Set a server URL variable (e.g. --server.zone=de-fra-1)"}
        {:family "--ssl."
         :shown "--ssl.KEY=VAL"
         :scope :any
         :also [:auth]
         :help "TLS option: cafile, capath, certificate, key, verify (e.g. --ssl.verify=none)"}
        {:names ["--output"]
         :key :output
         :value :string
         :arg "FORMAT"
         :choices [:json :yaml :raw :status :headers]
         :scope :any
         :help "json (default), yaml, raw, status or headers"}
        {:names ["--select"]
         :key :select
         :value :string
         :arg "PATH"
         :scope :op
         :help "Select nested value (e.g. .items[0].name, .items[].{id,name})"}
        {:names ["--no-color"]
         :key :no-color
         :scope :any
         :help "Disable colored output"}
        {:names ["--verbose" "-v"]
         :key :verbose
         :shown "-v, --verbose"
         :scope :any
         :help "Show status, headers and requests"}
        {:names ["--reload"]
         :key :reload
         :scope :op
         :help "Re-fetch and re-cache the schema"}
        {:names ["--ignore-status"]
         :key :ignore-status
         :scope :op
         :help "Treat HTTP error responses as output; exit 0"}
        {:names ["--no-validate"]
         :key :no-validate
         :scope :any
         :help "Send even if required params are missing or the body or inputs are invalid"}
        {:names ["--dry-run"]
         :key :dry-run
         :scope :op
         :explained [:az :profile]
         :help "Print the request instead of sending it"}
        {:names ["--curl"]
         :key :curl
         :scope :op
         :explained [:az]
         :help "Print an equivalent curl command instead of sending"}
        {:names ["--cache-ttl"]
         :key :cache-ttl
         :value :number
         :scope :op
         :help "Schema cache TTL in seconds (default: 3600)"}
        {:names ["--profile"]
         :key :profile
         :value :string
         :arg "NAME"
         :scope :az
         :help "Profile for auth, TLS and headers"}
        {:names ["-i"]
         :value :input
         :shown "-i KEY=VAL"
         :scope :az
         :help "Workflow input"}
        {:family "--i."
         :shown "--input.KEY=VAL"
         :scope :az
         :help "Workflow input (short: --i.KEY=VAL)"}
        {:names ["--inputs"]
         :key :arazzo-inputs-blob
         :value :inputs
         :scope :az
         :help "All inputs as a JSON/YAML object (or @file)"}
        {:names ["--arazzo-output"]
         :key :arazzo-output
         :value :string
         :arg "MODE"
         :choices [:final :steps :progress :full]
         :scope :az
         :help "final (default), steps, progress, full"}
        {:names ["--max-gotos"]
         :key :max-gotos
         :value :number
         :scope :az
         :help "Max gotos to one step before aborting (default: 50)"}
        {:names ["--logout"]
         :key :logout
         :scope :auth
         :help "Clear the cached token instead of authenticating"}])

(local option-by-name (let [index {}]
                        (each [_ o (ipairs options)]
                          (each [_ n (ipairs (or o.names []))]
                            (tset index n o)))
                        index))

(fn field-arg [a]
  "For --PREFIX.KEY=VAL arguments with a known prefix (long or short form),
returns (kind key value); kind is a value of field-prefixes."
  (let [(prefix k v) (a:match "^%-%-(%a+)%.(.-)=(.*)$")
        kind (when prefix (. field-prefixes prefix))]
    (when kind
      (values kind k v))))

(local short-prefixes {:query "--q." :header "--h." :body "--b." :input "--i."})

(fn add-field [r kind k v]
  (when (= k "")
    (error (.. (or (. short-prefixes kind) (.. "--" kind "."))
               " needs a field name, as in " (or (. short-prefixes kind) "--")
               "NAME=VALUE") 0))
  (match kind
    :query (let [prev (. r.query k)]
             ;; repeating a parameter sends it several times
             (tset r.query k (if (= nil prev) v
                                 (= (type prev) :table) (doto prev
                                                          (table.insert v))
                                 [prev v])))
    :header
    (let [existing (accumulate [found nil name (pairs r.headers) &until found]
                     (when (= (name:lower) (k:lower)) name))]
      ;; repeated header names, in any case, are joined like HTTP does
      (if existing
          (tset r.headers existing (.. (. r.headers existing) ", " v))
          (tset r.headers k v)))
    :body (table.insert r.body-fields [k v])
    :input (table.insert r.input-fields [k v])
    :server (tset r.server-vars k v)
    :ssl (tset r.ssl k v)))

(fn option-value [name opt raw]
  (when (and opt.choices (not (accumulate [ok false _ c (ipairs opt.choices)
                                           &until ok]
                                (= c raw))))
    (error (.. name " must be one of " (table.concat opt.choices ", ")
               ", got '" raw "'") 0))
  (match opt.value
    :number
    (or (tonumber raw) (error (.. name " expects a number, got '" raw "'") 0))
    :body (read-body raw)
    :inputs (decode-structured (read-body raw))
    _ raw))

(fn accepted-elsewhere [opt]
  "Commands besides opt's :scope that the parser lets it through for."
  (let [commands (icollect [_ c (ipairs (or opt.also []))]
                   c)]
    (each [_ c (ipairs (or opt.explained []))]
      (table.insert commands c))
    commands))

(local command-scopes {:op :op
                       :az :az
                       :arazzo :az
                       :auth :auth
                       :profile :profile
                       :completion :completion})

;; the option entry of each --PREFIX.NAME=VALUE family, by field kind: its
;; :scope and :also say which commands take it
(local family-options (collect [_ o (ipairs options)]
                        (when o.family
                          (values (. field-prefixes
                                     (o.family:match "^%-%-(.-)%.$"))
                                  o))))

(fn check-scopes [cmd used]
  "Raise for an option that doesn't apply to command cmd; used is a list of
[name scope also]."
  (let [scope (. command-scopes (or cmd ""))]
    (when scope
      (each [_ [name opt-scope also] (ipairs used)]
        ;; :any is any API command: op and az
        (when (not (or (= opt-scope scope)
                       (and (= opt-scope :any) (or (= scope :op) (= scope :az)))
                       (accumulate [ok false _ s (ipairs (or also [])) &until ok]
                         (= s scope))))
          (error (.. name " doesn't apply to " cmd " (it is for "
                     (if (= opt-scope :any) "op and az" opt-scope) ")")
                 0))))))

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
        used []
        input-pair (fn [kv]
                     (let [(k v) (kv:match "^(.-)=(.*)$")]
                       (assert k (.. "invalid -i argument (expected KEY=VAL): "
                                     kv))
                       (add-field r :input k v)))]
    (var i 1)
    (var options-done false)
    (while (<= i (length args))
      (let [a (. args i)]
        (if options-done (positional a) (= a "--") (set options-done true)
            (not (a:match "^%-")) (positional a) (field-arg a)
            (let [(kind k v) (field-arg a)]
              (table.insert used
                            [(a:match "^(%-%-?[%w-]+%.?)")
                             (?. family-options kind :scope)
                             (?. family-options kind :also)])
              (add-field r kind k v)) ;; -iKEY=VAL, glued
            (a:match "^%-i.+=")
            (do
              (table.insert used ["-i" :az])
              (input-pair (a:sub 3)))
            (let [(name inline) (if (a:find "=" 1 true)
                                    (a:match "^([^=]+)=(.*)$")
                                    a)
                  opt (or (. option-by-name name)
                          (error (.. "unknown option: " a) 0))]
              (table.insert used [name opt.scope (accepted-elsewhere opt)])
              (if (not opt.value)
                  (if inline
                      (error (.. name " takes no value") 0)
                      (tset r opt.key true))
                  (let [raw (or inline
                                (do
                                  (set i (+ i 1))
                                  (or (. args i)
                                      (error (.. name " requires a value") 0))))]
                    (if (= opt.value :input)
                        (input-pair raw)
                        (tset r opt.key (option-value name opt raw))))))))
      (set i (+ i 1)))
    (check-scopes r.cmd used)
    r))

{: field-prefixes : field-arg : parse-args : options : option-by-name}
