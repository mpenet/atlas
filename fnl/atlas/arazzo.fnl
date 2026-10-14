;; ABOUTME: Executes Arazzo 1.0 workflows: resolves source clients and operations,
;; ABOUTME: runs steps, evaluates criteria and applies success/failure actions.
(local atlas (require :atlas))

(local expr (require :atlas.arazzo.expr))

(local json (require :lunajson))

(local yaml (require :atlas.yaml))

(local http-mod (require :atlas.http))

(local socket (require :socket))

(local util (require :atlas.util))

(local refs (require :atlas.refs))

;; ---- loading ----

(fn load-doc [path]
  "Load and parse an Arazzo document (JSON or YAML) from a local path or http(s):// URL."
  (let [(ok parsed) (pcall yaml.decode (http-mod.fetch-text path))]
    (assert ok (.. "failed to parse arazzo document: " (tostring parsed)))
    parsed))

;; ---- client building ----

(fn source-client [url opts server-vars used]
  "Client for one source, given only the server variables its schema
declares; records the variables it used in used."
  (if (= nil (next server-vars))
      (atlas.client url opts)
      (let [schema ((or opts.load-schema atlas.load-schema) url
                                                            {:ssl opts.ssl
                                                             :headers opts.headers})
            declared (or (?. schema :servers 1 :variables) {})
            own (collect [name value (pairs server-vars)]
                  (when (. declared name)
                    (tset used name true)
                    (values name value)))
            client-opts (collect [k v (pairs opts)] k v)]
        (tset client-opts :server-vars own)
        (tset client-opts :source-url url)
        (atlas.client schema client-opts))))

(fn build-clients [doc ?opts ?location]
  "Returns {sourceName → atlas-client} for openapi sourceDescriptions.
Relative source URLs resolve against ?location, the document's own path or URL."
  (let [clients {}
        sources (icollect [_ src (ipairs (or doc.sourceDescriptions []))]
                  (when (= src.type :openapi) src))]
    (when (and (?. ?opts :base-url) (> (length sources) 1))
      (error (.. "base-url override is ambiguous: the document has "
                 (length sources) " openapi sources") 0))
    (when (and (?. ?opts :server-index) (> (length sources) 1))
      (error (.. "server-index is ambiguous: the document has "
                 (length sources) " openapi sources") 0))
    (let [server-vars (or (?. ?opts :server-vars) {})
          used {}]
      (each [_ src (ipairs sources)]
        (let [url (if ?location (util.resolve-reference ?location src.url)
                      src.url)
              (ok c) (pcall source-client url (or ?opts {}) server-vars used)]
          (when (not ok)
            (error (.. "source '" src.name "': " (tostring c)) 0))
          (tset clients src.name c)))
      (each [name (pairs server-vars)]
        (when (not (. used name))
          (error (.. "no openapi source declares server variable '" name "'") 0))))
    clients))

;; ---- operation lookup ----

(fn find-op [clients pred ?source]
  "First operation satisfying pred, searching only ?source when given."
  (accumulate [found nil name client (pairs clients) &until found]
    (when (or (= nil ?source) (= name ?source))
      (accumulate [op-found nil _ op (pairs client) &until op-found]
        (when (and (= (type op) :table) op.invoke (pred op))
          op)))))

