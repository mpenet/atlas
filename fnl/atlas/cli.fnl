;; ABOUTME: The atlas command line: dispatches the op, az, auth, profile and
;; ABOUTME: completion subcommands; run returns the process exit code.
(local atlas (require :atlas))
(local arazzo (require :atlas.arazzo))
(local auth (require :atlas.auth))
(local cli-help (require :atlas.cli.help))
(local http-mod (require :atlas.http))
(local pretty-mod (require :atlas.pretty))
(local socket (require :socket))
(local util (require :atlas.util))
(local validate (require :atlas.validate))
(local {: decode-structured
        : build-body
        : op-request
        : check-params
        : check-body} (require :atlas.cli.request))

(local {: parse-args} (require :atlas.cli.args))
(local restish (require :atlas.cli.restish))
(local json (require :atlas.json))
(local {: list-ops
        : render
        : print-resp
        : die
        : exit
        : exit-status
        : format-servers
        : print-arazzo-result
        : list-arazzo-workflows
        : wrap-log-request} (require :atlas.cli.output))

(local {: config-path
        : load-config
        : resolve-profile
        : merge-ssl
        : client-options
        : display-options
        : colors-wanted?
        : find-profile
        : fetch-schema
        : retry-options
        : request-timeout
        : load-schema-cached} (require :atlas.cli.settings))

(local {: usage
        : completion-fish
        : completion-bash
        : completion-zsh
        : run-complete} (require :atlas.cli.complete))

(fn sorted-names [t]
  (doto (icollect [k (pairs (or t {}))]
          k)
    (table.sort)))

(fn usage-with-choices [line title choices describe]
  "Print a usage line and the configured choices to stderr, then exit 1."
  (io.stderr:write (.. line "\n\n"))
  (if (next choices)
      (do
        (io.stderr:write (.. title ":\n"))
        (each [_ name (ipairs (sorted-names choices))]
          (io.stderr:write (.. "  " name "\t" (describe (. choices name)) "\n"))))
      (io.stderr:write (.. "None configured in " (util.config-dir)
                           "/config.json\n")))
  (exit 1))

;; ---- profile subcommands ----

(fn profile-list [config]
  (let [profiles (or (?. config :profiles) {})]
    (if (= (next profiles) nil)
        (print "No profiles configured.")
        (each [_ name (ipairs (sorted-names profiles))]
          (print (.. name "\t"
                     (match (pcall find-profile config name)
                       (true p) (or (?. p :schema) "(no schema)")
                       (_ err) (.. "(broken: " (tostring err) ")"))))))))

(fn profile-show [config name]
  (when (not name)
    (die "Usage: atlas profile show <name>"))
  (let [p (find-profile config name)]
    (if p
        (print (pretty-mod.pretty p 0 (colors-wanted?)))
        (die (.. "Profile not found: " (tostring name))))))

(fn read-json-file [path ?keep-null]
  (let [f (or (io.open path :r) (die (.. "cannot open " path)))
        text (f:read :*a)]
    (f:close)
    (let [(ok value) (pcall json.decode text ?keep-null)]
      (if ok value (die (.. "not valid JSON: " path))))))

(fn write-config [path config]
  "Write config as JSON to path, keeping the previous file as path.bak; both
are private to the user, as profiles hold credentials."
  (let [previous (io.open path :r)]
    (when previous
      (let [text (previous:read :*a)]
        (previous:close)
        (when (not (util.write-private (.. path ".bak") text))
          (die (.. "cannot write " path ".bak"))))))
  (when (not (util.write-private path
                                 (.. (pretty-mod.pretty config 0 false) "\n")))
    (die (.. "cannot write " path))))

