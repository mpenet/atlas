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
      (let [schema ((or opts.load-schema atlas.load-schema) url opts.ssl
                                                            opts.headers)
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
          (if ok
              (tset clients src.name c)
              (io.stderr:write (.. "warning: could not build client for source '"
                                   src.name "': " (tostring c) "\n")))))
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
      ;; plain string — first-match across all clients
      (find-op clients #(= $.operation-id op-id))))

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

(fn run-workflow [doc workflow-id inputs clients ?opts]
  (let [workflows (collect [_ w (ipairs (or doc.workflows []))]
                    w.workflowId
                    w)
        wf (. workflows workflow-id)]
    (assert wf (.. "workflow not found: " workflow-id))
    (let [stack (or (?. ?opts :workflow-stack) [])
          _ (each [_ active (ipairs stack)]
              (when (= active workflow-id)
                (error (.. "workflow cycle: " (table.concat stack " -> ")
                           " -> " workflow-id) 0)))
          ?opts (doto (collect [k v (pairs (or ?opts {}))]
                        k
                        v)
                  (tset :workflow-stack
                        (doto (icollect [_ w (ipairs stack)] w)
                          (table.insert workflow-id))))
          on-step (?. ?opts :on-step)
          max-gotos (or (?. ?opts :max-gotos) 50)
          ctx {:inputs (or inputs {})
               :request nil
               :response nil
               :steps {}
               :workflows {}}
          step-order []
          steps wf.steps
          step-index (collect [i s (ipairs steps)] s.stepId i)
          wf-params (expand-references doc wf.parameters)
          goto-counts {}
          retry-counts {}
          run-sub (fn [sub-id sub-inputs]
                    (let [sub (run-workflow doc sub-id sub-inputs clients ?opts)]
                      (each [k v (pairs sub.ctx.workflows)]
                        (tset ctx.workflows k v))
                      (tset ctx.workflows sub-id {:outputs sub.outputs})
                      sub))]
      ;; workflows listed in dependsOn run first, once each, with the same inputs
      (each [_ dep (ipairs (or wf.dependsOn []))]
        (when (= nil (. ctx.workflows dep))
          (run-sub dep inputs)))

      (fn run-step [step]
        "Run one step; returns {:ok bool :response resp :error message}."
        (if step.workflowId
            ;; sub-workflow step: its outputs become the step's outputs
            (let [sub-inputs (collect [_ p (ipairs (expand-references doc
                                                                      step.parameters))]
                               p.name
                               (expr.eval ctx p.value))
                  (ok sub) (pcall run-sub step.workflowId sub-inputs)]
              (tset ctx.steps step.stepId
                    {:outputs (if ok sub.outputs {})
                     :request nil
                     :response nil})
              (if ok {:ok true} {:ok false :error sub}))
            ;; operation step: merge workflow params then step params
            (let [params (util.merge-parameters wf-params
                                                (expand-references doc
                                                                   step.parameters))]
              {:ok true
               :response (execute-step ctx clients step params on-step)})))

      (fn next-index [i step success?]
        "Index of the step to run after step i, by the first action that
applies; nil when a failure is left unhandled."
        (let [actions (if success?
                          (merge-actions (expand-references doc
                                                            wf.successActions)
                                         (expand-references doc step.onSuccess))
                          (merge-actions (expand-references doc
                                                            wf.failureActions)
                                         (expand-references doc step.onFailure)))
              step-id step.stepId]
          (var next-i (if success? (+ i 1) nil))
          (var decided false)
          (each [_ action (ipairs actions) &until decided]
            (when (expr.eval-criteria ctx action.criteria)
              (match action.type
                :end (do
                       (set next-i (+ (length steps) 1))
                       (set decided true))
                :goto (let [target (or action.stepId action.workflowId)
                            n (+ 1 (or (. goto-counts target) 0))]
                        (tset goto-counts target n)
                        (assert (<= n max-gotos)
                                (.. "goto loop detected at: " target))
                        (when (and action.stepId (= action.stepId step-id)
                                   action.retryAfter)
                          (socket.sleep action.retryAfter))
                        (if action.stepId
                            (let [idx (. step-index action.stepId)]
                              (assert idx
                                      (.. "goto: unknown step: " action.stepId))
                              (set next-i idx))
                            (do
                              (run-sub action.workflowId inputs)
                              (set next-i (+ (length steps) 1))))
                        (set decided true))
                :retry (let [n (+ 1 (or (. retry-counts step-id) 0))]
                         (when (<= n (or action.retryLimit 1))
                           (tset retry-counts step-id n)
                           (when (and action.retryAfter (> action.retryAfter 0))
                             (socket.sleep action.retryAfter))
                           (when action.workflowId
                             (run-sub action.workflowId inputs))
                           (set next-i i)
                           (set decided true))))))
          next-i))

      (var i 1)
      (while (<= i (length steps))
        (let [step (. steps i)
              step-id step.stepId
              outcome (run-step step)
              success? (and outcome.ok
                            (expr.eval-criteria ctx step.successCriteria))]
          (table.insert step-order step-id)
          (when step.outputs
            (tset (. ctx.steps step-id) :outputs
                  (resolve-outputs ctx step.outputs)))
          (when success?
            (tset retry-counts step-id nil))
          (let [next-i (next-index i step success?)]
            (when (= next-i nil)
              (error (failure-message step-id outcome) 0))
            (set i next-i))))
      {:ctx ctx
       :outputs (resolve-outputs ctx wf.outputs)
       :steps ctx.steps
       :step-order step-order})))

;; ---- introspection ----

(fn find-workflow [doc workflow-id]
  "The workflow with workflow-id in doc, or nil."
  (accumulate [found nil _ wf (ipairs (or doc.workflows [])) &until found]
    (when (= wf.workflowId workflow-id) wf)))

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