(fn find-op-by-id [clients op-id]
  "Resolve an operationId, plain or $sourceDescriptions-qualified."
  (if (and (= (type op-id) :table) op-id.__source)
      ;; explicit source: $sourceDescriptions.name.opId
      (do
        (assert (. clients op-id.__source)
                (.. "unknown source '" op-id.__source "'"))
        (find-op clients #(= $.operation-id op-id.__operationId) op-id.__source))
      ;; plain string: must be unique across sources
      (let [sources (doto (icollect [name (pairs clients)]
                            (when (find-op clients #(= $.operation-id op-id)
                                           name)
                              name))
                      (table.sort))]
        (when (> (length sources) 1)
          (error (string.format "operationId '%s' is in several sources (%s): use $sourceDescriptions.NAME.%s"
                                op-id (table.concat sources ", ") op-id)
                 0))
        (find-op clients #(= $.operation-id op-id) (. sources 1)))))

(fn find-op-by-path [clients op-path-expr]
  "Resolve an operationPath expression to an operation.
Expression format: '{$sourceDescriptions.NAME.url}#/paths/~1foo/method'"
  (let [;; extract source name from {$sourceDescriptions.NAME.url} prefix
        src-name (op-path-expr:match "{%$sourceDescriptions%.([^%.}]+)%.[^}]+}")
        ;; extract the JSON pointer fragment after #
        ptr (op-path-expr:match "#(.+)$")]
    (assert src-name (.. "operationPath: cannot parse source name from: "
                         op-path-expr))
    (assert ptr (.. "operationPath: missing # fragment in: " op-path-expr))
    (assert (. clients src-name) (.. "operationPath: unknown source '" src-name
                                     "'"))
    ;; pointer is /paths/~1foo~1{id}/method — split into segments
    (let [segs (icollect [seg (ptr:gmatch "[^/]+")] seg)]
      ;; segs[1]="paths", segs[2]=encoded-path, segs[3]=method
      (assert (and (= (. segs 1) "paths") (. segs 2) (. segs 3))
              (.. "operationPath: expected /paths/<path>/<method>, got: " ptr))
      (let [api-path (util.unescape-pointer (. segs 2))
            method (: (. segs 3) :lower)]
        (find-op clients #(and (= $.path api-path) (= $.method method))
                 src-name)))))

;; ---- parameter resolution ----

(fn resolve-params [ctx params]
  "Evaluate parameters into {:path {} :query {} :headers {}} keyed by name."
  (let [result {:headers {} :path {} :query {}}
        cookies []]
    (each [_ p (ipairs params)]
      (let [v (expr.eval ctx p.value)]
        (match p.in
          :path (tset result.path p.name v)
          :query (tset result.query p.name v)
          :header (tset result.headers (p.name:lower) v)
          :cookie (table.insert cookies (.. p.name "=" (tostring v))))))
    (when (next cookies)
      (tset result.headers :cookie (table.concat cookies "; ")))
    result))

(fn resolve-outputs [ctx outputs]
  (let [result {}]
    (each [k expr-str (pairs (or outputs {}))]
      (tset result k (expr.eval ctx expr-str)))
    result))

;; ---- step execution ----

(fn execute-step [ctx clients step params on-step]
  "Execute a single step with resolved parameter objects. Updates ctx in place.
Returns the response."
  (let [step-id step.stepId
        resolved (resolve-params ctx params)
        body (when step.requestBody
               (expr.eval ctx step.requestBody.payload))
        op-ref (or step.operationId step.operationPath)
        op (if step.operationId
               (find-op-by-id clients (expr.eval ctx step.operationId))
               (find-op-by-path clients step.operationPath))
        request {:body body
                 :headers resolved.headers
                 :path resolved.path
                 :query (when (next resolved.query) resolved.query)
                 :timeout step.timeout}]
    (when (not op)
      (error (.. "step '" step-id "': operation not found: " (tostring op-ref))))
    (tset request :method (op.method:upper))
    (tset request :url (op.url-for request))
    (when on-step
      (on-step {:status :running :step step-id}))
    (let [t0 (socket.gettime)
          (ok resp) (pcall op.invoke request)
          elapsed (- (socket.gettime) t0)]
      (assert ok (.. "step '" step-id "' request failed: " (tostring resp)))
      ;; store in context
      (tset ctx.steps step-id {:elapsed elapsed
                               :op-ref op-ref
                               :outputs {}
                               :request request
                               :response resp})
      ;; update current response/request in ctx for criterion eval
      (tset ctx :response resp)
      (tset ctx :request request)
      (when on-step
        (on-step {:elapsed elapsed
                  :op-ref op-ref
                  :outputs (resolve-outputs ctx step.outputs)
                  :response resp
                  :status :done
                  :step step-id}))
      resp)))

;; ---- workflow execution ----

(fn expand-reference [doc item]
  "Replace a Reusable Object {:reference \"$components.KIND.NAME\"} with its
target; a :value on the reference overrides the target parameter's value."
  (if (and (= (type item) :table) item.reference)
      (let [(kind name) (item.reference:match "^%$components%.([^%.]+)%.(.+)$")
            target (?. doc :components kind name)]
        (assert target (.. "unresolved reference: " item.reference))
        (if (= nil item.value)
            target
            (doto (collect [k v (pairs target)] k v)
              (tset :value item.value))))
      item))

(fn expand-references [doc items]
  (icollect [_ item (ipairs (or items []))]
    (expand-reference doc item)))

(fn merge-actions [workflow-actions step-actions]
  "Step actions first, then workflow actions not overridden by name."
  (let [overridden (collect [_ a (ipairs step-actions)]
                     (when a.name (values a.name true)))
        out (icollect [_ a (ipairs step-actions)] a)]
    (each [_ a (ipairs workflow-actions)]
      (when (not (and a.name (. overridden a.name)))
        (table.insert out a)))
    out))

(fn failure-message [step-id outcome]
  (if outcome.error
      (.. "step '" step-id "' failed: " (tostring outcome.error))
      (let [resp outcome.response
            b (?. resp :body)
            body (if (= (type b) :table) (.. " " (json.encode b))
                     b (.. " " (tostring b))
                     "")]
        (.. "step '" step-id "' failed success criteria (HTTP "
            (tostring (or (?. resp :status) "?")) body ")"))))

(fn find-workflow [doc workflow-id]
  "The workflow with workflow-id in doc, or nil."
  (accumulate [found nil _ wf (ipairs (or doc.workflows [])) &until found]
    (when (= wf.workflowId workflow-id) wf)))

(fn enter-workflow [workflow-id ?opts]
  "?opts with workflow-id pushed on the running-workflow stack; a workflow
already on the stack means a cycle (dependsOn or a step calling itself)."
  (let [stack (or (?. ?opts :workflow-stack) [])]
    (each [_ active (ipairs stack)]
      (when (= active workflow-id)
        (error (.. "workflow cycle: " (table.concat stack " -> ") " -> "
                   workflow-id) 0)))
    (doto (collect [k v (pairs (or ?opts {}))]
            k
            v)
      (tset :workflow-stack
            (doto (icollect [_ w (ipairs stack)] w)
              (table.insert workflow-id))))))

(fn run-step [run step]
  "Run one step; returns {:ok bool :response resp :error message}."
  (if step.workflowId
      ;; sub-workflow step: its outputs become the step's outputs
      (let [sub-inputs (collect [_ p (ipairs (expand-references run.doc
                                                                step.parameters))]
                         p.name
                         (expr.eval run.ctx p.value))
            (ok sub) (pcall run.run-sub step.workflowId sub-inputs)]
        (tset run.ctx.steps step.stepId
              {:outputs (if ok sub.outputs {}) :request nil :response nil})
        (if ok {:ok true} {:ok false :error sub}))
      ;; operation step: merge workflow params then step params
      (let [params (util.merge-parameters run.wf-params
                                          (expand-references run.doc
                                                             step.parameters))]
        {:ok true
         :response (execute-step run.ctx run.clients step params run.on-step)})))

(fn goto-action [run action step]
  "Index of the step a goto action continues at."
  (let [target (or action.stepId action.workflowId)
        n (+ 1 (or (. run.goto-counts target) 0))]
    (tset run.goto-counts target n)
    (assert (<= n run.max-gotos) (.. "goto loop detected at: " target))
    (when (and action.stepId (= action.stepId step.stepId) action.retryAfter)
      (socket.sleep action.retryAfter))
    (if action.stepId
        (or (. run.step-index action.stepId)
            (error (.. "goto: unknown step: " action.stepId) 0))
        (do
          (run.run-sub action.workflowId run.inputs)
          (+ (length run.steps) 1)))))

(fn retry-action [run action i step]
  "i to run the step again, or nil once retryLimit is used up."
  (let [n (+ 1 (or (. run.retry-counts step.stepId) 0))]
    (when (<= n (or action.retryLimit 1))
      (tset run.retry-counts step.stepId n)
      (when (and action.retryAfter (> action.retryAfter 0))
        (socket.sleep action.retryAfter))
      (when action.workflowId
        (run.run-sub action.workflowId run.inputs))
      i)))

(fn next-index [run i step success?]
  "Index of the step to run after step i, by the first action that applies;
nil when a failure is left unhandled."
  (let [wf run.wf
        actions (if success?
                    (merge-actions (expand-references run.doc wf.successActions)
                                   (expand-references run.doc step.onSuccess))
                    (merge-actions (expand-references run.doc wf.failureActions)
                                   (expand-references run.doc step.onFailure)))
        chosen (accumulate [found nil _ action (ipairs actions) &until found]
                 (when (expr.eval-criteria run.ctx action.criteria)
                   (match action.type
                     :end [(+ (length run.steps) 1)]
                     :goto [(goto-action run action step)]
                     :retry (match (retry-action run action i step)
                              again [again]))))]
    (if chosen (. chosen 1)
        success? (+ i 1)
        nil)))

(fn run-workflow [doc workflow-id inputs clients ?opts]
  (let [wf (or (find-workflow doc workflow-id)
               (error (.. "workflow not found: " workflow-id) 0))
        opts (enter-workflow workflow-id ?opts)
        ctx {:inputs (or inputs {})
             :request nil
             :response nil
             :steps {}
             :workflows {}}
        run {: doc
             : wf
             : clients
             : ctx
             :inputs (or inputs {})
             :steps (or wf.steps [])
             :step-index (collect [i s (ipairs (or wf.steps []))]
                           s.stepId
                           i)
             :wf-params (expand-references doc wf.parameters)
             :on-step opts.on-step
             :max-gotos (or opts.max-gotos 50)
             :goto-counts {}
             :retry-counts {}
             :run-sub (fn [sub-id sub-inputs]
                        (let [sub (run-workflow doc sub-id sub-inputs clients
                                                opts)]
                          (each [k v (pairs sub.ctx.workflows)]
                            (tset ctx.workflows k v))
                          (tset ctx.workflows sub-id {:outputs sub.outputs})
                          sub))}
        step-order []]
    ;; workflows listed in dependsOn run first, once each, with the same inputs
    (each [_ dep (ipairs (or wf.dependsOn []))]
      (when (= nil (. ctx.workflows dep))
        (run.run-sub dep run.inputs)))
    (var i 1)
    (while (<= i (length run.steps))
      (let [step (. run.steps i)
            outcome (run-step run step)
            success? (and outcome.ok
                          (expr.eval-criteria ctx step.successCriteria))]
        (table.insert step-order step.stepId)
        (when step.outputs
          (tset (. ctx.steps step.stepId) :outputs
                (resolve-outputs ctx step.outputs)))
        (when success?
          (tset run.retry-counts step.stepId nil))
        (set i
             (or (next-index run i step success?)
                 (error (failure-message step.stepId outcome) 0)))))
    {: ctx
     :outputs (resolve-outputs ctx wf.outputs)
     :steps ctx.steps
     : step-order}))

;; ---- introspection ----

(fn positional-inputs [wf]
  "Input names used as path parameters by the workflow's steps, in first-use
order; the CLI accepts these as positional arguments."
  (let [seen {}
        names []]
    (each [_ step (ipairs (or wf.steps []))]
      (each [_ param (ipairs (or step.parameters []))]
        (when (= param.in :path)
          (let [input-name (and (= (type param.value) :string)
                                (param.value:match "^%$inputs%.(.+)$"))]
            (when (and input-name (not (. seen input-name)))
              (tset seen input-name true)
              (table.insert names input-name))))))
    names))

(fn workflow-inputs [doc wf]
  "The workflow's inputs JSON Schema with $refs resolved, or nil."
  (when wf.inputs
    ((refs.resolver doc) wf.inputs)))

;; ---- public API ----

(fn run [path workflow-id inputs ?opts]
  "Load an Arazzo document and execute a workflow.
?opts: { clients, http-fn, ssl, headers, timeout, base-url, on-step, max-gotos }"
  (let [doc (load-doc path)
        client-opts (collect [k v (pairs (or ?opts {}))]
                      (when (not= k :on-step) (values k v)))
        clients (or (?. ?opts :clients) (build-clients doc client-opts path))]
    (run-workflow doc workflow-id (or inputs {}) clients ?opts)))

{:build-clients build-clients
 :load-doc load-doc
 :run run
 :run-workflow run-workflow
 :find-workflow find-workflow
 :positional-inputs positional-inputs
 :workflow-inputs workflow-inputs}
