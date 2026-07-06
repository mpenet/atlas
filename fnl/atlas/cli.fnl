(local atlas (require :atlas))
(local arazzo (require :atlas.arazzo))
(local auth (require :atlas.auth))
(local cache (require :atlas.cache))
(local http-mod (require :atlas.http))
(local json (require :lunajson))
(local pretty-mod (require :atlas.pretty))
(local socket (require :socket))

(fn config-path []
  (.. (or (os.getenv :HOME) ".") "/.config/atlas/config.json"))

(fn load-config []
  (let [f (io.open (config-path) :r)]
    (if f
        (let [(ok cfg) (pcall json.decode (f:read :*a))]
          (f:close)
          (if ok cfg (error (.. "corrupt config: " (config-path)))))
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

(fn merge-profiles [base child]
  (let [result (collect [k v (pairs base)] k v)]
    (each [k v (pairs child)]
      (if (and (= k :headers) (= (type v) :table) (= (type (. result k)) :table))
          (let [merged (collect [hk hv (pairs (. result k))] hk hv)]
            (each [hk hv (pairs v)] (tset merged hk hv))
            (tset result k merged))
          (tset result k v)))
    result))

(fn resolve-profile [name profiles ?seen]
  (let [seen (or ?seen {})
        p (. profiles name)]
    (assert p (.. "Profile not found: " name))
    (assert (not (. seen name)) (.. "Circular extends: " name))
    (tset seen name true)
    (if p.extends
        (let [base (resolve-profile p.extends profiles seen)
              child (collect [k v (pairs p)] k v)]
          (tset child :extends nil)
          (merge-profiles base child))
        p)))

(fn coerce [s]
  (or (tonumber s) s))

(fn wrap-log-request [http-fn]
  (fn [req]
    (io.stderr:write (.. "> " (or req.method "?") " " (or req.url "?") "\n"))
    (when req.body
      (io.stderr:write (.. "> body: "
                           (if (= (type req.body) :table)
                               (json.encode req.body)
                               (tostring req.body))
                           "\n")))
    (when (and req.headers (next req.headers))
      (each [k v (pairs req.headers)]
        (io.stderr:write (.. "> " k ": " (tostring v) "\n"))))
    (http-fn req)))

(fn set-nested [t path v]
  (let [keys []]
    (each [k (path:gmatch "[^.]+")]
      (table.insert keys k))
    (var cur t)
    (for [i 1 (- (length keys) 1)]
      (let [k (. keys i)]
        (when (not (. cur k)) (tset cur k {}))
        (set cur (. cur k))))
    (tset cur (. keys (length keys)) v)))

(fn parse-args [args]
  (let [r {:path-params [] :query {} :headers {} :ssl {} :body-params {}
           :arazzo-inputs {}}]
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

          (a:match "^%-%-body%.(.-)=(.+)")
          (let [(k v) (a:match "^%-%-body%.(.-)=(.+)")]
            (set-nested r.body-params k (coerce v)))

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

          (= a :--list) (tset r :list true)
          (= a :--help) (tset r :help true)
          (= a :--no-color) (tset r :no-color true)
          (= a :--reload) (tset r :reload true)
          (= a :--logout) (tset r :logout true)
          (or (= a :-v) (= a :--verbose)) (tset r :verbose true)

          (a:match "^%-%-cache%-ttl=(.+)")
          (let [(v) (a:match "^%-%-cache%-ttl=(.+)")]
            (tset r :cache-ttl (tonumber v)))
          (a:match "^%-%-complete%-ops=(.+)")
          (let [(v) (a:match "^%-%-complete%-ops=(.+)")]
            (tset r :complete-ops v))

          (a:match "^%-%-select=(.+)")
          (let [(v) (a:match "^%-%-select=(.+)")]
            (tset r :select v))

          (a:match "^%-%-input%.(.-)=(.+)")
          (let [(k v) (a:match "^%-%-input%.(.-)=(.+)")]
            (tset r.arazzo-inputs k (coerce v)))

          (= a :-i)
          (do (set i (+ i 1))
              (let [kv (. args i)
                    (k v) (kv:match "^(.-)=(.+)")]
                (assert k (.. "invalid -i argument (expected KEY=VAL): " (tostring kv)))
                (tset r.arazzo-inputs k (coerce v))))

          (a:match "^%-i(.-)=(.+)")
          (let [(k v) (a:match "^%-i(.-)=(.+)")]
            (tset r.arazzo-inputs k (coerce v)))

          (a:match "^%-%-inputs=(.*)")
          (let [(v) (a:match "^%-%-inputs=(.*)")]
            (tset r :arazzo-inputs-blob (read-body v)))

          (a:match "^%-%-arazzo%-output=(.+)")
          (let [(v) (a:match "^%-%-arazzo%-output=(.+)")]
            (tset r :arazzo-output v))

          (a:match "^%-%-profile=(.+)")
          (let [(v) (a:match "^%-%-profile=(.+)")]
            (tset r :profile v))

          (not (a:match "^%-"))
          (if (not r.schema) (tset r :schema a)
              (not r.operation) (tset r :operation a)
              (table.insert r.path-params a))))
      (set i (+ i 1)))
    r))

