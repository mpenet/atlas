;; ABOUTME: Usage text, the option table, and shell completion: the __complete
;; ABOUTME: backend plus the fish, bash and zsh scripts that call it.
(local atlas (require :atlas))
(local arazzo (require :atlas.arazzo))
(local util (require :atlas.util))
(local {: field-prefixes} (require :atlas.cli.args))
(local {: load-config : load-schema-cached} (require :atlas.cli.settings))

;; ---- options and completion ----
(local options
       ;; [flag-as-shown flag-to-complete scope description]; scope is :op, :az or :any
       [["--list" "--list" :op "List all operations"]
        ["--help" "--help" :op "Show operation documentation"]
        ["--body=JSON"
         "--body="
         :op
         "Request body (inline JSON/YAML, @file, @-)"]
        ["-d JSON" nil :op "Alias for --body"]
        ["--body.KEY=VAL"
         "--b."
         :op
         "Body field, deep dot paths (short: --b.KEY=VAL)"]
        ["--query.KEY=VAL" "--q." :op "Query parameter (short: --q.KEY=VAL)"]
        ["--header.KEY=VAL"
         "--h."
         :op
         "Per-request header (short: --h.KEY=VAL)"]
        ["--timeout=N" "--timeout=" :any "Timeout in seconds"]
        ["--max-pages=N"
         "--max-pages="
         :op
         "Max pages to follow via Link rel=next (default: 25)"]
        ["--no-paginate" "--no-paginate" :op "Return only the first page"]
        ["--retry=N"
         "--retry="
         :any
         "Retries for 408/429/5xx and network errors (default: 2)"]
        ["--retry-unsafe"
         "--retry-unsafe"
         :any
         "Also retry POST/PUT/PATCH/DELETE"]
        ["--retry-max-wait=N"
         "--retry-max-wait="
         :any
         "Max seconds to wait between retries (default: 300)"]
        ["--base-url=URL" "--base-url=" :any "Override base URL"]
        ["--servers"
         "--servers"
         :op
         "List the schema's servers and their variables"]
        ["--server-index=N"
         "--server-index="
         :any
         "Use the schema's Nth server (default: 1)"]
        ["--server.NAME=VAL"
         "--server."
         :any
         "Set a server URL variable (e.g. --server.zone=de-fra-1)"]
        ["--output=FORMAT"
         "--output="
         :any
         "json (default), yaml, raw, status or headers"]
        ["--select=PATH"
         "--select="
         :op
         "Select nested value (e.g. .items[0].name, .items[].{id,name})"]
        ["--no-color" "--no-color" :any "Disable colored output"]
        ["-v, --verbose" "--verbose" :any "Show status, headers and requests"]
        ["--reload" "--reload" :op "Re-fetch and re-cache the schema"]
        ["--ignore-status"
         "--ignore-status"
         :op
         "Treat HTTP error responses as output; exit 0"]
        ["--no-validate"
         "--no-validate"
         :op
         "Send even if required params are missing or the body is invalid"]
        ["--dry-run" "--dry-run" :op "Print the request instead of sending it"]
        ["--curl"
         "--curl"
         :op
         "Print an equivalent curl command instead of sending"]
        ["--cache-ttl=N"
         "--cache-ttl="
         :op
         "Schema cache TTL in seconds (default: 3600)"]
        ["--profile=NAME" "--profile=" :az "Profile for auth, TLS and headers"]
        ["-i KEY=VAL" nil :az "Workflow input"]
        ["--input.KEY=VAL" "--i." :az "Workflow input (short: --i.KEY=VAL)"]
        ["--inputs=JSON"
         "--inputs="
         :az
         "All inputs as a JSON/YAML object (or @file)"]
        ["--help"
         "--help"
         :az
         "Show a workflow's inputs and steps (or list workflows)"]
        ["--arazzo-output=MODE"
         "--arazzo-output="
         :az
         "final (default), steps, progress, full"]
        ["--max-gotos=N"
         "--max-gotos="
         :az
         "Max visits per goto target before aborting (default: 50)"]])

(fn scope-options [scope]
  (icollect [_ [shown complete opt-scope help] (ipairs options)]
    (when (or (= opt-scope scope) (= opt-scope :any))
      {: shown : complete : help})))

(fn usage []
  (print "Usage: atlas <command> [args...] [options]")
  (print "")
  (print "Commands:")
  (print "  op  <profile-or-schema> [operation] [path-params...]  Run an API operation")
  (print "  az  <name-or-file> [workflow-id] [path-params...]     Run an Arazzo workflow")
  (print "  profile <list|show> [name]                            Manage profiles")
  (print "  auth    <profile> [--logout]                          Authenticate a profile")
  (print "  completion <fish|bash|zsh>                            Print shell completion")
  (each [_ [title scope] (ipairs [["Options (op):" :op] ["Options (az):" :az]])]
    (print "")
    (print title)
    (each [_ o (ipairs (scope-options scope))]
      (print (string.format "  %-21s %s" o.shown o.help))))
  (print "")
  (print (.. "Config: " (util.config-dir) "/config.json")))

