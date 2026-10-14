;; ABOUTME: Usage text, the option table, and shell completion: the __complete
;; ABOUTME: backend plus the fish, bash and zsh scripts that call it.
(local atlas (require :atlas))
(local arazzo (require :atlas.arazzo))
(local util (require :atlas.util))
(local http-mod (require :atlas.http))
(local {: field-prefixes : options : option-by-name} (require :atlas.cli.args))
(local {: load-config : load-schema-cached : find-profile}
       (require :atlas.cli.settings))

;; ---- options and completion ----
(fn shown [o]
  "How usage displays an option."
  (or o.shown (let [name (. o.names 1)]
                (match o.value
                  nil name
                  :number (.. name "=N")
                  :body (.. name "=JSON")
                  :inputs (.. name "=JSON")
                  _ (.. name "=" (or o.arg "VALUE"))))))

(fn completion [o]
  "What flag completion offers for an option, or nil for short-only ones."
  (or o.family (let [long (accumulate [found nil _ n (ipairs o.names)
                                       &until found]
                            (when (n:match "^%-%-") n))]
                 (when long
                   (if o.value (.. long "=") long)))))

(fn scope-options [scope]
  (icollect [_ o (ipairs options)]
    (when (or (= o.scope scope) (= o.scope :any))
      {:shown (shown o) :complete (completion o) :help o.help})))

(fn usage []
  (print "Usage: atlas <command> [args...] [options]")
  (print "")
  (print "Commands:")
  (print "  op  <profile-or-schema> [operation] [path-params...]  Run an API operation")
  (print "  az  <name-or-file> [workflow-id] [path-params...]     Run an Arazzo workflow")
  (print "  profile <list|show> [name]                            Manage profiles")
  (print "  profile import-restish [FILE] [--dry-run]             Add profiles from a Restish config")
  (print "  auth    <profile> [--logout]                          Authenticate a profile")
  (print "  completion <fish|bash|zsh>                            Print shell completion")
  (print "  --version                                             Print the version")
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

(fn split-line [line]
  "(words current positional): the words before the cursor, the word being
typed, and the positional words (values of `--name value` options skipped)."
  (let [words (icollect [w (line:gmatch "%S+")] w)
        current (if (or (= line "") (line:match "%s$")) "" (table.remove words))
        positional []]
    (var skip false)
    (each [_ w (ipairs words)]
      (if skip (set skip false)
          (?. option-by-name w :value) (set skip true)
          (not (w:match "^%-")) (table.insert positional w)))
    (values words current positional)))

(fn completion-context [ctx words [cmd target name]]
  "What the line refers to: an op schema's operations, server and current
operation, or an Arazzo document's workflow and inputs."
  (let [config (or ctx.config {})
        c {}]
    (when (and (= cmd :op) target)
      (let [(_ profile) (pcall find-profile config target)
            (ok schema) (pcall ctx.load-schema (or (?. profile :schema) target))]
        (when (and ok (= (type schema) :table))
          (let [index-flag (accumulate [v nil _ w (ipairs words)]
                             (or (w:match "^%-%-server%-index=(%d+)$") v))
                index (or (tonumber index-flag) (?. profile :server-index) 1)]
            (set c.ops (op-entries schema))
            (set c.server (. (atlas.servers schema) index))
            (set c.op (when name (. c.ops name)))))))
    (when (and (= cmd :az) target)
      (let [(ok doc) (pcall ctx.load-doc
                            (or (?. config :arazzo target :file) target))]
        (when (and ok (= (type doc) :table))
          (set c.doc doc)
          (set c.workflow (arazzo.find-workflow doc name))
          (set c.inputs
               (when c.workflow (arazzo.workflow-inputs doc c.workflow))))))
    c))

(fn positional-entries [config positional context]
  (let [[cmd target] positional
        n (length positional)
        profiles (icollect [_ p (ipairs (sorted-keys config.profiles))]
                   {:value p})]
    (if (= nil cmd) (icollect [_ c (ipairs [:auth :az :completion :op :profile])]
                      {:value c})
        (and (or (= cmd :op) (= cmd :auth)) (= n 1)) profiles
        (and (= cmd :profile) (= n 1))
        [{:value :import-restish} {:value :list} {:value :show}]
        (and (= cmd :profile) (= n 2) (= target :show)) profiles
        (and (= cmd :completion) (= n 1))
        [{:value :bash} {:value :fish} {:value :zsh}] (and (= cmd :op) (= n 2))
        (icollect [_ op-name (ipairs (sorted-keys context.ops))]
          {:value op-name :help (?. context.ops op-name :summary)})
        (and (= cmd :az) (= n 1)) (icollect [_ a (ipairs (sorted-keys config.arazzo))]
                                   {:value a})
        (and (= cmd :az) (= n 2))
        (icollect [_ wf (ipairs (or (?. context :doc :workflows) []))]
          {:value wf.workflowId :help wf.summary}) [])))

(fn complete-entries [line ctx]
  "Completion candidates {:value :help} for a command line typed up to the cursor."
  (let [(words current positional) (split-line line)
        cmd (. positional 1)
        context (completion-context ctx words positional)
        (prefix rest) (current:match "^%-%-(%a+)%.(.*)$")
        entries (if prefix
                    (let [kind (. field-prefixes prefix)]
                      (if kind ((field-entries prefix kind context) rest) []))
                    (current:match "^%-")
                    (icollect [_ o (ipairs (scope-options (match cmd
                                                            :az :az
                                                            :auth :auth
                                                            _ :op)))]
                      (when o.complete {:value o.complete :help o.help}))
                    (positional-entries (or ctx.config {}) positional context))
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
  ;; candidates come from the spec: read them as data, one per line, and
  ;; never pass them to compgen -W, which would expand $(...) in them
  (print "  local c cands=()")
  (print "  while IFS= read -r c; do cands+=(\"$c\"); done < <(atlas __complete \"$line\" 2>/dev/null)")
  (print "  # bash splits words at '=': complete only the part after it")
  (print "  if [[ \"$cur\" == \"=\" ]]; then cur=\"\"; fi")
  (print "  if [[ \"${line##* }\" == *=* ]]; then")
  (print "    local stripped")
  (print "    stripped=()")
  (print "    for c in \"${cands[@]}\"; do stripped+=(\"${c#*=}\"); done")
  (print "    cands=(\"${stripped[@]}\")")
  (print "  fi")
  (print "  COMPREPLY=()")
  (print "  for c in \"${cands[@]}\"; do [[ \"$c\" == \"$cur\"* ]] && COMPREPLY+=(\"$c\"); done")
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
                                (load-schema-cached src
                                                    {:transport http-mod.request})
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
