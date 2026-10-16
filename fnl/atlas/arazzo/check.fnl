;; ABOUTME: Checks an Arazzo document without running it: what steps call, their
;; ABOUTME: parameters and bodies, references, conditions and actions.
(local arazzo (require :atlas.arazzo))
(local expr (require :atlas.arazzo.expr))
(local iregexp (require :atlas.iregexp))
(local jsonpath (require :atlas.jsonpath))
(local json (require :atlas.json))

(local locations {:path true
                  :query true
                  :header true
                  :cookie true
                  :querystring true})

;; an empty run: expressions resolve to nothing, but unknown ones still raise
(local empty-ctx {:inputs {} :steps {} :workflows {} :outputs {}})

(fn keys-of [t]
  (collect [k (pairs (if (= (type t) :table) t {}))]
    k
    true))

(fn component [doc reference]
  "The component $components.KIND.NAME names, or nil."
  (let [(kind name) (reference:match "^%$components%.([^%.]+)%.(.+)$")]
    (?. doc :components kind name)))

(fn expressions-in [s]
  "The runtime expressions in string s: all of it, or the ones in {}."
  (if (s:match "^%$%a") [s] (icollect [e (s:gmatch "{(%$[^}]+)}")]
                              e)))

(fn condition-expressions [condition]
  (icollect [e (condition:gmatch "%$[^%s()=!<>&|]+")]
    e))

