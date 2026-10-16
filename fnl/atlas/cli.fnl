;; ABOUTME: The atlas command line: dispatches the op, az, http, mcp, auth,
;; ABOUTME: profile and completion subcommands; run returns the exit code.
(local atlas (require :atlas))
(local arazzo (require :atlas.arazzo))
(local arazzo-expr (require :atlas.arazzo.expr))
(local arazzo-check (require :atlas.arazzo.check))
(local auth (require :atlas.auth))
(local cli-help (require :atlas.cli.help))
(local http-mod (require :atlas.http))
(local mcp (require :atlas.cli.mcp))
(local pretty-mod (require :atlas.pretty))
(local progress (require :atlas.cli.progress))
(local socket (require :socket))
(local util (require :atlas.util))
(local validate (require :atlas.validate))
(local {: decode-structured
        : build-body
        : op-request
        : check-params
        : check-body} (require :atlas.cli.request))

(local {: parse-args} (require :atlas.cli.args))
(local plugins (require :atlas.cli.plugins))
(local restish (require :atlas.cli.restish))
(local json (require :atlas.json))
(local {: list-ops
        : print-resp
        : die
        : exit
        : exit-status
        : format-servers
        : print-arazzo-result
        : list-arazzo-workflows
        : wrap-log-request
        : strip-location
        : check-select
        : stream-printer
        : exit?} (require :atlas.cli.output))

(local {: config-path
        : load-config
        : check-config
        : resolve-profile
        : merge-ssl
        : client-options
        : display-options
        : colors-wanted?
        : find-profile
        : fetch-schema
        : retry-options
        : request-timeout
        : load-schema-cached
        : discover-schema} (require :atlas.cli.settings))

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
                       (_ err) (.. "(broken: " (strip-location (tostring err))
                                   ")"))))))))

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
        auth-cfg (let [a (?. profile :auth)]
                   (when (not (and a a.name (not= a.name "")))
                     (die (.. "No auth configured for profile: " profile-name)))
                   (let [(ok resolved) (pcall plugins.resolve-auth config a)]
                     (if ok resolved (die (tostring resolved)))))]
    (let [net {:ssl (merge-ssl profile p.ssl)
               :timeout (request-timeout profile p config)}
          headers #(let [(ok h) (pcall auth.get-headers profile-name auth-cfg
                                       net)]
                     (if ok h (die (tostring h))))]
      (if p.logout
          (do
            (auth.clear-token profile-name)
            (print (.. "Logged out: " profile-name)))
          auth-cfg.sign
          (print (.. "signs each request with auth " auth-cfg.name
                     " from plugin " auth-cfg.plugin))
          (. {:external-tool true :bearer true :basic true :api-key true}
             auth-cfg.name)
          (let [h (headers)
                params (or auth-cfg.params {})]
            (each [_ k (ipairs (sorted-names h))]
              (print (.. k ": " (. h k))))
            ;; what is added to each request rather than as a header
            (if (and (= auth-cfg.name :api-key) (= params.in :query))
                (let [(ok kv) (pcall #(.. (auth.required-param auth-cfg :name)
                                          "="
                                          (auth.required-param auth-cfg :value)))]
                  (if ok (print (.. "query: " kv)) (die (tostring kv))))
                (and (= auth-cfg.name :external-tool)
                     (not= params.output :bearer-token))
                (let [(ok command) (pcall auth.required-param auth-cfg
                                          :commandline)]
                  (if ok (print (.. "signs each request with: " command))
                      (die (tostring command))))))
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

(fn run-options [{: profile-name : profile} p env]
  "The options of a workflow run with the context's profile: its clients'
options, and how to load its sources."
  (let [
        ;; merged pages would change what step expressions like $response.body#/0 refer to
        p (doto (collect [k v (pairs p)] k v)
            (tset :no-paginate true))
        verbose (. (display-options profile p env.config) :verbose)
        run-opts (client-options profile-name profile p env.config
                                 env.transport)]
    (set run-opts.load-schema (source-schema-loader env run-opts verbose))
    run-opts))