(fn import-restish [file p env]
  "Add the profiles of a Restish config to the atlas config; existing atlas
profiles are kept. --dry-run prints the converted profiles instead."
  (let [path (or file (restish.find-config {:RSH_CONFIG_DIR (os.getenv :RSH_CONFIG_DIR)
                                            :XDG_CONFIG_HOME (os.getenv :XDG_CONFIG_HOME)}
                                           (or (os.getenv :HOME) ".")
                                           #(let [f (io.open $ :r)]
                                              (when f (f:close)
                                                true)))
                 (die "no Restish config found; pass its path: atlas profile import-restish FILE"))
        (profiles warnings) (restish.convert (read-json-file path))
        ;; rewrite the file as it is, nulls included, not the runtime view
        config (match (io.open env.config-path :r)
                 f (do
                     (f:close)
                     (read-json-file env.config-path true))
                 _ (collect [k v (pairs env.config)] k v))
        existing (or config.profiles {})
        names (sorted-names profiles)]
    (io.stderr:write (.. "reading " path "\n"))
    (each [_ w (ipairs warnings)]
      (io.stderr:write (.. "warning: " (util.printable w) "\n")))
    (if p.dry-run
        (print (pretty-mod.pretty profiles 0 false))
        (let [merged (collect [k v (pairs existing)] k v)
              added (icollect [_ name (ipairs names)]
                      (when (= nil (. existing name))
                        (tset merged name (. profiles name))
                        name))]
          (each [_ name (ipairs names)]
            (when (. existing name)
              (print (.. "kept existing profile: " name))))
          (set config.profiles merged)
          (write-config env.config-path config)
          (print (string.format "imported %d profiles into %s: %s"
                                (length added) env.config-path
                                (table.concat added ", ")))))))

(fn run-profile [subcmd name p env]
  (when (and p.dry-run (not= subcmd :import-restish))
    (die "--dry-run only applies to profile import-restish"))
  (match subcmd
    :list (profile-list env.config)
    :show (profile-show env.config name)
    :import-restish (import-restish name p env)
    _ (die (.. (if subcmd (.. "Unknown profile subcommand: " subcmd "\n") "")
               "Usage: atlas profile <list|show|import-restish> [name-or-file]"))))

(fn run-auth [profile-name p config]
  (when (not profile-name)
    (die "Usage: atlas auth <profile> [--logout]"))
  (let [profile (or (find-profile config profile-name)
                    (die (.. "Profile not found: " profile-name)))
        auth-cfg (?. profile :auth)]
    (when (not (and auth-cfg auth-cfg.name (not= auth-cfg.name "")))
      (die (.. "No auth configured for profile: " profile-name)))
    (let [net {:ssl (merge-ssl profile p.ssl)
               :timeout (request-timeout profile p config)}
          headers #(let [(ok h) (pcall auth.get-headers profile-name auth-cfg
                                       net)]
                     (if ok h (die (tostring h))))]
      (if p.logout
          (do
            (auth.clear-token profile-name)
            (print (.. "Logged out: " profile-name)))
          (. {:external-tool true :bearer true :basic true :api-key true}
             auth-cfg.name)
          (let [h (headers)
                params (or auth-cfg.params {})]
            (each [_ k (ipairs (sorted-names h))]
              (print (.. k ": " (. h k))))
            ;; what is added to each request rather than as a header
            (if (and (= auth-cfg.name :api-key) (= params.in :query))
                (print (.. "query: " (tostring params.name) "="
                           (tostring params.value)))
                (and (= auth-cfg.name :external-tool)
                     (not= params.output :bearer-token))
                (print (.. "signs each request with: "
                           (tostring params.commandline)))))
          ;; a new token replaces the cached one only once obtained
          (let [(ok err) (pcall auth.authenticate profile-name auth-cfg net)]
            (if ok
                (print (.. "Authenticated: " profile-name))
                (die (tostring err))))))))

;; ---- az ----

(fn object-option [name value]
  "value, which must be a JSON object to give workflow inputs (or nil)."
  (when (and (not= nil value)
             (or (not= (type value) :table) (= value json.null)
                 (json.array? value)))
    (die (.. name " must be an object of workflow inputs")))
  (or value {}))