(fn op? [v]
  (and (= (type v) :table) (~= nil (. v :has-body?))))

(fn list-ops [c]
  (let [ops []]
    (each [k v (pairs c)]
      (when (op? v)
        (table.insert ops {:k k :summary (. v :summary)})))
    (table.sort ops (fn [a b] (< a.k b.k)))
    (let [width (accumulate [w 0 _ op (ipairs ops)]
                  (math.max w (length op.k)))]
      (each [_ op (ipairs ops)]
        (print (if op.summary
                   (string.format (.. "%-" width "s  %s") op.k op.summary)
                   op.k))))))

(fn select-path [data path]
  (var cur data)
  (var i 1)
  (let [n (length path)]
    (while (and cur (<= i n))
      (let [c (path:sub i i)]
        (if (= c :.)
            (set i (+ i 1))
            (= c "[")
            (let [(j-iter) (path:match "^%[%]()" i)]
              (if j-iter
                  (let [rest (path:sub j-iter)
                        result []]
                    (when (= (type cur) :table)
                      (each [_ v (ipairs cur)]
                        (table.insert result
                          (if (> (length rest) 0) (select-path v rest) v))))
                    (set cur result)
                    (set i (+ n 1)))
                  (let [(idx j) (path:match "^%[(%d+)%]()" i)]
                    (if idx
                        (do (set cur (. cur (+ 1 (tonumber idx))))
                            (set i j))
                        (do (set cur nil) (set i (+ n 1)))))))
            (= c "{")
            (let [(fields-str j) (path:match "^{([^}]+)}()" i)]
              (if fields-str
                  (let [fields []
                        rest (path:sub j)
                        apply (fn [obj]
                                (if (= (type obj) :table)
                                    (let [out {}]
                                      (each [_ f (ipairs fields)]
                                        (tset out f (. obj f)))
                                      (if (> (length rest) 0) (select-path out rest) out))
                                    obj))]
                    (each [f (fields-str:gmatch "[^,]+")]
                      (table.insert fields (f:match "^%s*(.-)%s*$")))
                    (if (= (type cur) :table)
                        (let [is-arr (= (type (. cur 1)) :table)]
                          (if is-arr
                              (let [result []]
                                (each [_ v (ipairs cur)]
                                  (table.insert result (apply v)))
                                (set cur result))
                              (set cur (apply cur))))
                        (set cur nil))
                    (set i (+ n 1)))
                  (do (set cur nil) (set i (+ n 1)))))
            (let [(key j) (path:match "^([^%.%[{]+)()" i)]
              (if key
                  (do (set cur (. cur key)) (set i j))
                  (do (set cur nil) (set i (+ n 1)))))))))
  cur)