(fn workflow-runner [{: doc : file &as context} p env ?reporter]
  "A function running a workflow of doc with its inputs: (ok result) as pcall
returns them, reporting progress to ?reporter. The clients of its sources are
built on first use."
  (let [run-opts (run-options context p env)]
    (var clients nil)
    (set run-opts.on-step (?. ?reporter :on-step))
    (set run-opts.max-gotos p.max-gotos)
    (set run-opts.max-wait (. (retry-options profile p env.config) :max-wait))
    ;; conditions that can't be evaluated fail; this says why
    (set run-opts.warn (or (?. ?reporter :warn)
                           #(io.stderr:write (.. "warning: " (util.printable $)
                                                 "\n"))))
    (fn [wf inputs]
      (pcall #(do
                (when (not clients)
                  (set clients (arazzo.build-clients doc run-opts file)))
                (arazzo.run-workflow doc wf.workflowId inputs clients run-opts))))))

(fn check-document [{: doc : file &as context} p env]
  "Print what is wrong in the document, or in workflow p.operation, found
without running it; exit 1 when something is."
  (let [clients (let [(ok c) (pcall arazzo.build-clients doc
                                    (run-options context p env) file)]
                  (if ok c (die (tostring c))))
        problems (icollect [_ problem (ipairs (arazzo-check.check doc clients))]
                   (when (or (not p.operation) (= problem.where p.operation)
                             (= (problem.where:sub 1 (+ (length p.operation) 3))
                                (.. p.operation " ›")))
                     problem))
        count-of #(accumulate [n 0 _ problem (ipairs problems)]
                    (if (= problem.level $) (+ n 1) n))
        errors (count-of :error)
        warnings (count-of :warning)
        plural #(.. $1 " " $2 (if (= $1 1) "" "s"))]
    (each [_ problem (ipairs problems)]
      (print (util.printable (.. (if (= problem.level :error) "✗ " "! ")
                                 problem.where ": " problem.message))))
    (print (if (next problems)
               (.. (plural errors :error) ", " (plural warnings :warning))
               (let [workflows (icollect [_ wf (ipairs (or doc.workflows []))]
                                 (when (or (not p.operation)
                                           (= wf.workflowId p.operation))
                                   wf))]
                 (.. "✓ " (plural (length workflows) :workflow) ", "
                     (plural (accumulate [n 0 _ wf (ipairs workflows)]
                               (+ n (length (or wf.steps []))))
                             :step) ": nothing wrong found"))))
    (when (> errors 0)
      (exit 1))))

(fn execute-workflow [context wf inputs p env]
  (let [{: output : no-color : verbose} (display-options context.profile p
                                                         env.config)
        mode (or p.arazzo-output (if verbose :progress :final))
        ;; progress goes to stderr; on a terminal, lines are rewritten in
        ;; place, unless -v interleaves the requests' logs with them
        stderr-terminal (util.terminal? 2)
        reporter (when (or (= mode :progress) (= mode :full))
                   (progress.reporter {:write #(io.stderr:write $)
                                       :tty (and stderr-terminal (not verbose))
                                       ;; unknown, a common width: the
                                       ;; lines rewritten in place must not wrap
                                       :columns (when stderr-terminal
                                                  (or (util.terminal-columns)
                                                      80))
                                       :color (and stderr-terminal
                                                   (not no-color))}))
        run (workflow-runner context p env reporter)]
    (let [t0 (socket.gettime)
          (ok result) (run wf inputs)]
      (when reporter
        (reporter.finish ok wf.workflowId (- (socket.gettime) t0)))
      (if ok
          (print-arazzo-result result mode output no-color)
          (die (tostring result))))))

(fn arazzo-context [name ?profile-name p env]
  "{:named :file :doc :profile-name :profile} of an Arazzo context (or file)
name: the document, and the profile to run it with, ?profile-name else the
context's."
  (let [named (?. env.config :arazzo name)
        file (if named named.file name)
        profile-name (or ?profile-name (?. named :profile))
        profile (find-profile env.config profile-name)
        _ (when (and profile-name (not profile))
            (die (.. "Profile not found: " profile-name)))
        doc (arazzo.load-doc file
                             {:ssl (merge-ssl profile p.ssl)
                              :timeout (request-timeout profile p env.config)})]
    {: named : file : doc : profile-name : profile}))

