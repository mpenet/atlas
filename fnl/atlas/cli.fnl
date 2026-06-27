(local atlas (require :atlas))
(local json (require :lunajson))
(local pretty-mod (require :atlas.pretty))

(fn config-path []
  (.. (or (os.getenv :HOME) ".") "/.config/atlas/config.json"))

(fn load-config []
  (let [f (io.open (config-path) :r)]
    (if f
        (let [cfg (json.decode (f:read :*a))]
          (f:close)
          cfg)
        {})))

(fn read-body [s]
  (let [raw (if (= s "@-")
                (io.read :*a)
                (let [(path) (s:match "^@(.+)")]
                  (if path
                      (let [f (assert (io.open path :r))
                            c (f:read :*a)]
                        (f:close) c)
                      s)))
        (ok parsed) (pcall json.decode raw)]
    (assert ok (.. "invalid JSON in body: " (tostring parsed)))
    parsed))

(fn save-config [cfg]
  (let [path (config-path)
        dir  (path:match "^(.+)/[^/]+$")]
    (os.execute (.. "mkdir -p " dir))
    (let [f (assert (io.open path :w))]
      (f:write (json.encode cfg))
      (f:close))))

(fn parse-args [args]
  (let [r {:path-params [] :query {} :headers {} :ssl {}}]
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

          (a:match "^%-%-ssl%.(.-)=(.+)")
          (let [(k v) (a:match "^%-%-ssl%.(.-)=(.+)")]
            (tset r.ssl k v))

          (a:match "^%-%-body=(.*)")
          (let [(v) (a:match "^%-%-body=(.*)")]
            (tset r :body (read-body v)))

          (= a :-d)
          (do (set i (+ i 1))
              (tset r :body (read-body (. args i))))

          (a:match "^%-%-schema=(.+)")
          (let [(v) (a:match "^%-%-schema=(.+)")]
            (tset r :schema-url v))

          (a:match "^%-%-timeout=(.+)")
          (let [(v) (a:match "^%-%-timeout=(.+)")]
            (tset r :timeout (tonumber v)))

          (a:match "^%-%-base%-url=(.+)")
          (let [(v) (a:match "^%-%-base%-url=(.+)")]
            (tset r :base-url v))

          (a:match "^%-%-output=(.+)")
          (let [(v) (a:match "^%-%-output=(.+)")]
            (tset r :output v))

          (= a :--list)          (tset r :list true)
          (= a :--help)          (tset r :help true)
          (= a :--no-color)      (tset r :no-color true)
          (or (= a :-v) (= a :--verbose)) (tset r :verbose true)
          (a:match "^%-%-complete%-ops=(.+)")
          (let [(v) (a:match "^%-%-complete%-ops=(.+)")]
            (tset r :complete-ops v))

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

(fn strip-location [msg]
  (let [s (tostring msg)
        (r) (s:gsub "[^%s:]+%.lua:%d+: " "")]
    r))

(fn die [msg]
  (io.stderr:write (.. (strip-location (tostring msg)) "\n"))
  (os.exit 1))

;; ---- profile subcommands ----

(fn profile-list [config]
  (let [profiles (or (?. config :profiles) {})]
    (if (= (next profiles) nil)
        (print "No profiles configured.")
        (each [name p (pairs profiles)]
          (print (.. name "\t" (or p.schema "(no schema)")))))))

(fn profile-show [config name]
  (let [p (?. config :profiles name)]
    (if p
        (print (pretty-mod.pretty p 0 true))
        (die (.. "Profile not found: " name)))))

(fn profile-add [config name p args]
  (assert name "profile name required")
  (assert (or p.schema-url (?. config :profiles name :schema))
          "profile add requires --schema=URL")
  (let [profiles (or config.profiles {})
        existing (or (. profiles name) {})
        updated  {:schema (or p.schema-url existing.schema)}]
    (when p.base-url (tset updated :base-url p.base-url))
    (when p.timeout  (tset updated :timeout p.timeout))
    (when (next p.headers) (tset updated :headers p.headers))
    (when (next p.ssl)     (tset updated :ssl p.ssl))
    (tset profiles name updated)
    (tset config :profiles profiles)
    (save-config config)
    (print (.. "Profile '" name "' saved."))))

(fn profile-remove [config name]
  (assert name "profile name required")
  (assert (?. config :profiles name) (.. "Profile not found: " name))
  (tset config.profiles name nil)
  (save-config config)
  (print (.. "Profile '" name "' removed.")))

(fn run-profile [subcmd name p config]
  (match subcmd
    :list   (profile-list config)
    :show   (profile-show config name)
    :add    (profile-add config name p nil)
    :remove (profile-remove config name)
    :rm     (profile-remove config name)
    _       (die (.. "Unknown profile subcommand: " (tostring subcmd)
                     "\nUsage: atlas profile <list|show|add|remove> [name] [options]"))))

(fn complete-ops [schema-or-profile]
  (let [config  (load-config)
        profile (?. config :profiles schema-or-profile)
        schema  (or (?. profile :schema) schema-or-profile)
        opts    {:headers (or (?. profile :headers) {})}
        (ok c)  (pcall atlas.client schema opts)]
    (when ok
      (each [k v (pairs c)]
        (when (op? v) (print k))))))

(fn completion-fish []
  (print "# atlas fish completion — source this or put in ~/.config/fish/completions/atlas.fish")
  (print "")
  (print "# disable file completion by default")
  (print "complete -c atlas -f")
  (print "")
  (print "# flags")
  (print "complete -c atlas -l list      -d 'List all operations'")
  (print "complete -c atlas -l help      -d 'Show operation documentation'")
  (print "complete -c atlas -l no-color  -d 'Disable colored output'")
  (print "complete -c atlas -s v -l verbose -d 'Show status and headers'")
  (print "complete -c atlas -l output    -d 'Output format' -r -a 'json raw status headers'")
  (print "complete -c atlas -l timeout   -d 'Timeout in seconds' -r")
  (print "complete -c atlas -l base-url  -d 'Override base URL' -r")
  (print "complete -c atlas -l body      -d 'Request body JSON' -r")
  (print "complete -c atlas -s d         -d 'Request body JSON' -r")
  (print "")
  (print "# profile names as first positional arg")
  (print "complete -c atlas -n '__fish_is_first_arg' -a '(atlas profile list 2>/dev/null | cut -f1)' -d 'Profile'")
  (print "complete -c atlas -n '__fish_is_first_arg' -a 'profile' -d 'Manage profiles'")
  (print "")
  (print "# operation names as second positional arg")
  (print "complete -c atlas -n 'not __fish_is_first_arg' -a '(atlas --complete-ops=(commandline -opc | string split \" \" -f2) 2>/dev/null)'")
  (print "")
  (print "# profile subcommands")
  (print "complete -c atlas -n '__fish_seen_subcommand_from profile' -a 'list show add remove' -d 'Profile subcommand'"))

(fn completion-bash []
  (print "# atlas bash completion — add to ~/.bashrc: source <(atlas completion bash)")
  (print "_atlas_complete() {")
  (print "  local cur=\"${COMP_WORDS[COMP_CWORD]}\"")
  (print "  local prev=\"${COMP_WORDS[COMP_CWORD-1]}\"")
  (print "  if [ $COMP_CWORD -eq 1 ]; then")
  (print "    COMPREPLY=($(compgen -W \"$(atlas profile list 2>/dev/null | cut -f1) profile\" -- \"$cur\"))")
  (print "  elif [ $COMP_CWORD -eq 2 ] && [ \"${COMP_WORDS[1]}\" != 'profile' ]; then")
  (print "    COMPREPLY=($(compgen -W \"$(atlas --complete-ops=${COMP_WORDS[1]} 2>/dev/null)\" -- \"$cur\"))")
  (print "  elif [ \"${COMP_WORDS[1]}\" = 'profile' ] && [ $COMP_CWORD -eq 2 ]; then")
  (print "    COMPREPLY=($(compgen -W 'list show add remove' -- \"$cur\"))")
  (print "  fi")
  (print "}")
  (print "complete -F _atlas_complete atlas"))

(fn completion-zsh []
  (print "# atlas zsh completion — add to fpath or source directly")
  (print "#compdef atlas")
  (print "_atlas() {")
  (print "  local state")
  (print "  _arguments '1:schema-or-profile:->profile' '2:operation:->operation'")
  (print "  case $state in")
  (print "    profile) compadd $(atlas profile list 2>/dev/null | cut -f1) profile ;;")
  (print "    operation) compadd $(atlas --complete-ops=${words[2]} 2>/dev/null) ;;")
  (print "  esac")
  (print "}")
  (print "_atlas"))

(fn usage []
  (print "Usage: atlas <schema-or-profile> [operation] [path-params...] [options]")
  (print "       atlas profile <list|show|add|remove> [name] [options]")
  (print "       atlas completion <fish|bash|zsh>")
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
  (print "Profile options (for 'atlas profile add'):")
  (print "  --schema=URL          Schema URL or file path")
  (print "  --base-url=URL        Override base URL")
  (print "  --header.KEY=VAL      Default request header")
  (print "  --timeout=N           Default timeout")
  (print "  --ssl.KEY=VAL         SSL options (cafile, verify, etc.)")
  (print "")
  (print "Config: ~/.config/atlas/config.json"))

(fn run [args]
  (let [p (parse-args args)]
    (when (not p.schema)
      (usage)
      (os.exit 0))
    (when p.complete-ops
      (complete-ops p.complete-ops)
      (os.exit 0))
    (if (= p.schema :completion)
        (match p.operation
          :fish (completion-fish)
          :bash (completion-bash)
          :zsh  (completion-zsh)
          _     (die "Usage: atlas completion <fish|bash|zsh>"))
        (= p.schema :profile)
        (run-profile p.operation (. p.path-params 1) p (load-config))
        (let [config  (load-config)
              profile (?. config :profiles p.schema)
              schema  (or (?. profile :schema) p.schema)
              opts    {:headers (or (?. profile :headers) {})
                       :timeout (or p.timeout (?. profile :timeout))
                       :ssl     (or (?. profile :ssl) {})}]
          (when (or p.base-url (?. profile :base-url))
            (tset opts :base-url (or p.base-url (?. profile :base-url))))
          (let [(ok-c c) (pcall atlas.client schema opts)]
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

              (die "No operation specified. Use --list to see available operations.")))))))

(fn main [args]
  (let [(ok err) (pcall run args)]
    (when (not ok) (die (tostring err)))))

{: main}