(fn print-resp [resp output no-color verbose ?select ?elapsed]
  (let [error? (and resp.status (>= resp.status 400))
        body (if (and (not error?) ?select resp.body)
                 (select-path resp.body ?select)
                 resp.body)
        timing (if ?elapsed (.. "  " (string.format "%.3fs" ?elapsed)) "")]
    (if error?
        (do
          (io.stderr:write (.. "HTTP " resp.status timing "\n"))
          (when verbose
            (each [k v (pairs (or resp.headers {}))]
              (io.stderr:write (.. k ": " v "\n")))
            (io.stderr:write "\n"))
          (when resp.body
            (io.stderr:write (.. (pretty-mod.pretty resp.body 0 (not no-color)) "\n")))
          (os.exit 1))
        (do
          (when verbose
            (print (.. "HTTP " resp.status timing))
            (each [k v (pairs (or resp.headers {}))]
              (print (.. k ": " v)))
            (print ""))
          (match (or output :json)
            :raw     (print (tostring body))
            :status  (print resp.status)
            :headers (each [k v (pairs (or resp.headers {}))]
                       (print (.. k ": " v)))
            :yaml    (if body
                         (let [rendered (pretty-mod.yaml body 0 (not no-color))]
                           (print (if (rendered:match "^\n") (rendered:sub 2) rendered)))
                         (when (not verbose)
                           (io.stderr:write (.. "HTTP " resp.status "\n"))))
            _ (if body
                  (print (pretty-mod.pretty body 0 (not no-color)))
                  (when (not verbose)
                    (io.stderr:write (.. "HTTP " resp.status "\n")))))))))

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
  (let [profiles (or (?. config :profiles) {})
        p (when (. profiles name) (resolve-profile name profiles {}))]
    (if p
        (print (pretty-mod.pretty p 0 true))
        (die (.. "Profile not found: " name)))))

(fn run-profile [subcmd name config]
  (match subcmd
    :list (profile-list config)
    :show (profile-show config name)
    _ (die (.. "Unknown profile subcommand: " (tostring subcmd)
                     "\nUsage: atlas profile <list|show> [name]"))))

(fn complete-ops [schema-or-profile]
  (let [config   (load-config)
        profiles (or (?. config :profiles) {})
        profile  (when (. profiles schema-or-profile)
                   (resolve-profile schema-or-profile profiles {}))
        schema   (or (?. profile :schema) schema-or-profile)
        opts     {:headers (or (?. profile :headers) {})}
        (ok c)   (pcall atlas.client schema opts)]
    (when ok
      (each [k v (pairs c)]
        (when (op? v) (print k))))))

