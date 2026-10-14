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
(local json (require :lunajson))
(local {: list-ops
        : render
        : print-resp
        : die
        : exit
        : exit-status
        : format-servers
        : print-arazzo-result
        : list-arazzo-workflows} (require :atlas.cli.output))

(local {: config-path
        : load-config
        : resolve-profile
        : merge-ssl
        : client-options
        : display-options
        : fetch-schema
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

(fn find-profile [config name]
  (let [profiles (or (?. config :profiles) {})]
    (when (and name (. profiles name))
      (resolve-profile name profiles {}))))

;; ---- profile subcommands ----

(fn profile-list [config]
  (let [profiles (or (?. config :profiles) {})]
    (if (= (next profiles) nil)
        (print "No profiles configured.")
        (each [_ name (ipairs (sorted-names profiles))]
          (print (.. name "\t" (or (. profiles name :schema) "(no schema)")))))))

(fn profile-show [config name]
  (let [p (find-profile config name)]
    (if p
        (print (pretty-mod.pretty p 0 true))
        (die (.. "Profile not found: " (tostring name))))))

(fn read-json-file [path]
  (let [f (or (io.open path :r) (die (.. "cannot open " path)))
        text (f:read :*a)]
    (f:close)
    (let [(ok value) (pcall json.decode text)]
      (if ok value (die (.. "not valid JSON: " path))))))

(fn write-config [path config]
  "Write config as JSON to path, keeping the previous file as path.bak."
  (let [previous (io.open path :r)]
    (when previous
      (let [text (previous:read :*a)
            backup (io.open (.. path ".bak") :w)]
        (previous:close)
        (backup:write text)
        (backup:close))))
  (os.execute (.. "mkdir -p " (util.shell-quote (or (path:match "^(.*)/") "."))))
  (let [f (or (io.open path :w) (die (.. "cannot write " path)))]
    (f:write (.. (pretty-mod.pretty config 0 false) "\n"))
    (f:close)))

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
        config (collect [k v (pairs env.config)] k v)
        existing (or config.profiles {})
        names (sorted-names profiles)]
    (io.stderr:write (.. "reading " path "\n"))
    (each [_ w (ipairs warnings)]
      (io.stderr:write (.. "warning: " w "\n")))
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
  (match subcmd
    :list (profile-list env.config)
    :show (profile-show env.config name)
    :import-restish (import-restish name p env)
    _ (die (.. "Unknown profile subcommand: " (tostring subcmd)
               "\nUsage: atlas profile <list|show|import-restish> [name-or-file]"))))

(fn run-auth [profile-name p config]
  (when (not profile-name)
    (die "Usage: atlas auth <profile> [--logout]"))
  (let [profile (or (find-profile config profile-name)
                    (die (.. "Profile not found: " profile-name)))
        auth-cfg (?. profile :auth)]
    (when (not (and auth-cfg auth-cfg.name (not= auth-cfg.name "")))
      (die (.. "No auth configured for profile: " profile-name)))
    (let [ssl (merge-ssl profile p.ssl)
          headers #(let [(ok h) (pcall auth.get-headers profile-name auth-cfg
                                       ssl)]
                     (if ok h (die (tostring h))))]
      (if p.logout
          (do
            (auth.clear-token profile-name)
            (print (.. "Logged out: " profile-name)))
          (. {:external-tool true :bearer true :basic true :api-key true}
             auth-cfg.name)
          (let [h (headers)]
            (each [_ k (ipairs (sorted-names h))]
              (print (.. k ": " (. h k)))))
          (do
            (auth.clear-token profile-name)
            (headers)
            (print (.. "Authenticated: " profile-name)))))))

;; ---- az ----