(fn checker [doc clients]
  "{:problems [] :report (fn [level where message])} and the checks of doc."
  (let [problems []
        workflows (collect [_ wf (ipairs (or doc.workflows []))]
                    (when (= (type wf.workflowId) :string)
                      (values wf.workflowId wf)))
        sources (collect [_ src (ipairs (or doc.sourceDescriptions []))]
                  (when src.name (values src.name true)))]
    (fn report [level where message]
      (table.insert problems {: level : where : message}))

    (fn input-names [wf]
      "The names of wf's inputs, or nil when its schema doesn't list them."
      (let [(ok schema) (pcall arazzo.workflow-inputs doc wf)]
        (when (and ok (= (type schema) :table)
                   (= (type schema.properties) :table))
          (keys-of schema.properties))))

    (fn output-names [step]
      "The names of step's outputs: its own, else a workflow step's workflow's."
      (if step.outputs (keys-of step.outputs)
          step.workflowId (keys-of (?. workflows step.workflowId :outputs))
          {}))

    (fn check-reference [scope where e]
      "Report what expression e refers to that doesn't exist."
      (let [(ok err) (pcall expr.resolve-expr empty-ctx e)]
        (when (not ok)
          (report :error where (tostring err))))
      (let [name #(e:match (.. "^%$" $ "%.([^#]+)"))]
        (match (e:match "^%$(%a+)")
          :inputs (let [input (name :inputs)
                        names (input-names scope.wf)]
                    (when (and input names (not (. names input)))
                      (report :error where
                              (.. "no input '" input "' in workflow "
                                  scope.wf.workflowId))))
          :steps (let [(id part rest) (e:match "^%$steps%.([^%.]+)%.(%a+)(.*)$")
                       target (when id (. scope.steps id))]
                   (if (and id (not target))
                       (report :error where (.. "unknown step '" id "'"))
                       (and target (= part :outputs))
                       (let [output (rest:match "^%.([^#]+)")]
                         (when (and output
                                    (not (. (output-names target) output)))
                           (report :error where
                                   (.. "step '" id "' has no output '" output
                                       "'"))))))
          :workflows (let [(id part rest) (e:match "^%$workflows%.([^%.]+)%.(%a+)(.*)$")
                           target (when id (. workflows id))]
                       (if (and id (not target))
                           (report :error where
                                   (.. "unknown workflow '" id "'"))
                           (and target (= part :outputs))
                           (let [output (rest:match "^%.([^#]+)")]
                             (when (and output
                                        (not (. (keys-of target.outputs) output)))
                               (report :error where
                                       (.. "workflow '" id "' has no output '"
                                           output "'"))))))
          :outputs (let [output (name :outputs)]
                     (when (and output
                                (not (. (keys-of scope.wf.outputs) output)))
                       (report :error where
                               (.. "workflow " scope.wf.workflowId
                                   " has no output '" output "'"))))
          :sourceDescriptions (let [source (e:match "^%$sourceDescriptions%.([^%.]+)")]
                                (when (and source (not (. sources source)))
                                  (report :error where
                                          (.. "unknown source '" source "'")))))))

    (fn check-value [scope where v]
      "Check the expressions anywhere in v: a string, a Selector Object or
data holding them."
      (if (= (type v) :string)
          (each [_ e (ipairs (expressions-in v))]
            (check-reference scope where e))
          (expr.selector-object? v)
          (do
            (check-value scope where v.context)
            (let [(ok kind) (pcall expr.expression-type v.type)]
              (if (not ok) (report :error where (tostring kind))
                  (and (= kind :jsonpath) (not (v.selector:find "{$" 1 true)))
                  (let [(ok err) (pcall jsonpath.compile v.selector)]
                    (when (not ok)
                      (report :error where (tostring err)))))))
          (and (= (type v) :table) (not= v json.null))
          (each [_ item (pairs v)]
            (check-value scope where item))))

    (fn check-criteria [scope where criteria]
      (each [_ c (ipairs (or criteria []))]
        (let [condition (tostring c.condition)
              (ok kind) (pcall expr.expression-type (or c.type :simple))
              ;; runtime expressions inside are only known when running
              embedded (condition:find "{$" 1 true)]
          (if (not ok) (report :error where (tostring kind)) (= kind :simple)
              (let [(_ problem) (expr.eval-criterion empty-ctx c)]
                (if problem (report :error where problem)
                    (each [_ e (ipairs (condition-expressions condition))]
                      (check-reference scope where e))))
              (do
                (check-value scope where c.context)
                (each [_ e (ipairs (expressions-in condition))]
                  (check-reference scope where e))
                (when (not embedded)
                  (let [(ok err) (pcall (if (= kind :regex)
                                            #(iregexp.compile condition
                                                              {:ecmascript true})
                                            #(jsonpath.compile condition)))]
                    (when (not ok)
                      (report :error where (tostring err))))))))))

    (fn expand [where items]
      "items with their references replaced by the components they name."
      (icollect [_ item (ipairs (or items []))]
        (if (and (= (type item) :table) item.reference)
            (let [target (component doc item.reference)]
              (if target
                  (if (= nil item.value) target
                      (doto (collect [k v (pairs target)] k v)
                        (tset :value item.value)))
                  (report :error where (.. "unknown component " item.reference))))
            item)))

    (fn check-actions [scope where-of actions]
      (each [_ a (ipairs actions)]
        (let [where (where-of a)]
          (match a.type
            :end nil
            (where (or :goto :retry)) (do
                                        (when (and a.stepId
                                                   (not (. scope.steps a.stepId)))
                                          (report :error where
                                                  (.. a.type
                                                      " to unknown step '"
                                                      a.stepId "'")))
                                        (when (and a.workflowId
                                                   (not (a.workflowId:match "^%$"))
                                                   (not (. workflows
                                                           a.workflowId)))
                                          (report :error where
                                                  (.. "unknown workflow '"
                                                      a.workflowId "'")))
                                        (when (and (= a.type :goto)
                                                   (not a.stepId)
                                                   (not a.workflowId))
                                          (report :error where
                                                  "goto needs a stepId or a workflowId")))
            _ (report :error where "type must be end, goto or retry"))
          (check-criteria scope where a.criteria)
          (each [_ p (ipairs (or a.parameters []))]
            (check-value scope where p.value)))))

    (fn check-operation [where op params body]
      "Report what step's parameters and body get wrong about operation op."
      (let [declared (collect [_ p (ipairs (or op.parameters []))]
                       (when (and p.name p.in)
                         (values (.. p.in ":" p.name) p)))
            given (collect [_ p (ipairs params)]
                    (when (and p.name p.in)
                      (values (.. p.in ":" p.name) true)))
            name (or op.operation-id op.name "the operation")]
        (each [_ path-param (ipairs (or op.path-params []))]
          (tset declared (.. "path:" path-param)
                (or (. declared (.. "path:" path-param))
                    {:name path-param :in :path :required true})))
        (each [key p (pairs declared)]
          (when (and (or p.required (= p.in :path)) (not (. given key)))
            (report :error where
                    (.. "required " p.in " parameter '" p.name "' is missing"))))
        (each [_ p (ipairs params)]
          (when (and p.name (. locations p.in) (not= p.in :querystring)
                     (not (. declared (.. p.in ":" p.name))))
            (report :warning where
                    (.. name " has no " p.in " parameter '" p.name "'"))))
        (if (and body (not op.has-body))
            (report :warning where (.. name " takes no request body"))
            (and (not body) (?. op :spec :requestBody :required))
            (report :error where (.. name " requires a request body")))))

    (fn check-step [scope step]
      (let [where (.. scope.wf.workflowId " › step " (tostring step.stepId))
            targets (accumulate [n 0 _ k (ipairs [:operationId
                                                  :operationPath
                                                  :workflowId])]
                      (if (. step k) (+ n 1) n))
            params (expand where
                           (doto (icollect [_ p (ipairs scope.wf-params)] p)
                             (#(each [_ p (ipairs (or step.parameters []))]
                                 (table.insert $ p)))))]
        (if (= targets 0)
            (report :error where
                    "calls nothing: give an operationId, operationPath or workflowId")
            (> targets 1)
            (report :error where
                    "calls both an operation and a workflow: give only one")
            step.workflowId
            (when (and (not (step.workflowId:match "^%$"))
                       (not (. workflows step.workflowId)))
              (report :error where
                      (.. "unknown workflow '" step.workflowId "'")))
            (let [ref (or step.operationId step.operationPath)
                  (ok op) (pcall #(if step.operationId
                                      (arazzo.find-op-by-id clients
                                                            (expr.eval empty-ctx
                                                                       step.operationId))
                                      (arazzo.find-op-by-path clients
                                                              step.operationPath)))]
              (if (not ok) (report :error where (tostring op)) (not op)
                  (report :error where
                          (.. "operation not found: " (tostring ref)))
                  (check-operation where op
                                   (icollect [_ p (ipairs params)]
                                     (when (= (type p) :table) p))
                                   step.requestBody))))
        (each [_ p (ipairs params)]
          (when (= (type p) :table)
            (when (not (. locations p.in))
              (when (not step.workflowId)
                (report :error where
                        (.. "parameter '" (tostring p.name)
                            "': 'in' must be path, query, header, cookie or querystring"))))
            (check-value scope where p.value)))
        (when step.requestBody
          (check-value scope where step.requestBody.payload)
          (each [_ r (ipairs (or step.requestBody.replacements []))]
            (check-value scope where r.value)))
        (check-criteria scope where step.successCriteria)
        (each [kind actions (pairs {:onSuccess [step.onSuccess
                                                scope.wf.successActions]
                                    :onFailure [step.onFailure
                                                scope.wf.failureActions]})]
          (check-actions scope
                         #(.. where " › " kind " " (tostring (or $.name "")))
                         (expand where
                                 (doto (icollect [_ a (ipairs (or (. actions 1)
                                                                  []))]
                                         a)
                                   (#(each [_ a (ipairs (or (. actions 2) []))]
                                       (table.insert $ a)))))))
        (each [_ v (pairs (or step.outputs {}))]
          (check-value scope where v))))

    (fn check-workflow [wf]
      (let [where (tostring wf.workflowId)
            steps {}]
        (each [_ step (ipairs (or wf.steps []))]
          (when (. steps step.stepId)
            (report :error (.. where " › step " (tostring step.stepId))
                    "stepId used twice"))
          (tset steps step.stepId step))
        (each [_ dep (ipairs (or wf.dependsOn []))]
          (when (and (not (dep:match "^%$")) (not (. workflows dep)))
            (report :error where (.. "depends on unknown workflow '" dep "'"))))
        (let [scope {: wf : steps :wf-params (or wf.parameters [])}]
          (each [_ step (ipairs (or wf.steps []))]
            (check-step scope step))
          (each [_ v (pairs (or wf.outputs {}))]
            (check-value scope where v)))))

    (let [seen {}]
      (each [_ wf (ipairs (or doc.workflows []))]
        (if (. seen wf.workflowId)
            (report :error (tostring wf.workflowId) "workflowId used twice")
            (do
              (tset seen wf.workflowId true)
              (check-workflow wf)))))
    problems))

(fn check [doc clients]
  "What is wrong in Arazzo document doc, whose sources are clients, found
without running it: [{:level :error|:warning :where :message}]."
  (checker doc clients))

{: check}
