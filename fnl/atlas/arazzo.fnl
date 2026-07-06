(local atlas (require :atlas))
(local expr (require :atlas.arazzo.expr))
(local json (require :lunajson))
(local http-mod (require :atlas.http))
(local socket (require :socket))
(local util (require :atlas.util))

;; ---- loading ----

(fn load-doc [path]
  "Load and parse an Arazzo document from a local path or http(s):// URL."
  (let [content (if (path:match "^https?://")
                    (let [resp (http-mod.request {:method :GET :url path :headers {}})]
                      (assert (and (>= resp.status 200) (< resp.status 300))
                              (.. "failed to fetch arazzo doc: HTTP " resp.status))
                      (if (= (type resp.body) :string)
                          resp.body
                          (json.encode resp.body)))
                    (let [(f err) (io.open path :r)]
                      (assert f (.. "cannot open arazzo file: " (tostring err)))
                      (let [c (f:read :*a)] (f:close) c)))
        (ok parsed) (pcall json.decode content)]
    (assert ok (.. "failed to parse arazzo document: " (tostring parsed)))
    parsed))

;; ---- client building ----

(fn build-path-index [schema client]
  "Build a {\"method /path\" → op-fn} index from schema paths."
  (let [index {}]
    (each [path methods (pairs (or schema.paths {}))]
      (each [method op-spec (pairs methods)]
        (when (and (= (type op-spec) :table) op-spec.operationId)
          (let [op-fn (. client (util.camel->kebab op-spec.operationId))]
            (when op-fn
              (tset index (.. method " " path) op-fn))))))
    index))