(fn workflow-inputs [p named doc wf]
  "Inputs for a run, lowest priority first: the context's configured inputs,
positional path params, --inputs, --body, then --i./-i/--b. fields."
  (let [base (collect [k v (pairs (or (?. named :inputs) {}))]
               k
               v)]
    (each [j name (ipairs (arazzo.positional-inputs wf))]
      (let [v (. p.path-params j)]
        (when v (tset base name v))))
    (each [k v (pairs (or p.arazzo-inputs-blob {}))]
      (tset base k v))
    (when p.body
      (each [k v (pairs (decode-structured p.body))]
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
        :running (io.stderr:write (.. (paint :dim "→") " " info.step "\n"))
        :done (do
                (io.stderr:write (.. (paint :ok "✓") " " info.step
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

(fn source-schema-loader [env auth-headers]
  "Loader for source schemas: URLs through the transport, getting credentials
only after answering 401/403; files directly."
  (fn [location opts]
    (if (location:match "^https?://")
        (fetch-schema location {:transport (or env.transport http-mod.request)
                                :headers opts.headers
                                :ssl opts.ssl
                                : auth-headers})
        (atlas.load-schema location opts))))

(fn execute-workflow [doc file wf inputs p profile-name profile env]
  (let [
        ;; merged pages would change what step expressions like $response.body#/0 refer to
        p (doto (collect [k v (pairs p)] k v)
            (tset :no-paginate true))
        {: output : no-color : verbose} (display-options profile p env.config)
        mode (or p.arazzo-output (if verbose :progress :final))
        show-progress (or (= mode :progress) (= mode :full))
        paint #(pretty-mod.paint $1 $2 (not no-color))
        run-opts (client-options profile-name profile p env.config
                                 env.transport)]
    (set run-opts.load-schema (source-schema-loader env run-opts.auth-headers))
    (set run-opts.on-step
         (when show-progress (progress-reporter output (not no-color))))
    (set run-opts.max-gotos p.max-gotos)
    (let [t0 (socket.gettime)
          clients (arazzo.build-clients doc run-opts file)
          (ok result) (pcall arazzo.run-workflow doc wf.workflowId inputs
                             clients run-opts)
          timing (string.format "  %.3fs" (- (socket.gettime) t0))]
      (when show-progress
        (io.stderr:write (if ok
                             (.. (paint :ok "✓") " workflow " wf.workflowId
                                 timing "\n")
                             (.. (paint :fail "✗") " workflow " wf.workflowId
                                 " failed" timing "\n"))))
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
        doc (arazzo.load-doc file)
        wf (when p.operation (arazzo.find-workflow doc p.operation))]
    (if (not p.operation) (list-arazzo-workflows doc) (not wf)
        (die (.. "Unknown workflow: " p.operation)) p.help
        (print (cli-help.build-workflow wf (arazzo.workflow-inputs doc wf)
                                        (arazzo.positional-inputs wf)))
        (let [inputs (workflow-inputs p named doc wf)]
          (check-inputs doc wf inputs p)
          (execute-workflow doc file wf inputs p profile-name profile env)))))

;; ---- op ----

(fn load-op-schema [raw-schema profile p opts env]
  "Parsed schema for op: URLs through the cache and the transport, files
parsed by atlas.client."
  (if (and (= (type raw-schema) :string) (raw-schema:match "^https?://"))
      (load-schema-cached raw-schema
                          {:transport (or env.transport http-mod.request)
                           :headers opts.headers
                           :auth-headers opts.auth-headers
                           :ssl opts.ssl
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
        (io.stderr:write (.. "warning: " w "\n")))
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
                        (length p.path-params) (table.concat p.path-params " "))))
  (when (next p.input-fields)
    (die "workflow inputs (-i, --i.) only apply to az")))

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
          raw-schema (or (?. profile :schema) p.schema)
          opts (client-options p.schema profile p config env.transport)
          schema (load-op-schema raw-schema profile p opts env)]
      (when (= (type schema) :table)
        (set opts.source-url raw-schema))
      (if p.servers
          (print (format-servers (atlas.servers (if (= (type schema) :string)
                                                    (atlas.load-schema schema)
                                                    schema))
                                 (or opts.server-index 1) opts.server-vars))
          (let [(ok c) (pcall atlas.client schema opts)
                c (if ok c (die (.. "failed to build client: " (tostring c))))
                op (when p.operation
                     (or (. c p.operation)
                         (die (.. "Unknown operation: " p.operation))))]
            (if (or p.list (not op)) (list-ops c) p.help
                (print (cli-help.build-cli op.path op.method op.spec))
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
                  (io.stderr:write (.. message "\n")))
                code))))))

(fn main [args]
  (os.exit (run args)))

{: main : run}