(fn completion-fish []
  (print "# atlas fish completion — source this or put in ~/.config/fish/completions/atlas.fish")
  (print "")
  (print "complete -c atlas -f")
  (print "")
  (print "# count non-flag positional args before cursor")
  (print "function __atlas_num_args")
  (print "    set -l n 0")
  (print "    for t in (commandline -opc)[2..]")
  (print "        string match -qr '^-' -- $t; or set n (math $n + 1)")
  (print "    end")
  (print "    echo $n")
  (print "end")
  (print "")
  (print "# ── first positional ─────────────────────────────────────────────────────────")
  (print "complete -c atlas -n 'test (__atlas_num_args) -eq 0' -a '(atlas profile list 2>/dev/null | cut -f1)' -d Profile")
  (print "complete -c atlas -n 'test (__atlas_num_args) -eq 0' -a profile    -d 'Manage profiles'")
  (print "complete -c atlas -n 'test (__atlas_num_args) -eq 0' -a auth       -d 'Authenticate a profile'")
  (print "complete -c atlas -n 'test (__atlas_num_args) -eq 0' -a completion -d 'Print shell completion script'")
  (print "")
  (print "# ── profile subcommands ──────────────────────────────────────────────────────")
  (print "complete -c atlas -n '__fish_seen_subcommand_from profile; and test (__atlas_num_args) -eq 1' -a list -d 'List profiles'")
  (print "complete -c atlas -n '__fish_seen_subcommand_from profile; and test (__atlas_num_args) -eq 1' -a show -d 'Show resolved profile'")
  (print "complete -c atlas -n '__fish_seen_subcommand_from profile; and __fish_seen_subcommand_from show' -a '(atlas profile list 2>/dev/null | cut -f1)'")
  (print "")
  (print "# ── auth <profile> ───────────────────────────────────────────────────────────")
  (print "complete -c atlas -n '__fish_seen_subcommand_from auth; and test (__atlas_num_args) -eq 1' -a '(atlas profile list 2>/dev/null | cut -f1)'")
  (print "")
  (print "# ── completion <shell> ───────────────────────────────────────────────────────")
  (print "complete -c atlas -n '__fish_seen_subcommand_from completion; and test (__atlas_num_args) -eq 1' -a 'fish bash zsh'")
  (print "")
  (print "# ── operation names (second positional, non-special first arg) ───────────────")
  (print "complete -c atlas -n 'not __fish_seen_subcommand_from profile auth completion; and test (__atlas_num_args) -eq 1' -a '(atlas --complete-ops=(commandline -opc)[2] 2>/dev/null)'")
  (print "")
  (print "# ── flags ────────────────────────────────────────────────────────────────────")
  (print "complete -c atlas -l list      -d 'List all operations'")
  (print "complete -c atlas -l help      -d 'Show operation documentation'")
  (print "complete -c atlas -l no-color  -d 'Disable colored output'")
  (print "complete -c atlas -s v -l verbose -d 'Show status and response headers'")
  (print "complete -c atlas -l reload    -d 'Re-fetch and re-cache the schema'")
  (print "complete -c atlas -l output    -r -d 'Output format' -a 'json yaml raw status headers'")
  (print "complete -c atlas -l select    -r -d 'Select nested value (.items[0].name)'")
  (print "complete -c atlas -l timeout   -r -d 'Timeout in seconds'")
  (print "complete -c atlas -l cache-ttl -r -d 'Schema cache TTL in seconds'")
  (print "complete -c atlas -l base-url  -r -d 'Override base URL'")
  (print "complete -c atlas -l body      -r -d 'Request body (JSON, @file, @-)'")
  (print "complete -c atlas -s d         -r -d 'Request body (JSON, @file, @-)'")
  (print "complete -c atlas -l logout    -d 'Clear cached token (for auth subcommand)'"))

(fn completion-bash []
  (print "# atlas bash completion — add to ~/.bashrc: source <(atlas completion bash)")
  (print "_atlas_complete() {")
  (print "  local cur=\"${COMP_WORDS[COMP_CWORD]}\"")
  (print "  local first=\"${COMP_WORDS[1]}\"")
  (print "  local second=\"${COMP_WORDS[2]}\"")
  (print "  if [ $COMP_CWORD -eq 1 ]; then")
  (print "    local profiles=$(atlas profile list 2>/dev/null | cut -f1)")
  (print "    COMPREPLY=($(compgen -W \"$profiles profile auth completion\" -- \"$cur\"))")
  (print "  elif [ $COMP_CWORD -eq 2 ]; then")
  (print "    case \"$first\" in")
  (print "      profile)    COMPREPLY=($(compgen -W 'list show' -- \"$cur\")) ;;")
  (print "      auth)       COMPREPLY=($(compgen -W \"$(atlas profile list 2>/dev/null | cut -f1)\" -- \"$cur\")) ;;")
  (print "      completion) COMPREPLY=($(compgen -W 'fish bash zsh' -- \"$cur\")) ;;")
  (print "      *)          COMPREPLY=($(compgen -W \"$(atlas --complete-ops=$first 2>/dev/null)\" -- \"$cur\")) ;;")
  (print "    esac")
  (print "  elif [ $COMP_CWORD -eq 3 ] && [ \"$first\" = 'profile' ] && [ \"$second\" = 'show' ]; then")
  (print "    COMPREPLY=($(compgen -W \"$(atlas profile list 2>/dev/null | cut -f1)\" -- \"$cur\"))")
  (print "  fi")
  (print "}")
  (print "complete -F _atlas_complete atlas"))