(fn build-clients [doc ?opts]
  "Returns {sourceName → atlas-client} for openapi sourceDescriptions.
   Clients table also has a __path_index key: {sourceName → {\"method /path\" → op-fn}}."
  (let [clients {}
        path-index {}]
    (each [_ src (ipairs (or doc.sourceDescriptions []))]
      (when (= src.type :openapi)
        (let [(ok c) (pcall atlas.client src.url (or ?opts {}))]
          (if ok
              (do
                (tset clients src.name c)
                (let [(ok2 schema) (pcall atlas.load-schema src.url)]
                  (when ok2
                    (tset path-index src.name (build-path-index schema c)))))
              (io.stderr:write (.. "warning: could not build client for source '"
                                   src.name "': " (tostring c) "\n"))))))
    (tset clients :__path_index path-index)
    clients))

;; ---- operation lookup ----

(fn find-op [clients op-id]
  "Find a client operation by operationId across all clients.
   op-id may be a plain string or a $sourceDescriptions sentinel."
  (if (and (= (type op-id) :table) op-id.__source)
      ;; explicit source: $sourceDescriptions.name.opId
      (let [c (. clients op-id.__source)]
        (when c (. c op-id.__operationId)))
      ;; plain string — first-match across all clients
      (do
        (var found nil)
        (each [k c (pairs clients) &until found]
          (when (not= k :__path_index)
            (let [op (. c op-id)]
              (when op (set found op)))))
        found)))

(fn decode-pointer-seg [s]
  (-> s (: :gsub "~1" "/") (: :gsub "~0" "~")))

(fn find-op-by-path [ctx clients op-path-expr]
  "Resolve an operationPath expression to an op-fn.
   Expression format: '{$sourceDescriptions.NAME.url}#/paths/~1foo/method'"
  (let [;; extract source name from {$sourceDescriptions.NAME.url} prefix
        src-name (op-path-expr:match "{%$sourceDescriptions%.([^%.}]+)%.[^}]+}")
        ;; extract the JSON pointer fragment after #
        ptr      (op-path-expr:match "#(.+)$")]
    (assert src-name (.. "operationPath: cannot parse source name from: " op-path-expr))
    (assert ptr      (.. "operationPath: missing # fragment in: " op-path-expr))
    ;; pointer is /paths/~1foo~1{id}/method — split into segments
    (let [segs []]
      (each [s (ptr:gmatch "[^/]+")]
        (table.insert segs s))
      ;; segs[1]="paths", segs[2]=encoded-path, segs[3]=method
      (assert (and (= (. segs 1) "paths") (. segs 2) (. segs 3))
              (.. "operationPath: expected /paths/<path>/<method>, got: " ptr))
      (let [api-path (decode-pointer-seg (. segs 2))
            method   (. segs 3)
            key      (.. method " " api-path)
            index    (?. clients :__path_index src-name)]
        (assert index (.. "operationPath: no path index for source '" src-name "'"))
        (. index key)))))

;; ---- parameter resolution ----

(fn resolve-params [ctx params]
  "Resolve parameter list into {path=[], query={}, headers={}, body=nil}.
   Returns separate tables for each location."
  (let [result {:path [] :query {} :headers {} :body nil}]
    (each [_ p (ipairs (or params []))]
      (let [v (expr.eval ctx p.value)]
        (match p.in
          :path   (table.insert result.path v)
          :query  (tset result.query p.name v)
          :header (tset result.headers (p.name:lower) v)
          :body   (tset result :body v)
          ;; no :in — workflow input mapping
          _ (when (not p.in) (tset (or ctx.inputs {}) p.name v)))))
    result))

;; ---- step execution ----

(fn resolve-outputs [ctx outputs]
  (let [result {}]
    (each [k expr-str (pairs (or outputs {}))]
      (tset result k (expr.eval ctx expr-str)))
    result))

(fn max-gotos [] 50)

(fn execute-step [ctx clients step workflow-params on-step]
  "Execute a single step. Updates ctx in place. Returns the response."
  (let [step-id step.stepId
        ;; merge workflow params then step params
        merged-params (let [all []]
                        (each [_ p (ipairs (or workflow-params []))]
                          (table.insert all p))
                        (each [_ p (ipairs (or step.parameters []))]
                          (table.insert all p))
                        all)
        resolved (resolve-params ctx merged-params)]

    ;; resolve request body: step.requestBody overrides param body
    (let [body (if (and step.requestBody step.requestBody.payload)
                   (expr.eval ctx step.requestBody.payload)
                   resolved.body)
          op (if step.operationId
                 (find-op clients (expr.eval ctx step.operationId))
                 step.workflowId
                 nil  ;; handled by caller
                 step.operationPath
                 (find-op-by-path ctx clients step.operationPath)
                 nil)]

      (when (and (not op) (not step.workflowId))
        (error (.. "step '" step-id "': operation not found: "
                   (tostring (or step.operationId step.operationPath "?")))))

      (when on-step (on-step {:step step-id :status :running}))

      (let [t0 (socket.gettime)
            call-args (icollect [_ v (ipairs resolved.path)] v)
            req-opts (let [o {}]
                       (when (next resolved.query) (tset o :query resolved.query))
                       (when (next resolved.headers) (tset o :headers resolved.headers))
                       (when step.timeout (tset o :timeout step.timeout))
                       (when (next o) o))]
        (when body (table.insert call-args body))
        (when req-opts (table.insert call-args req-opts))
        (let [(ok resp) (pcall op (table.unpack call-args))
              elapsed (- (socket.gettime) t0)]
          (assert ok (.. "step '" step-id "' request failed: " (tostring resp)))
          ;; store in context
          (let [op-ref (or step.operationId step.operationPath)]
            (tset ctx.steps step-id
                  {:response resp
                   :request  {:body body :headers (or resolved.headers {})}
                   :op-ref   op-ref
                   :outputs  {}
                   :elapsed  elapsed}))
          ;; update current response/request in ctx for criterion eval
          (tset ctx :response resp)
          (tset ctx :request {:body body :headers (or resolved.headers {})})
          (when on-step
            (let [outputs (resolve-outputs ctx step.outputs)]
              (on-step {:step step-id :status :done
                        :op-ref  (or step.operationId step.operationPath)
                        :outputs outputs
                        :response resp :elapsed elapsed})))
          resp)))))

;; ---- workflow execution ----

(fn run-workflow [doc workflow-id inputs clients ?opts]
  (let [workflows (collect [_ w (ipairs (or doc.workflows []))]
                    w.workflowId w)
        wf (. workflows workflow-id)]
    (assert wf (.. "workflow not found: " workflow-id))
    (let [on-step (?. ?opts :on-step)
          ctx {:inputs (or inputs {})
               :steps {}
               :workflows {}
               :response nil
               :request nil}
          steps wf.steps
          step-index (collect [i s (ipairs steps)] s.stepId i)
          goto-counts {}]

      (var i 1)
      (while (<= i (length steps))
        (let [step (. steps i)
              step-id step.stepId]

          (if step.workflowId
              ;; sub-workflow step
              (let [sub-inputs (let [t {}]
                                 (each [_ p (ipairs (or step.parameters []))]
                                   (tset t p.name (expr.eval ctx p.value)))
                                 t)
                    sub-result (run-workflow doc step.workflowId sub-inputs clients ?opts)]
                (tset ctx.steps step-id
                      {:outputs sub-result.outputs
                       :response nil :request nil})
                (set i (+ i 1)))

              ;; operation step
              (let [resp (execute-step ctx clients step (or wf.parameters []) on-step)
                    success? (expr.eval-criteria ctx (or step.successCriteria []))
                    actions (if success?
                                (or step.onSuccess [])
                                (or step.onFailure []))]
                ;; resolve step outputs
                (let [step-outputs (resolve-outputs ctx step.outputs)]
                  (tset (. ctx.steps step-id) :outputs step-outputs))

                ;; process actions
                (var jumped false)
                (each [_ action (ipairs actions) &until jumped]
                  (let [action-ok? (expr.eval-criteria ctx (or action.criteria []))]
                    (when action-ok?
                      (match action.type
                        :end  (do
                                (set i (+ (length steps) 1))
                                (set jumped true))
                        :goto (let [target (or action.stepId action.workflowId)]
                                (let [n (+ 1 (or (. goto-counts target) 0))]
                                  (tset goto-counts target n)
                                  (assert (< n (max-gotos))
                                          (.. "goto loop detected at: " target)))
                                (when (and action.stepId (= action.stepId step-id) action.retryAfter)
                                  (socket.sleep action.retryAfter))
                                (if action.stepId
                                    (let [idx (. step-index action.stepId)]
                                      (assert idx (.. "goto: unknown step: " action.stepId))
                                      (set i idx)
                                      (set jumped true))
                                    action.workflowId
                                    (do
                                      (run-workflow doc action.workflowId inputs clients ?opts)
                                      (set i (+ (length steps) 1))
                                      (set jumped true))))
                        :retry (error "retry action: use onFailure with retryLimit — not yet supported")
                        _ nil))))

                (when (not jumped)
                  (when (not success?)
                    (let [status (tostring (or (?. resp :status) "?"))
                          body   (let [b (?. resp :body)]
                                   (if (= (type b) :table)
                                       (.. " " (json.encode b))
                                       (if b (.. " " (tostring b)) "")))]
                      (error (.. "step '" step-id "' failed success criteria"
                                 " (HTTP " status body ")"))))
                  (set i (+ i 1)))))))

      {:outputs (resolve-outputs ctx wf.outputs)
       :steps ctx.steps
       :ctx ctx})))

;; ---- public API ----

(fn run [path workflow-id inputs ?opts]
  "Load an Arazzo document and execute a workflow.
   ?opts: { clients, http-fn, ssl, headers, timeout, on-step }"
  (let [doc (load-doc path)
        clients (or (?. ?opts :clients)
                    (build-clients doc (collect [k v (pairs (or ?opts {}))]
                                         (when (not= k :on-step) (values k v)))))]
    (run-workflow doc workflow-id (or inputs {}) clients ?opts)))

{: load-doc : build-clients : run-workflow : run}
