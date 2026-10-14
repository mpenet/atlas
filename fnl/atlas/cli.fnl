;; ABOUTME: The atlas command line: dispatches the op, az, auth, profile and
;; ABOUTME: completion subcommands.
(local atlas (require :atlas))
(local arazzo (require :atlas.arazzo))
(local auth (require :atlas.auth))
(local help (require :atlas.doc))
(local pretty-mod (require :atlas.pretty))
(local socket (require :socket))
(local {: decode-structured
        : decode-body
        : build-body
        : op-request
        : check-params
        : check-body} (require :atlas.cli.request))

(local {: parse-args} (require :atlas.cli.args))
(local {: redact-header
        : list-ops
        : request-text
        : curl-command
        : render
        : format-output
        : exit-code
        : print-resp
        : strip-location
        : die
        : format-servers
        : print-arazzo-result
        : list-arazzo-workflows} (require :atlas.cli.output))

(local {: load-config
        : resolve-profile
        : merge-ssl
        : retry-options
        : paginate-options
        : client-options
        : load-schema-cached} (require :atlas.cli.settings))

(local {: usage
        : complete-line
        : completion-fish
        : completion-bash
        : completion-zsh
        : run-complete} (require :atlas.cli.complete))

;; ---- profile subcommands ----
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

(fn run-auth [profile-name p config]
  (assert profile-name "Usage: atlas auth <profile> [--logout]")
  (let [profiles (or (?. config :profiles) {})
        profile (when (. profiles profile-name)
                  (resolve-profile profile-name profiles {}))]
    (assert profile (.. "Profile not found: " profile-name))
    (let [auth-cfg (?. profile :auth)]
      (assert (and auth-cfg auth-cfg.name (not= auth-cfg.name ""))
              (.. "No auth configured for profile: " profile-name))
      (let [ssl (merge-ssl profile p.ssl)]
        (if (. {:external-tool true :bearer true :basic true :api-key true}
               auth-cfg.name)
            (let [(ok headers) (pcall auth.get-headers profile-name auth-cfg
                                      ssl)]
              (if ok
                  (each [k v (pairs headers)]
                    (print (.. k ": " v)))
                  (die (tostring headers))))
            p.logout
            (do
              (auth.clear-token profile-name)
              (print (.. "Logged out: " profile-name)))
            (do
              (auth.clear-token profile-name)
              (let [(ok result) (pcall auth.get-headers profile-name auth-cfg
                                       ssl)]
                (if ok
                    (print (.. "Authenticated: " profile-name))
                    (die (tostring result))))))))))