(fn completion-zsh []
  (print "# atlas zsh completion — add to fpath or source directly")
  (print "#compdef atlas")
  (print "_atlas() {")
  (print "  local state first=${words[2]}")
  (print "  _arguments '1:schema-or-profile:->first' '2:arg:->second' '3:name:->third'")
  (print "  case $state in")
  (print "    first)")
  (print "      local profiles=($(atlas profile list 2>/dev/null | cut -f1))")
  (print "      compadd $profiles profile auth completion ;;")
  (print "    second)")
  (print "      case $first in")
  (print "        profile)    compadd list show ;;")
  (print "        auth)       compadd $(atlas profile list 2>/dev/null | cut -f1) ;;")
  (print "        completion) compadd fish bash zsh ;;")
  (print "        *)          compadd $(atlas --complete-ops=$first 2>/dev/null) ;;")
  (print "      esac ;;")
  (print "    third)")
  (print "      if [ \"${words[2]}\" = 'profile' ] && [ \"${words[3]}\" = 'show' ]; then")
  (print "        compadd $(atlas profile list 2>/dev/null | cut -f1)")
  (print "      fi ;;")
  (print "  esac")
  (print "}")
  (print "_atlas"))

(fn usage []
  (print "Usage: atlas <schema-or-profile> [operation] [path-params...] [options]")
  (print "       atlas profile <list|show> [name]")
  (print "       atlas auth <profile> [--logout]")
  (print "       atlas arazzo <name-or-file> <workflow-id> [path-params...] [options]")
  (print "       atlas completion <fish|bash|zsh>")
  (print "")
  (print "Options:")
  (print "  --list                List all operations")
  (print "  --help                Show operation documentation")
  (print "  --body=JSON           Request body (inline JSON, @file, @-)")
  (print "  -d JSON               Alias for --body")
  (print "  --body.KEY=VAL        Build request body from individual fields")
  (print "  --query.KEY=VAL       Query parameter")
  (print "  --header.KEY=VAL      Per-request header")
  (print "  --timeout=N           Timeout in seconds")
  (print "  --base-url=URL        Override base URL")
  (print "  --output=json|yaml|raw|status|headers  Output format (default: json)")
  (print "  --select=PATH         Select nested value (e.g. .items[0].name, .items[].{id,name})")
  (print "  --no-color            Disable colored output")
  (print "  -v, --verbose         Show status and response headers")
  (print "  --reload              Re-fetch and re-cache the schema")
  (print "  --cache-ttl=N         Schema cache TTL in seconds (default: 3600)")
  (print "")
  (print "Auth options (for 'atlas auth <profile>'):")
  (print "  --logout              Clear cached token")
  (print "")
  (print "Arazzo options (for 'atlas arazzo <name-or-file> <workflow-id>'):")
  (print "  -i KEY=VAL            Workflow input (short form)")
  (print "  --input.KEY=VAL       Workflow input (long form)")
  (print "  --inputs=JSON         All inputs as a JSON object (or @file)")
  (print "  --arazzo-output=MODE  final (default), steps, progress, full")
  (print "")
  (print "Config: ~/.config/atlas/config.json"))

(fn tls->ssl [tls]
  (when tls
    (let [ssl {}]
      (when tls.cert (tset ssl :certificate tls.cert))
      (when tls.key (tset ssl :key tls.key))
      (when tls.insecure (tset ssl :verify "none"))
      (when (next ssl) ssl))))

(fn merge-ssl [profile cli-ssl]
  (let [ssl (collect [k v (pairs (or (?. profile :ssl) {}))] k v)
        tls (tls->ssl (?. profile :tls))]
    (when tls (each [k v (pairs tls)] (tset ssl k v)))
    (when cli-ssl (each [k v (pairs cli-ssl)] (tset ssl k v)))
    ssl))