(fn run-arazzo [p env]
  ;; p.schema = name-or-file, p.operation = workflow-id, p.path-params = extra positionals
  (when (or p.dry-run p.curl)
    (die "--dry-run/--curl are not supported for az: later steps depend on real responses; use -v to log each request"))
  (when (not p.schema)
    (usage-with-choices "Usage: atlas az <name-or-file> <workflow-id> [-i KEY=VAL ...]"
                        "Configured Arazzo contexts" (or env.config.arazzo {})
                        #(or $.file "")))
  (let [{: named : doc &as context} (arazzo-context p.schema p.profile p env)
        wf (when p.operation (arazzo.find-workflow doc p.operation))]
    (if (and p.operation (not wf)) (die (.. "Unknown workflow: " p.operation))
        p.check (check-document context p env) (not p.operation)
        (list-arazzo-workflows doc) p.help
        (print (util.printable (cli-help.build-workflow wf
                                                        (arazzo.workflow-inputs doc
                                                                                wf)
                                                        (arazzo.positional-inputs wf))))
        (let [inputs (workflow-inputs p named doc wf)]
          (check-inputs doc wf inputs p)
          (execute-workflow context wf inputs p env)))))

;; ---- op ----

(fn schema-fetch-options [profile p opts env verbose]
  "load-schema-cached options for the spec of an API."
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

(fn load-op-schema [raw-schema profile p opts env verbose]
  "Parsed schema for op: URLs through the cache and the transport, files
parsed by atlas.client."
  (if (and (= (type raw-schema) :string) (raw-schema:match "^https?://"))
      (load-schema-cached raw-schema
                          (schema-fetch-options profile p opts env verbose))
      raw-schema))

(fn request-problems [op request opts]
  "(errors warnings) of request for op: missing required params and body
errors, and undeclared query names."
  (let [headers (collect [k v (pairs opts.headers)] k v)]
    (each [k v (pairs (or request.headers {}))]
      (tset headers k v))
    ;; headers auth will add count as present without authenticating now
    (each [_ name (ipairs opts.auth-header-names)]
      (tset headers name "<auth>"))
    (let [(errors warnings) (check-params op
                                          {:query request.query
                                           : headers
                                           :implied-query opts.implied-query})]
      (each [_ e (ipairs (check-body op request.body))]
        (table.insert errors e))
      (values errors warnings))))

(fn check-request [op request opts p]
  "Warn about undeclared query names; stop on missing required params or an
invalid body unless --no-validate."
  (let [(errors warnings) (request-problems op request opts)]
    (each [_ w (ipairs warnings)]
      (io.stderr:write (.. "warning: " (util.printable w) "\n")))
    (when (and (next errors) (not p.no-validate))
      (die (.. (table.concat errors "\n")
               "\n(use --no-validate to send anyway)")))))

(fn check-arguments [op p]
  "Stop on arguments the operation can't use."
  (when (> (length p.path-params) (length op.path-params))
    (die (string.format "%s takes %d path parameter%s (%s), got %d: %s"
                        p.operation (length op.path-params)
                        (if (= 1 (length op.path-params)) "" "s")
                        (table.concat op.path-params ", ")
                        (length p.path-params) (table.concat p.path-params " ")))))

(fn attempt [send]
  "The response of (send); a request that fails stops atlas."
  (let [(ok resp) (pcall send)]
    (if ok resp
        (exit? resp) (error resp 0)
        (die (.. "request failed: " (tostring resp))))))

(fn poll [send p verbose]
  "The first response of (send) for which p.until holds, sending again every
p.every seconds for up to p.max-time; on a terminal, a line says what it waits
for."
  (let [every (or p.every 5)
        max-time (or p.max-time 600)
        t0 (socket.gettime)
        ;; in place on a terminal, unless -v logs requests between attempts
        tty (and (util.terminal? 2) (not verbose))
        columns (when tty (or (util.terminal-columns) 80))
        clear #(when tty (io.stderr:write "\r\27[K"))]
    (var result nil)
    (var attempts 0)
    (while (not result)
      (let [resp (attempt send)
            ctx {:response resp :inputs {} :steps {} :workflows {}}
            criterion {:condition p.until}
            (passed problem) (arazzo-expr.eval-criterion ctx criterion)
            elapsed (- (socket.gettime) t0)]
        (set attempts (+ attempts 1))
        (when problem
          (clear)
          (die (.. "--until: " problem)))
        (if passed (set result resp) (> (+ elapsed every) max-time)
            (do
              (clear)
              (die (string.format "--until condition still false after %d attempt%s (%s): %s"
                                  attempts (if (= attempts 1) "" "s")
                                  (util.duration elapsed)
                                  (arazzo-expr.explain-criterion ctx criterion))))
            (do
              (when tty
                (io.stderr:write (.. "\r\27[K"
                                     (progress.fit (progress.one-line (string.format "↻ attempt %d · %s · again in %ss · %s"
                                                                                     attempts
                                                                                     (util.duration elapsed)
                                                                                     every
                                                                                     (arazzo-expr.explain-criterion ctx
                                                                                                                    criterion)))
                                                   columns))))
              (socket.sleep every)))))
    (clear)
    result))

(fn exchange [send p display]
  "Send the request with (send), again while p.until doesn't hold, and print
the response."
  (when (and (not p.until) (or p.every p.max-time))
    (die (.. (if p.every "--every" "--max-time") " needs --until")))
  (let [{: output : no-color : verbose} display
        t0 (socket.gettime)
        resp (if p.until (poll send p verbose) (attempt send))]
    (print-resp resp output no-color verbose p.select (- (socket.gettime) t0)
                ;; a condition that holds is success, whatever the status
                (or p.ignore-status (not= nil p.until)))))

(fn send-op [op p opts profile config]
  (check-arguments op p)
  (let [request (op-request op p)]
    (check-request op request opts p)
    (exchange #(op.invoke request) p (display-options profile p config))))

(fn discovered-api-schema [profile-name profile p opts env verbose]
  "(location schema) of the spec discovery finds for the profile's base URL;
a remembered location that no longer works is looked for again."
  (let [fetch-opts (schema-fetch-options profile p opts env verbose)
        find #(let [(location doc reasons) (discover-schema opts.base-url $)]
                (when (not location)
                  (die (.. "no OpenAPI description found for "
                           (util.redact-url opts.base-url)
                           ": set \"schema\" in profile " profile-name "\n  "
                           (table.concat (icollect [_ r (ipairs reasons)]
                                           (strip-location r))
                                         "\n  "))))
                (values location doc))
        (location doc) (find fetch-opts)]
    (if doc (values location doc)
        (let [(ok schema) (pcall load-op-schema location profile p opts env
                                 verbose)]
          (if ok (values location schema)
              (find (doto (collect [k v (pairs fetch-opts)] k v)
                      (tset :reload true))))))))

(fn api-setup [p env usage]
  "{:profile :schema :opts} for a command naming a profile or a spec
(p.schema): the profile, the spec (parsed when fetched, else its path) and
the client options."
  (let [config env.config]
    (when (not p.schema)
      (usage-with-choices usage "Configured profiles" (or config.profiles {})
                          #(or $.schema "(no schema)")))
    (let [profile (find-profile config p.schema)
          opts (client-options p.schema profile p config env.transport)
          verbose (. (display-options profile p config) :verbose)
          (raw-schema schema) (if (not profile)
                                  (values p.schema
                                          (load-op-schema p.schema profile p
                                                          opts env verbose))
                                  profile.schema
                                  (values profile.schema
                                          (load-op-schema profile.schema
                                                          profile p opts env
                                                          verbose))
                                  ;; no schema: the API may say where its
                                  ;; spec is
                                  opts.base-url
                                  (discovered-api-schema p.schema profile p
                                                         opts env verbose)
                                  (die (.. "profile " p.schema
                                           " has no schema: set \"schema\" to the spec's URL or path, or \"base-url\" to find it")))]
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
      {: profile : schema : opts})))

(fn build-client [schema opts]
  (let [(ok c) (pcall atlas.client schema opts)]
    (if ok c (die (.. "failed to build client: " (tostring c))))))

(fn print-streams [opts profile p config]
  "opts with an http-fn whose requests print the responses that come as a
stream (events, JSON Lines, raw output) as they arrive."
  (let [{: output : no-color : verbose} (display-options profile p config)
        http-fn opts.http-fn
        stream (stream-printer output (not no-color) p.select
                               (util.terminal? 1) verbose)]
    (doto opts
      (tset :http-fn #(http-fn (doto (collect [k v (pairs $)] k v)
                                 (tset :stream stream)))))))

(fn run-op [p env]
  (let [config env.config
        {: profile : schema : opts} (api-setup p env
                                               "Usage: atlas op <profile-or-schema> [operation] [args...]")
        _ (print-streams opts profile p config)]
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
          (print (util.printable (format-servers servers index opts.server-vars))))
        (let [c (build-client schema opts)
              op (when p.operation
                   (or (. c p.operation)
                       (die (.. "Unknown operation: " p.operation))))]
          (if (or p.list (not op)) (list-ops c) p.help
              (print (util.printable (cli-help.build-cli op.path op.method
                                                         op.spec op.name)))
              (send-op op p opts profile config))))))

;; ---- http ----

(local http-usage "Usage: atlas http [METHOD] <URL-or-path> [options]")

(fn profile-base-url [profile-name profile p opts env]
  "Where a profile's API is: --base-url or its base-url, else its spec's
server."
  (or opts.base-url (let [raw-schema (or profile.schema
                                         (die (.. "profile " profile-name
                                                  " has no base-url or schema")))
                          verbose (. (display-options profile p env.config)
                                     :verbose)
                          schema (load-op-schema raw-schema profile p opts env
                                                 verbose)
                          (ok url) (pcall atlas.base-url
                                          (if (= (type schema) :string)
                                              (atlas.load-schema schema)
                                              schema)
                                          {:server-index opts.server-index
                                           :server-vars opts.server-vars
                                           :source-url (when (= (type schema)
                                                                :table)
                                                         raw-schema)})]
                      (if ok url (die (tostring url))))))

(fn http-url [target base profile-name]
  "The URL of target: absolute, or a path under base. A profile's
credentials only go to its own origin."
  (if (target:match "^%a[%w+.-]*://")
      (do
        (when (not (util.origin target))
          (die (.. "not an http(s) URL: " target)))
        (when (and profile-name (not= (util.origin target) (util.origin base)))
          (die (.. target " is not on the API of profile " profile-name " ("
                   (util.origin base) "): its credentials are only sent there")))
        target)
      base
      (.. (pick-values 1 (base:gsub "/+$" "")) "/"
          (pick-values 1 (target:gsub "^/+" "")))
      (die (.. "a path needs --profile or --base-url: " target))))

(fn http-body [p]
  "(body json) from -d and --b. fields: fields build a JSON object (on -d's
JSON or YAML one); otherwise -d is sent as given, as JSON when it is JSON."
  (if (next p.body-fields)
      (values (build-body p.body-fields nil
                          (when p.body (decode-structured p.body)))
              true)
      (values p.body (and (= (type p.body) :string) (pcall json.decode p.body)))))

(local http-methods {:GET true
                     :HEAD true
                     :POST true
                     :PUT true
                     :PATCH true
                     :DELETE true
                     :OPTIONS true
                     :TRACE true
                     :CONNECT true})

(fn run-http [p env]
  ;; a method alone is a forgotten URL, not a path named after the method
  (when (or (not p.schema) (next p.path-params)
            (and (not p.operation) (. http-methods (p.schema:upper))))
    (die http-usage))
  (let [config env.config
        (method target) (if p.operation
                            (values (p.schema:upper) p.operation)
                            (values "GET" p.schema))
        _ (when (not (method:match "^[!#$%%&'*+%-.^_`|~%w]+$"))
            (die (.. "invalid HTTP method: " p.schema)))
        profile (find-profile config p.profile)
        _ (when (and p.profile (not profile))
            (die (.. "Profile not found: " p.profile)))
        opts (print-streams (client-options p.profile profile p config
                                            env.transport)
                            profile p config)
        base (if profile
                 (profile-base-url p.profile profile p opts env)
                 opts.base-url)
        url (http-url target base p.profile)
        (body json-body) (http-body p)
        headers (collect [k v (pairs opts.headers)] k v)]
    (each [k v (pairs p.headers)]
      (tset headers (k:lower) v))
    (when (and json-body (= nil (. headers :content-type)))
      (tset headers :content-type "application/json"))
    (exchange #(opts.http-fn {: method
                              : url
                              :query (when (next p.query) p.query)
                              : headers
                              : body
                              :ssl opts.ssl
                              :timeout opts.timeout}) p
              (display-options profile p config))))

;; ---- mcp ----

(local mcp-usage
       "Usage: atlas mcp <profile-or-schema> [--allow-writes] [--arazzo NAME]")

(fn name-pattern [glob]
  "A Lua pattern matching the whole names glob matches: * is any text."
  (.. "^" (pick-values 1 (: (glob:gsub "[%^%$%(%)%%%.%[%]%+%-%?]" "%%%0") :gsub
                            "%*" ".*")) "$"))

(fn listed-operations [c listed]
  "The operations of c that listed names, as names or * patterns: an
unknown name, or a pattern that matches nothing, is an error."
  (let [chosen {}]
    (each [_ entry (ipairs listed)]
      (if (entry:find "*" 1 true)
          (let [pattern (name-pattern entry)
                matched (icollect [name op (pairs c)]
                          (when (name:match pattern)
                            (tset chosen name op)
                            name))]
            (when (= nil (next matched))
              (die (.. "mcp.operations: " entry " matches no operation"))))
          (tset chosen entry (or (. c entry)
                                 (die (.. "unknown operation in mcp.operations: "
                                          entry))))))
    (icollect [_ op (pairs chosen)] op)))

(fn mcp-operations [c profile p]
  "The operations atlas mcp offers: those the profile's mcp.operations lists,
else the read-only ones (all with --allow-writes), by name."
  (let [listed (?. profile :mcp :operations)
        ops (if listed
                (listed-operations c listed)
                (icollect [_ op (pairs c)]
                  (when (or p.allow-writes
                            (. {:get true :head true :options true}
                               (op.method:lower)))
                    op)))]
    (table.sort ops #(< $1.name $2.name))
    ops))

(fn tool-error [text]
  {:content [{:type :text : text}] :isError true})

(fn tool-text [body]
  "A response body as tool result text: JSON, or text when it is UTF-8."
  (if (= nil body) nil
      (= (type body) :table) (json.encode body)
      (utf8.len body) body
      (.. "(" (length body) " bytes that aren't text)")))

(fn call-tool [op arguments opts tool-opts]
  "The tools/call result of op for arguments: the response body, or a tool
error for arguments the operation can't take and for HTTP errors."
  (let [(ok req) (pcall mcp.request op arguments tool-opts)
        errors (if ok (check-body op req.body) [])]
    (if (not ok) (tool-error (strip-location (tostring req))) (next errors)
        (tool-error (table.concat errors "\n"))
        (let [(sent resp) (pcall op.invoke req)
              text (when sent (tool-text resp.body))]
          (if (not sent)
              (tool-error (.. "request failed: "
                              (strip-location (tostring resp))))
              (>= resp.status 400)
              (tool-error (.. "HTTP " resp.status (if text (.. "\n" text) "")))
              {:content [{:type :text :text (or text (.. "HTTP " resp.status))}]
               :isError false})))))

(fn operation-tools [p env]
  "[[tool call] ...] for the operations atlas mcp offers of p.schema."
  (let [{: profile : schema : opts} (api-setup p env mcp-usage)
        document (if (= (type schema) :string) (atlas.load-schema schema)
                     schema)
        _ (when (= (type schema) :string)
            (set opts.source-url schema))
        c (build-client document opts)
        supplied-headers (collect [k (pairs opts.headers)] (k:lower)
                           true)
        _ (each [_ name (ipairs opts.auth-header-names)]
            (tset supplied-headers (name:lower) true))
        tool-opts {:openapi-30 (not (: (tostring (or document.openapi ""))
                                       :match "^3%.[1-9]"))
                   : supplied-headers
                   :supplied-query opts.implied-query}]
    (icollect [_ op (ipairs (mcp-operations c profile p))]
      [(mcp.tool op tool-opts) #(call-tool op $ opts tool-opts)])))

(fn workflow-tools [p env]
  "[[tool call] ...] for the workflows of the Arazzo context or file
p.arazzo, run with the context's profile, else the profile atlas mcp names."
  (let [positional (when (and p.schema (find-profile env.config p.schema))
                     p.schema)
        context (arazzo-context p.arazzo
                                (or (?. env.config :arazzo p.arazzo :profile)
                                    positional)
                                p env)
        run (workflow-runner context p env)]
    (icollect [_ wf (ipairs (or context.doc.workflows []))]
      (let [schema (arazzo.workflow-inputs context.doc wf)]
        [(mcp.workflow-tool wf schema)
         (fn [inputs]
           (let [(object err) (pcall mcp.check-arguments inputs)
                 errors (if (not object) [err] schema
                            (validate.check schema inputs :inputs) (next inputs)
                            ["the workflow takes no inputs"] [])]
             (if (next errors) (tool-error (table.concat errors "\n"))
                 (let [(ok result) (run wf inputs)]
                   (if ok
                       {:content [{:type :text
                                   :text (json.encode (or result.outputs {}))}]
                        :isError false}
                       (tool-error (strip-location (tostring result))))))))]))))

(fn run-mcp [p env]
  (when (or p.operation (next p.path-params))
    (die mcp-usage))
  (let [entries (if (or p.schema (not p.arazzo)) (operation-tools p env) [])
        _ (when p.arazzo
            (each [_ entry (ipairs (workflow-tools p env))]
              (table.insert entries entry)))
        calls (accumulate [calls {} _ [tool call] (ipairs entries)]
                (if (. calls tool.name)
                    (die (.. "two tools would be named " tool.name
                             ": rename one of the workflows"))
                    (doto calls (tset tool.name call))))
        handle (mcp.handler {:tools (icollect [_ [tool] (ipairs entries)] tool)
                             :call #((. calls $1) $2)
                             :version atlas.version
                             :instructions "Each tool calls an operation of an HTTP API, or runs an Arazzo workflow, through atlas. Path, query and header parameters are arguments by name; a request body is the body argument."})
        real-print _G.print]
    (when (> (length entries) 100)
      (io.stderr:write (.. "warning: " (length entries)
                           " tools: AI clients work best with far fewer; list the ones to offer in the profile's mcp.operations\n")))
    ;; stdout carries the protocol only
    (set _G.print (fn [...]
                    (io.stderr:write (.. (table.concat (icollect [_ v (ipairs [...])]
                                                         (tostring v))
                                                       "\t")
                                         "\n"))))
    (let [(ok err) (pcall mcp.serve handle (or env.read-line #(io.read :l))
                          (or env.write-line
                              #(doto io.stdout
                                 (: :write $ "\n")
                                 (: :flush))))]
      (set _G.print real-print)
      (when (not ok)
        (error err 0)))))

;; ---- entry points ----

(fn dispatch [args env]
  (if (= (. args 1) "__complete")
      (run-complete args)
      (= (. args 1) "--version")
      (print (.. "atlas " atlas.version " ("
                 ((. (require :atlas.curl) :version)) ")"))
      (let [p (parse-args args)]
        (when p.select
          (check-select p.select))
        (match p.cmd
          nil (usage)
          :completion (match p.schema
                        :fish (completion-fish)
                        :bash (completion-bash)
                        :zsh (completion-zsh)
                        _ (die "Usage: atlas completion <fish|bash|zsh>"))
          (where (or :profile :auth :http) p.help) (usage)
          :profile (run-profile p.schema p.operation p env)
          :auth (run-auth p.schema p env.config)
          (where (or :az :arazzo)) (run-arazzo p env)
          :op (run-op p env)
          :http (run-http p env)
          :mcp (run-mcp p env)
          _ (die (.. "Unknown command: " (tostring p.cmd)
                     "\nUsage: atlas <op|az|http|mcp|profile|auth|completion> ..."))))))

(fn run [args ?env]
  "Run atlas with args and return the exit code.
?env: {:transport http-fn :config table :config-path string :schema-cache bool}
replaces the network, the config contents, where the config is written, and
the schema cache."
  (let [env (or ?env {})
        (config-ok config) (pcall #(check-config (if env.config env.config
                                                     (load-config))))]
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