(fn workflow-inputs [p named doc wf]
  "Inputs for a run, lowest priority first: the context's configured inputs,
positional path params, --inputs, --body, then --i./-i/--b. fields."
  (let [base (collect [k v (pairs (or (?. named :inputs) {}))]
               k
               v)]
    (each [j name (ipairs (arazzo.positional-inputs wf))]
      (let [v (. p.path-params j)]
        (when v (tset base name v))))
    (each [k v (pairs (object-option "--inputs" p.arazzo-inputs-blob))]
      (tset base k v))
    (when p.body
      (each [k v (pairs (object-option "--body" (decode-structured p.body)))]
        (tset base k v)))
    (let [fields (icollect [_ f (ipairs p.input-fields)] f)]
      (each [_ f (ipairs p.body-fields)]
        (table.insert fields f))
      (build-body fields (arazzo.workflow-inputs doc wf) base))))

(fn progress-reporter [output use-color]
  "on-step callback printing live step progress to stderr."
  (let [paint #(pretty-mod.paint $1 $2 use-color)]
    (fn [info]
      (match info.status
        :running (io.stderr:write (.. (paint :dim "→") " "
                                      (util.printable info.step) "\n"))
        :done (do
                (io.stderr:write (.. (paint :ok "✓") " "
                                     (util.printable info.step)
                                     (if info.elapsed
                                         (string.format "  %.3fs" info.elapsed)
                                         "")
                                     (if (?. info :response :status)
                                         (.. "  HTTP " info.response.status)
                                         "")
                                     "\n"))
                (when (and info.outputs (next info.outputs))
                  (io.stderr:write (.. (render info.outputs output use-color)
                                       "\n"))))))))

(fn check-inputs [doc wf inputs p]
  "Stop when inputs don't match the workflow's inputs schema, unless --no-validate."
  (let [errors (validate.check (arazzo.workflow-inputs doc wf) inputs :inputs)]
    (when (and (next errors) (not p.no-validate))
      (die (.. (table.concat errors "\n") "\n(use --no-validate to run anyway)")))))

(fn schema-transport [env verbose]
  "Transport for fetching specs: logged like requests under -v."
  (let [transport (or env.transport http-mod.request)]
    (if verbose (wrap-log-request transport) transport)))

(fn source-schema-loader [env client-opts verbose]
  "Loader for source schemas: URLs through the transport, getting credentials
(client-opts :auth-headers and :authorize) only after answering 401/403, and
never for a document whose loader options say :credentials false (a $ref to
another origin); files directly."
  (fn [location opts]
    (if (location:match "^https?://")
        (fetch-schema location
                      {:transport (schema-transport env verbose)
                       :headers opts.headers
                       :ssl opts.ssl
                       :timeout opts.timeout
                       :base-url client-opts.base-url
                       :auth-headers (when (not= false opts.credentials)
                                       client-opts.auth-headers)
                       :authorize (when (not= false opts.credentials)
                                    client-opts.authorize)})
        (atlas.load-schema location opts))))

(fn execute-workflow [doc file wf inputs p profile-name profile env]
  (let [
        ;; merged pages would change what step expressions like $response.body#/0 refer to
        p (doto (collect [k v (pairs p)] k v)
            (tset :no-paginate true))
        {: output : no-color : verbose} (display-options profile p env.config)
        mode (or p.arazzo-output (if verbose :progress :final))
        show-progress (or (= mode :progress) (= mode :full))
        ;; progress goes to stderr
        stderr-color (and (not no-color) (util.terminal? 2))
        paint #(pretty-mod.paint $1 $2 stderr-color)
        run-opts (client-options profile-name profile p env.config
                                 env.transport)]
    (set run-opts.load-schema (source-schema-loader env run-opts verbose))
    (set run-opts.on-step
         (when show-progress
           (progress-reporter output stderr-color)))
    (set run-opts.max-gotos p.max-gotos)
    (set run-opts.max-wait (. (retry-options profile p env.config) :max-wait))
    (let [t0 (socket.gettime)
          clients (arazzo.build-clients doc run-opts file)
          (ok result) (pcall arazzo.run-workflow doc wf.workflowId inputs
                             clients run-opts)
          timing (string.format "  %.3fs" (- (socket.gettime) t0))]
      (when show-progress
        (io.stderr:write (if ok
                             (.. (paint :ok "✓") " workflow "
                                 (util.printable wf.workflowId) timing "\n")
                             (.. (paint :fail "✗") " workflow "
                                 (util.printable wf.workflowId) " failed" timing
                                 "\n"))))
      (if ok
          (print-arazzo-result result mode output no-color)
          (die (tostring result))))))

(fn run-arazzo [p env]
  ;; p.schema = name-or-file, p.operation = workflow-id, p.path-params = extra positionals
  (when (or p.dry-run p.curl)
    (die "--dry-run/--curl are not supported for az: later steps depend on real responses; use -v to log each request"))
  (when (not p.schema)
    (usage-with-choices "Usage: atlas az <name-or-file> <workflow-id> [-i KEY=VAL ...]"
                        "Configured Arazzo contexts" (or env.config.arazzo {})
                        #(or $.file "")))
  (let [named (?. env.config :arazzo p.schema)
        file (if named named.file p.schema)
        profile-name (or p.profile (?. named :profile))
        profile (find-profile env.config profile-name)
        _ (when (and profile-name (not profile))
            (die (.. "Profile not found: " profile-name)))
        doc (arazzo.load-doc file
                             {:ssl (merge-ssl profile p.ssl)
                              :timeout (request-timeout profile p env.config)})
        wf (when p.operation (arazzo.find-workflow doc p.operation))]
    (if (not p.operation) (list-arazzo-workflows doc) (not wf)
        (die (.. "Unknown workflow: " p.operation)) p.help
        (print (util.printable (cli-help.build-workflow wf
                                                        (arazzo.workflow-inputs doc
                                                                                wf)
                                                        (arazzo.positional-inputs wf))))
        (let [inputs (workflow-inputs p named doc wf)]
          (check-inputs doc wf inputs p)
          (execute-workflow doc file wf inputs p profile-name profile env)))))

;; ---- op ----

(fn load-op-schema [raw-schema profile p opts env verbose]
  "Parsed schema for op: URLs through the cache and the transport, files
parsed by atlas.client."
  (if (and (= (type raw-schema) :string) (raw-schema:match "^https?://"))
      (load-schema-cached raw-schema
                          {:transport (schema-transport env verbose)
                           :headers opts.headers
                           ;; a dry run's auth headers are placeholders
                           :auth-headers (when (not (and p.dry-run (not p.curl)))
                                           opts.auth-headers)
                           :authorize opts.authorize
                           :base-url opts.base-url
                           :ssl opts.ssl
                           :timeout opts.timeout
                           :ttl (or p.cache-ttl (?. profile :cache-ttl) 3600)
                           :reload p.reload
                           :cache env.schema-cache})
      raw-schema))

(fn check-request [op request opts p]
  "Warn about undeclared query names; stop on missing required params or an
invalid body unless --no-validate."
  (let [headers (collect [k v (pairs opts.headers)] k v)]
    (each [k v (pairs (or request.headers {}))]
      (tset headers k v))
    ;; headers auth will add count as present without authenticating now
    (each [_ name (ipairs opts.auth-header-names)]
      (tset headers name "<auth>"))
    (let [(errors warnings) (check-params op {:query request.query : headers})]
      (each [_ e (ipairs (check-body op request.body))]
        (table.insert errors e))
      (each [_ w (ipairs warnings)]
        (io.stderr:write (.. "warning: " (util.printable w) "\n")))
      (when (and (next errors) (not p.no-validate))
        (die (.. (table.concat errors "\n")
                 "\n(use --no-validate to send anyway)"))))))

(fn check-arguments [op p]
  "Stop on arguments the operation can't use."
  (when (> (length p.path-params) (length op.path-params))
    (die (string.format "%s takes %d path parameter%s (%s), got %d: %s"
                        p.operation (length op.path-params)
                        (if (= 1 (length op.path-params)) "" "s")
                        (table.concat op.path-params ", ")
                        (length p.path-params) (table.concat p.path-params " ")))))

(fn send-op [op p opts profile config]
  (check-arguments op p)
  (let [request (op-request op p)
        {: output : no-color : verbose} (display-options profile p config)]
    (check-request op request opts p)
    (let [t0 (socket.gettime)
          (ok resp) (pcall op.invoke request)]
      (if ok
          (print-resp resp output no-color verbose p.select
                      (- (socket.gettime) t0) p.ignore-status)
          (die (.. "request failed: " (tostring resp)))))))

(fn run-op [p env]
  (let [config env.config]
    (when (not p.schema)
      (usage-with-choices "Usage: atlas op <profile-or-schema> [operation] [args...]"
                          "Configured profiles" (or config.profiles {})
                          #(or $.schema "(no schema)")))
    (let [profile (find-profile config p.schema)
          raw-schema (if (not profile) p.schema
                         (or profile.schema
                             (die (.. "profile " p.schema
                                      " has no schema: set \"schema\" to the spec's URL or path"))))
          opts (client-options p.schema profile p config env.transport)
          verbose (. (display-options profile p config) :verbose)
          schema (load-op-schema raw-schema profile p opts env verbose)]
      (when (= (type schema) :table)
        (set opts.source-url raw-schema))
      ;; documents the spec refers to: through the transport, with the same
      ;; rules for headers and credentials as the spec (a dry run's auth
      ;; headers are placeholders)
      (set opts.load-schema
           (source-schema-loader env
                                 {:auth-headers (when (not (and p.dry-run
                                                                (not p.curl)))
                                                  opts.auth-headers)
                                  :authorize opts.authorize
                                  :base-url opts.base-url}
                                 verbose))
      (if p.servers
          (let [servers (atlas.servers (if (= (type schema) :string)
                                           (atlas.load-schema schema)
                                           schema))
                index (or opts.server-index 1)
                selected (. servers index)
                (ok err) (if selected
                             (pcall atlas.server-url selected
                                    (or opts.server-vars {}))
                             true)]
            (when (not ok)
              (die (tostring err)))
            (print (util.printable (format-servers servers index
                                                   opts.server-vars))))
          (let [(ok c) (pcall atlas.client schema opts)
                c (if ok c (die (.. "failed to build client: " (tostring c))))
                op (when p.operation
                     (or (. c p.operation)
                         (die (.. "Unknown operation: " p.operation))))]
            (if (or p.list (not op)) (list-ops c) p.help
                (print (util.printable (cli-help.build-cli op.path op.method
                                                           op.spec op.name)))
                (send-op op p opts profile config)))))))

;; ---- entry points ----

(fn dispatch [args env]
  (if (= (. args 1) "__complete")
      (run-complete args)
      (= (. args 1) "--version")
      (print (.. "atlas " atlas.version " ("
                 ((. (require :atlas.curl) :version)) ")"))
      (let [p (parse-args args)]
        (match p.cmd
          nil (usage)
          :completion (match p.schema
                        :fish (completion-fish)
                        :bash (completion-bash)
                        :zsh (completion-zsh)
                        _ (die "Usage: atlas completion <fish|bash|zsh>"))
          (where (or :profile :auth) p.help) (usage)
          :profile (run-profile p.schema p.operation p env)
          :auth (run-auth p.schema p env.config)
          (where (or :az :arazzo)) (run-arazzo p env)
          :op (run-op p env)
          _ (die (.. "Unknown command: " (tostring p.cmd)
                     "\nUsage: atlas <op|az|profile|auth|completion> ..."))))))

(fn run [args ?env]
  "Run atlas with args and return the exit code.
?env: {:transport http-fn :config table :config-path string :schema-cache bool}
replaces the network, the config contents, where the config is written, and
the schema cache."
  (let [env (or ?env {})
        (config-ok config) (if env.config (values true env.config)
                               (pcall load-config))]
    (if (not config-ok)
        (do
          (io.stderr:write (.. (tostring config) "\n"))
          1)
        (let [(ok result) (pcall dispatch args
                                 (doto (collect [k v (pairs env)] k v)
                                   (tset :config config)
                                   (tset :config-path
                                         (or env.config-path (config-path)))))]
          (if ok
              (if (= (type result) :number) result 0)
              (let [(code message) (exit-status result)]
                (when (not= message "")
                  ;; messages quote specs and servers: keep their control
                  ;; characters from the terminal
                  (io.stderr:write (.. (util.printable message) "\n")))
                code))))))

(fn main [args]
  (os.exit (run args)))

{: main : run}