(fn run-auth [profile-name p config]
  (assert profile-name "Usage: atlas auth <profile> [--logout]")
  (let [profiles (or (?. config :profiles) {})
        profile  (when (. profiles profile-name)
                   (resolve-profile profile-name profiles {}))]
    (assert profile (.. "Profile not found: " profile-name))
    (let [auth-cfg (?. profile :auth)]
      (assert (and auth-cfg auth-cfg.name (not= auth-cfg.name ""))
              (.. "No auth configured for profile: " profile-name))
      (let [ssl (merge-ssl profile p.ssl)]
        (if (= auth-cfg.name "external-tool")
            (let [(ok headers) (pcall auth.get-headers profile-name auth-cfg ssl)]
              (if ok
                  (each [k v (pairs headers)]
                    (print (.. k ": " v)))
                  (die (tostring headers))))
            p.logout
            (do (auth.clear-token profile-name)
                (print (.. "Logged out: " profile-name)))
            (do (auth.clear-token profile-name)
                (let [(ok result) (pcall auth.get-headers profile-name auth-cfg ssl)]
                  (if ok
                      (print (.. "Authenticated: " profile-name))
                      (die (tostring result))))))))))

(fn print-arazzo-result [result mode output no-color]
  (let [fmt (or output :json)
        render (fn [v]
                 (match fmt
                   :yaml (let [s (pretty-mod.yaml v 0 (not no-color))]
                           (if (s:match "^\n") (s:sub 2) s))
                   _     (pretty-mod.pretty v 0 (not no-color))))]
    (match (or mode :final)
      :final
      (when (next (or result.outputs {}))
        (print (render result.outputs)))

      :steps
      (do
        (let [ordered (icollect [id _ (pairs result.steps)] id)]
          (table.sort ordered)
          (each [_ step-id (ipairs ordered)]
            (let [step (. result.steps step-id)]
              (print (.. "--- " step-id " ---"))
              (when step.response
                (print (render step.response.body))))))
        (when (next (or result.outputs {}))
          (print "--- outputs ---")
          (print (render result.outputs))))

      :progress
      ;; progress is printed live via on-step; print outputs at end
      (when (next (or result.outputs {}))
        (print (render result.outputs)))

      :full
      (do
        (let [ordered (icollect [id _ (pairs result.steps)] id)]
          (table.sort ordered)
          (each [_ step-id (ipairs ordered)]
            (let [step (. result.steps step-id)]
              (print (.. "--- " step-id " request ---"))
              (when step.op-ref (print (.. "operation: " step.op-ref)))
              (when (and step.request step.request.body)
                (print (render step.request.body)))
              (print (.. "--- " step-id " response"
                         (if (and step.response step.response.status)
                             (.. " HTTP " step.response.status) "")
                         " ---"))
              (when step.response (print (render step.response.body))))))
        (when (next (or result.outputs {}))
          (print "--- outputs ---")
          (print (render result.outputs)))))))

(fn list-arazzo-workflows [doc]
  (let [wfs (or doc.workflows [])]
    (when (= (length wfs) 0)
      (print "(no workflows)"))
    (let [width (accumulate [w 0 _ wf (ipairs wfs)]
                  (math.max w (length wf.workflowId)))]
      (each [_ wf (ipairs wfs)]
        (print (if wf.summary
                   (string.format (.. "%-" width "s  %s") wf.workflowId wf.summary)
                   wf.workflowId))))))

(fn workflow-path-param-names [wf]
  "Return ordered list of input names that are path params in any step."
  (let [seen {} names []]
    (each [_ step (ipairs (or wf.steps []))]
      (each [_ param (ipairs (or step.parameters []))]
        (when (= param.in :path)
          (let [input-name (and (= (type param.value) :string)
                                (param.value:match "^%$inputs%.(.+)$"))]
            (when (and input-name (not (. seen input-name)))
              (tset seen input-name true)
              (table.insert names input-name))))))
    names))