(fn run-arazzo [p]
  ;; p.schema = name-or-file, p.operation = workflow-id, p.path-params = extra positionals
  (when (or p.dry-run p.curl)
    (die "--dry-run/--curl are not supported for az: later steps depend on real responses; use -v to log each request"))
  ;; merged pages would change what step expressions like $response.body#/0 refer to
  (tset p :no-paginate true)
  (let [name-or-file p.schema
        workflow-id p.operation]
    (when (not name-or-file)
      (let [config (load-config)
            named (or (?. config :arazzo) {})]
        (io.stderr:write "Usage: atlas az <name-or-file> <workflow-id> [-i KEY=VAL ...]\n\n")
        (if (next named)
            (do
              (io.stderr:write "Configured Arazzo contexts:\n")
              (each [n v (pairs named)]
                (io.stderr:write (.. "  " n "\t" (or v.file "") "\n"))))
            (io.stderr:write "No Arazzo contexts configured in ~/.config/atlas/config.json\n")))
      (os.exit 1))
    (let [config (load-config)
          named (?. config :arazzo name-or-file)
          file (if named named.file name-or-file)
          profiles (or (?. config :profiles) {})
          profile-name (or p.profile (?. named :profile))
          profile (when (and profile-name (. profiles profile-name))
                    (resolve-profile profile-name profiles {}))
          (ok doc) (pcall arazzo.load-doc file)]
      (assert ok (tostring doc))
      (if (not workflow-id)
          (list-arazzo-workflows doc)
          p.help
          (let [wf (accumulate [found nil _ w (ipairs (or doc.workflows []))]
                     (if (= w.workflowId workflow-id) w found))]
            (if wf
                (print (help.build-workflow wf (arazzo.workflow-inputs doc wf)
                                            (arazzo.positional-inputs wf)))
                (die (.. "Unknown workflow: " workflow-id))))
          (let [wf (accumulate [found nil _ w (ipairs (or doc.workflows []))]
                     (if (= w.workflowId workflow-id) w found))
                pp-names (if wf (arazzo.positional-inputs wf) [])
                inputs (let [base (collect [k v (pairs (or (?. named :inputs)
                                                           {}))]
                                    k
                                    v)]
                         (each [j name (ipairs pp-names)]
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
                           (build-body fields
                                       (when wf (arazzo.workflow-inputs doc wf))
                                       base)))
                mode (or p.arazzo-output (if p.verbose :progress :final))
                no-color (or p.no-color (?. config :no-color))
                output (or p.output (?. config :output))
                run-opts (client-options profile-name profile p config)
                use-color (not no-color)
                dim (fn [s] (if use-color (.. "\27[2m" s "\27[0m") s))
                green (fn [s] (if use-color (.. "\27[32m" s "\27[0m") s))
                red (fn [s] (if use-color (.. "\27[31m" s "\27[0m") s))
                on-step (when (or (= mode :progress) (= mode :full))
                          (let [render #(render $ output use-color)]
                            (fn [info]
                              (match info.status
                                :running (io.stderr:write (.. (dim "→") " "
                                                              info.step "\n"))
                                :done (do
                                        (io.stderr:write (.. (green "✓") " "
                                                             info.step
                                                             (if info.elapsed
                                                                 (string.format "  %.3fs"
                                                                                info.elapsed)
                                                                 "")
                                                             (if (and info.response
                                                                      info.response.status)
                                                                 (.. "  HTTP "
                                                                     info.response.status)
                                                                 "")
                                                             "\n"))
                                        (when (and info.outputs
                                                   (next info.outputs))
                                          (io.stderr:write (.. (render info.outputs)
                                                               "\n"))))))))]
            (tset run-opts :on-step on-step)
            (tset run-opts :max-gotos p.max-gotos)
            (let [t0 (socket.gettime)
                  clients (arazzo.build-clients doc run-opts file)
                  (ok result) (pcall arazzo.run-workflow doc workflow-id inputs
                                     clients run-opts)
                  elapsed (- (socket.gettime) t0)]
              (when (or (= mode :progress) (= mode :full))
                (if ok
                    (io.stderr:write (.. (green "✓") " workflow " workflow-id
                                         (string.format "  %.3fs" elapsed) "\n"))
                    (io.stderr:write (.. (red "✗") " workflow " workflow-id
                                         " failed"
                                         (string.format "  %.3fs" elapsed) "\n"))))
              (if ok
                  (print-arazzo-result result mode output no-color)
                  (die (tostring result)))))))))

(fn run-op [p]
  (when (not p.schema)
    (let [config (load-config)
          profiles (or (?. config :profiles) {})]
      (io.stderr:write "Usage: atlas op <profile-or-schema> [operation] [args...]\n\n")
      (if (next profiles)
          (do
            (io.stderr:write "Configured profiles:\n")
            (each [n v (pairs profiles)]
              (io.stderr:write (.. "  " n "\t" (or v.schema "(no schema)") "\n"))))
          (io.stderr:write "No profiles configured in ~/.config/atlas/config.json\n")))
    (os.exit 1))
  (let [config (load-config)
        profiles (or (?. config :profiles) {})
        profile (when (and p.schema (. profiles p.schema))
                  (resolve-profile p.schema profiles {}))
        raw-schema (or (?. profile :schema) p.schema)
        ttl (or p.cache-ttl (?. profile :cache-ttl) 3600)
        no-color (or p.no-color (?. profile :no-color) (?. config :no-color))
        output (or p.output (?. profile :output) (?. config :output))
        verbose (or p.verbose (?. profile :verbose) (?. config :verbose))
        opts (client-options p.schema profile p config)
        schema (if (and (= (type raw-schema) :string)
                        (raw-schema:match "^https?://"))
                   (load-schema-cached raw-schema ttl p.reload opts.ssl
                                       opts.headers)
                   raw-schema)]
    (when (= (type schema) :table)
      (tset opts :source-url raw-schema))
    (when p.servers
      (let [loaded (if (= (type schema) :string) (atlas.load-schema schema)
                       schema)]
        (print (format-servers (atlas.servers loaded) (or opts.server-index 1)
                               (or opts.server-vars {})))
        (os.exit 0)))
    (let [(ok-c c) (pcall atlas.client schema opts)]
      (when (not ok-c)
        (die (.. "failed to build client: " (tostring c))))
      (if p.list
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
            (let [request (op-request op p)
                  all-headers (collect [k v (pairs (or opts.headers {}))]
                                k
                                v)]
              (each [k v (pairs (or request.headers {}))]
                (tset all-headers k v))
              (let [(param-errors warnings) (check-params op
                                                          {:query request.query
                                                           :headers all-headers})
                    errors (icollect [_ e (ipairs param-errors)] e)]
                (each [_ e (ipairs (check-body op request.body))]
                  (table.insert errors e))
                (each [_ w (ipairs warnings)]
                  (io.stderr:write (.. "warning: " w "\n")))
                (when (and (next errors) (not p.no-validate))
                  (die (.. (table.concat errors "\n")
                           "\n(use --no-validate to send anyway)"))))
              (let [t0 (socket.gettime)
                    (ok-r resp) (pcall op.invoke request)
                    elapsed (- (socket.gettime) t0)]
                (if ok-r
                    (os.exit (print-resp resp output no-color verbose p.select
                                         elapsed p.ignore-status))
                    (die (.. "request failed: " (tostring resp)))))))
          (list-ops c)))))

(fn run [args]
  (when (= (. args 1) "__complete")
    (run-complete args)
    (os.exit 0))
  (let [p (parse-args args)]
    (when (not p.cmd)
      (usage)
      (os.exit 0))
    (match p.cmd
      :completion (match p.schema
                    :fish (completion-fish)
                    :bash (completion-bash)
                    :zsh (completion-zsh)
                    _ (die "Usage: atlas completion <fish|bash|zsh>"))
      :profile (run-profile p.schema p.operation (load-config))
      :auth (run-auth p.schema p (load-config))
      (where (or :az :arazzo)) (run-arazzo p)
      :op (run-op p)
      _ (die (.. "Unknown command: " (tostring p.cmd)
                 "\nUsage: atlas <op|az|profile|auth|completion> ...")))))

(fn main [args]
  (let [(ok err) (pcall run args)]
    (when (not ok) (die (tostring err)))))

{: main
 : parse-args
 : build-body
 : op-request
 : format-output
 : client-options
 : redact-header
 : strip-location
 : exit-code
 : retry-options
 : request-text
 : curl-command
 : decode-body
 : paginate-options
 : format-servers
 : check-params
 : check-body
 : complete-line}

{: main}