(fn sorted-keys [t]
  (doto (icollect [k (pairs (or t {}))]
          k)
    (table.sort)))

(fn op-entries [schema]
  "Operations of a schema keyed by CLI name, built like a real client."
  (let [(ok c) (pcall atlas.client schema
                      {:base-url "http://completion.invalid" :http-fn #nil})]
    (if ok c {})))

(fn enum-of [schema]
  (or (?. schema :enum) (?. schema :items :enum)))

(fn field-entries [prefix kind context]
  "Completion entries for --PREFIX.NAME=VALUE fields: names, or enum values
once a name and = are typed."
  (let [fields (match kind
                 :query (collect [_ p (ipairs (or (?. context :op :parameters)
                                                  []))]
                          (when (= p.in :query)
                            (values p.name
                                    {:enum (enum-of p.schema)
                                     :help p.description})))
                 :header (collect [_ p (ipairs (or (?. context :op :parameters)
                                                   []))]
                           (when (= p.in :header)
                             (values p.name
                                     {:enum (enum-of p.schema)
                                      :help p.description})))
                 :body (collect [name prop (pairs (or (?. context :op
                                                          :body-schema
                                                          :properties)
                                                      {}))]
                         (values name
                                 {:enum (enum-of prop) :help prop.description}))
                 :input (collect [name prop (pairs (or (?. context :inputs
                                                           :properties)
                                                       {}))]
                          (values name
                                  {:enum (enum-of prop) :help prop.description}))
                 :server (collect [name v (pairs (or (?. context :server
                                                         :variables)
                                                     {}))]
                           (values name {:enum v.enum :help v.description}))
                 _ {})]
    (fn [rest]
      (let [(name) (rest:match "^(.-)=")]
        (if name
            (icollect [_ v (ipairs (or (?. fields name :enum) []))]
              {:value (.. "--" prefix "." name "=" (tostring v))})
            (icollect [_ n (ipairs (sorted-keys fields))]
              {:value (.. "--" prefix "." n "=") :help (. fields n :help)}))))))

(fn complete-entries [line ctx]
  "Completion candidates {:value :help} for a command line typed up to the cursor."
  (let [words (icollect [w (line:gmatch "%S+")] w)
        current (if (or (= line "") (line:match "%s$")) "" (table.remove words))
        positional (let [out []]
                     (var skip false)
                     (each [_ w (ipairs words)]
                       (if skip (set skip false)
                           (or (= w "-d") (= w "-i")) (set skip true)
                           (not (w:match "^%-")) (table.insert out w)))
                     out)
        [cmd target name] positional
        config (or ctx.config {})
        profiles (or config.profiles {})
        flag-value (fn [flag]
                     (accumulate [v nil _ w (ipairs words)]
                       (or (w:match (.. "^%-%-" flag "=(.*)$")) v)))
        context (let [c {}]
                  (when (and (= cmd :op) target)
                    (let [src (or (?. profiles target :schema) target)
                          (ok schema) (pcall ctx.load-schema src)]
                      (when (and ok (= (type schema) :table))
                        (let [index (or (tonumber (or (flag-value "server%-index")
                                                      ""))
                                        (?. profiles target :server-index) 1)]
                          (set c.ops (op-entries schema))
                          (set c.server (. (atlas.servers schema) index))
                          (set c.op (when name (. c.ops name)))))))
                  (when (and (= cmd :az) target)
                    (let [file (or (?. config :arazzo target :file) target)
                          (ok doc) (pcall ctx.load-doc file)]
                      (when (and ok (= (type doc) :table))
                        (set c.doc doc)
                        (set c.workflow
                             (accumulate [found nil _ wf (ipairs (or doc.workflows
                                                                     []))]
                               (if (= wf.workflowId name) wf found)))
                        (set c.inputs
                             (when c.workflow
                               (arazzo.workflow-inputs doc c.workflow))))))
                  c)
        entries (if (current:match "^%-%-(%a+)%.")
                    (let [(prefix rest) (current:match "^%-%-(%a+)%.(.*)$")
                          kind (if (= prefix :server) :server
                                   (. field-prefixes prefix))]
                      (if kind ((field-entries prefix kind context) rest) []))
                    (current:match "^%-")
                    (icollect [_ o (ipairs (scope-options (if (= cmd :az) :az
                                                              :op)))]
                      (when o.complete {:value o.complete :help o.help}))
                    (= nil cmd)
                    (icollect [_ c (ipairs [:auth :az :completion :op :profile])]
                      {:value c})
                    (let [n (length positional)
                          profile-entries (icollect [_ name (ipairs (sorted-keys profiles))]
                                            {:value name})]
                      (if (and (or (= cmd :op) (= cmd :auth)) (= n 1))
                          profile-entries
                          (and (= cmd :profile) (= n 1))
                          [{:value :list} {:value :show}]
                          (and (= cmd :profile) (= n 2) (= target :show))
                          profile-entries
                          (and (= cmd :completion) (= n 1))
                          [{:value :bash} {:value :fish} {:value :zsh}]
                          (and (= cmd :op) (= n 2))
                          (icollect [_ op-name (ipairs (sorted-keys context.ops))]
                            {:value op-name
                             :help (?. context.ops op-name :summary)})
                          (and (= cmd :az) (= n 1))
                          (icollect [_ ctx-name (ipairs (sorted-keys config.arazzo))]
                            {:value ctx-name})
                          (and (= cmd :az) (= n 2))
                          (icollect [_ wf (ipairs (or (?. context :doc
                                                          :workflows)
                                                      []))]
                            {:value wf.workflowId :help wf.summary})
                          [])))
        matching (icollect [_ e (ipairs entries)]
                   (when (= current (e.value:sub 1 (length current)))
                     e))]
    (table.sort matching #(< $1.value $2.value))
    matching))

(fn complete-line [line ctx]
  "Completion candidates for a command line typed up to the cursor."
  (icollect [_ e (ipairs (complete-entries line ctx))]
    e.value))

(fn completion-fish []
  (print "# atlas fish completion — source this or put in ~/.config/fish/completions/atlas.fish")
  (print "complete -c atlas -f -a '(atlas __complete --describe (commandline -cp))'"))

(fn completion-bash []
  (print "# atlas bash completion — add to ~/.bashrc: eval \"$(atlas completion bash)\"")
  (print "_atlas_complete() {")
  (print "  local line=\"${COMP_LINE:0:COMP_POINT}\"")
  (print "  local cur=\"${COMP_WORDS[COMP_CWORD]}\"")
  (print "  local IFS=$'\\n'")
  (print "  local cands")
  (print "  cands=($(atlas __complete \"$line\" 2>/dev/null))")
  (print "  # bash splits words at '=': complete only the part after it")
  (print "  if [[ \"$cur\" == \"=\" ]]; then cur=\"\"; fi")
  (print "  if [[ \"${line##* }\" == *=* ]]; then")
  (print "    local stripped c")
  (print "    stripped=()")
  (print "    for c in \"${cands[@]}\"; do stripped+=(\"${c#*=}\"); done")
  (print "    cands=(\"${stripped[@]}\")")
  (print "  fi")
  (print "  COMPREPLY=($(compgen -W \"${cands[*]}\" -- \"$cur\"))")
  (print "  if [[ ${#COMPREPLY[@]} -eq 1 && \"${COMPREPLY[0]}\" == *[=.] ]] && type compopt &>/dev/null; then compopt -o nospace; fi")
  (print "}")
  (print "complete -F _atlas_complete atlas"))

(fn completion-zsh []
  (print "#compdef atlas")
  (print "# atlas zsh completion — add to fpath or source directly")
  (print "_atlas() {")
  (print "  local -a cands")
  (print "  cands=(${(f)\"$(atlas __complete \"${BUFFER[1,CURSOR]}\" 2>/dev/null)\"})")
  (print "  local -a open closed")
  (print "  local c")
  (print "  # no trailing space after NAME= and prefix. so the value can follow")
  (print "  for c in $cands; do")
  (print "    if [[ $c == *[=.] ]]; then open+=($c); else closed+=($c); fi")
  (print "  done")
  (print "  compadd -S '' -- ${open[@]}")
  (print "  compadd -- ${closed[@]}")
  (print "}")
  (print "compdef _atlas atlas"))

(fn run-complete [args]
  "Hidden backend for the shell completion scripts:
atlas __complete [--describe] LINE-UP-TO-CURSOR"
  (let [describe? (= (. args 2) "--describe")
        ;; shells pass the whole line, program name included
        line (: (or (. args (if describe? 3 2)) "") :match "^%s*%S+%s+(.*)$")
        ctx {:config (let [(ok cfg) (pcall load-config)] (if ok cfg {}))
             :load-schema (fn [src]
                            (if (src:match "^https?://")
                                (load-schema-cached src 3600 false)
                                (atlas.load-schema src)))
             :load-doc arazzo.load-doc}]
    (each [_ e (ipairs (if line (complete-entries line ctx) []))]
      (print (if (and describe? e.help)
                 (.. e.value "\t" (: (tostring e.help) :gsub "%s+" " "))
                 e.value)))))

{: options
 : scope-options
 : usage
 : sorted-keys
 : op-entries
 : enum-of
 : field-entries
 : complete-entries
 : complete-line
 : completion-fish
 : completion-bash
 : completion-zsh
 : run-complete}