(fn run-arazzo [p]
  (let [name-or-file p.operation
        workflow-id  (. p.path-params 1)]
    (assert name-or-file "Usage: atlas arazzo <name-or-file> [<workflow-id>] [-i KEY=VAL ...] [--inputs=JSON]")
    (let [config   (load-config)
          named    (?. config :arazzo name-or-file)
          file     (if named named.file name-or-file)
          profiles (or (?. config :profiles) {})
          profile-name (or p.profile (?. named :profile))
          profile  (when (and profile-name (. profiles profile-name))
                     (resolve-profile profile-name profiles {}))
          (ok doc) (pcall arazzo.load-doc file)]
      (assert ok (tostring doc))
      (if (not workflow-id)
          (list-arazzo-workflows doc)
          (let [wf       (accumulate [found nil _ w (ipairs (or doc.workflows []))]
                           (if (= w.workflowId workflow-id) w found))
                pp-names (if wf (workflow-path-param-names wf) [])
                inputs   (let [base (collect [k v (pairs (or (?. named :inputs) {}))] k v)]
                           ;; positional args -> path params
                           (each [j name (ipairs pp-names)]
                             (let [v (. p.path-params (+ j 1))]
                               (when v (tset base name v))))
                           (each [k v (pairs (or p.arazzo-inputs-blob {}))]
                             (tset base k v))
                           (each [k v (pairs p.arazzo-inputs)]
                             (tset base k v))
                           ;; body-params merge flat into inputs so $inputs.key works
                           (each [k v (pairs (or p.body-params {}))]
                             (tset base k v))
                           (when (and p.body (= (type p.body) :table))
                             (each [k v (pairs p.body)]
                               (tset base k v)))
                           base)
                mode     (or p.arazzo-output (if p.verbose :progress :final))
                no-color (or p.no-color (?. config :no-color))
                output   (or p.output (?. config :output))
                ssl      (merge-ssl profile p.ssl)
                auth-cfg (let [a (?. profile :auth)]
                           (when (and a a.name (not= a.name "")) a))
                run-opts (let [o {:on-step nil
                                  :timeout (or p.timeout (?. profile :timeout))
                                  :ssl     ssl}]
                           (let [base-fn (if p.verbose
                                             (wrap-log-request http-mod.request)
                                             http-mod.request)
                                 wrapped (when auth-cfg (auth.wrap-http-fn auth-cfg base-fn))]
                             (tset o :http-fn (or wrapped (when p.verbose base-fn))))
                           (when (?. profile :base-url)
                             (tset o :base-url (?. profile :base-url)))
                           o)
                use-color (not no-color)
                dim    (fn [s] (if use-color (.. "\27[2m" s "\27[0m") s))
                green  (fn [s] (if use-color (.. "\27[32m" s "\27[0m") s))
                red    (fn [s] (if use-color (.. "\27[31m" s "\27[0m") s))
                on-step  (when (or (= mode :progress) (= mode :full))
                           (let [fmt    (or output :json)
                                 render (fn [v]
                                          (match fmt
                                            :yaml (let [s (pretty-mod.yaml v 0 use-color)]
                                                    (if (s:match "^\n") (s:sub 2) s))
                                            _ (pretty-mod.pretty v 0 use-color)))]
                             (fn [info]
                               (match info.status
                                 :running (io.stderr:write (.. (dim "→") " " info.step "\n"))
                                 :done
                                 (do
                                   (io.stderr:write
                                     (.. (green "✓") " " info.step
                                         (if info.elapsed
                                             (string.format "  %.3fs" info.elapsed) "")
                                         (if (and info.response info.response.status)
                                             (.. "  HTTP " info.response.status) "")
                                         "\n"))
                                   (when (and info.outputs (next info.outputs))
                                     (io.stderr:write (.. (render info.outputs) "\n"))))))))]
            (tset run-opts :on-step on-step)
            (let [t0      (socket.gettime)
                  clients (arazzo.build-clients doc run-opts)
                  (ok result) (pcall arazzo.run-workflow doc workflow-id inputs clients run-opts)
                  elapsed (- (socket.gettime) t0)]
              (when (or (= mode :progress) (= mode :full))
                (if ok
                    (io.stderr:write
                      (.. (green "✓") " workflow " workflow-id
                          (string.format "  %.3fs" elapsed) "\n"))
                    (io.stderr:write
                      (.. (red "✗") " workflow " workflow-id " failed"
                          (string.format "  %.3fs" elapsed) "\n"))))
              (if ok
                  (print-arazzo-result result mode output no-color)
                  (die (tostring result)))))))))

(fn load-schema-cached [url ttl reload? ssl headers]
  (let [cached (when (not reload?) (cache.get url ttl))]
    (if cached
        cached
        (let [schema (atlas.load-schema url ssl headers)]
          (cache.put url schema)
          schema))))

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
          :zsh (completion-zsh)
          _ (die "Usage: atlas completion <fish|bash|zsh>"))
        (= p.schema :profile)
        (run-profile p.operation (. p.path-params 1) (load-config))
        (= p.schema :auth)
        (run-auth p.operation p (load-config))
        (= p.schema :arazzo)
        (run-arazzo p)
        (let [config (load-config)
              profiles (or (?. config :profiles) {})
              profile (when (. profiles p.schema)
                        (resolve-profile p.schema profiles {}))
              raw-schema (or (?. profile :schema) p.schema)
              ttl (or p.cache-ttl (?. profile :cache-ttl) 3600)
              no-color (or p.no-color (?. profile :no-color) (?. config :no-color))
              output (or p.output (?. profile :output) (?. config :output))
              verbose (or p.verbose (?. profile :verbose) (?. config :verbose))
              timeout (or p.timeout (?. profile :timeout) (?. config :timeout))
              ssl (merge-ssl profile p.ssl)
              auth-cfg (let [a (?. profile :auth)]
                         (when (and a a.name (not= a.name "")) a))
              auth-headers (when auth-cfg
                             (let [(ok h) (pcall auth.get-headers p.schema auth-cfg ssl)]
                               (if ok h (die (.. "authentication failed: " (tostring h))))))
              schema (if (and (= (type raw-schema) :string)
                              (raw-schema:match "^https?://"))
                        (load-schema-cached raw-schema ttl p.reload ssl auth-headers)
                        raw-schema)
              opts {:headers (collect [k v (pairs (or (?. profile :headers) {}))] k v)
                    :timeout timeout
                    :ssl ssl}]
          (when auth-headers
            (each [k v (pairs auth-headers)]
              (tset opts.headers k v)))
          (let [base-fn (if p.verbose
                            (wrap-log-request http-mod.request)
                            http-mod.request)
                wrapped (when auth-cfg (auth.wrap-http-fn auth-cfg base-fn))]
            (tset opts :http-fn (or wrapped (when p.verbose base-fn))))
          (when (or p.base-url (?. profile :base-url))
            (tset opts :base-url (or p.base-url (?. profile :base-url))))
          (when (= (type schema) :table)
            (tset opts :source-url raw-schema))
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
                    (print (or (. op :cli/help) "No documentation available."))
                    (die (.. "Unknown operation: " p.operation))))

              p.operation
              (let [op (. c p.operation)]
                (when (not op) (die (.. "Unknown operation: " p.operation)))
                (let [path-args (icollect [_ v (ipairs p.path-params)] (coerce v))
                      call-args (icollect [_ v (ipairs path-args)] v)
                      req-opts (let [o {}]
                                 (when (next p.query) (tset o :query p.query))
                                 (when (next p.headers) (tset o :headers p.headers))
                                 (when timeout (tset o :timeout timeout))
                                 (when (next o) o))]
                  (when op.has-body?
                    (let [body (if (and (not p.body) (next p.body-params))
                                   p.body-params
                                   p.body)]
                      (table.insert call-args body)))
                  (when req-opts (table.insert call-args req-opts))
                  (let [t0 (socket.gettime)
                        (ok-r resp) (pcall op (table.unpack call-args))
                        elapsed (- (socket.gettime) t0)]
                    (if ok-r
                        (print-resp resp output no-color verbose p.select elapsed)
                        (die (.. "request failed: " (tostring resp)))))))

              (die "No operation specified. Use --list to see available operations.")))))))

(fn main [args]
  (let [(ok err) (pcall run args)]
    (when (not ok) (die (tostring err)))))

{: main}
