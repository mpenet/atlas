;; ABOUTME: Terminal output for the CLI: response rendering and selection, dry-run
;; ABOUTME: and curl printing, request logging with redaction, exit codes.
(local util (require :atlas.util))
(local http-mod (require :atlas.http))
(local json (require :atlas.json))
(local pretty-mod (require :atlas.pretty))

(fn redact-header [name value ?names]
  "Value safe to print for header name: credentials are masked, as are the
headers in the set ?names (lowercase)."
  (let [n (name:lower)]
    (if (or (= n "authorization") (= n "proxy-authorization"))
        (let [(scheme) (: (tostring value) :match "^(%S+)%s")]
          (if scheme (.. scheme " <redacted>") "<redacted>"))
        (or (util.secret-name? n) (?. ?names n))
        "<redacted>"
        value)))

(fn sensitive-names [names]
  "Set of the lowercased names authentication marked on a request."
  (collect [_ n (ipairs (or names []))]
    (n:lower)
    true))

(fn sorted-headers [headers]
  (let [names (icollect [k (pairs (or headers {}))]
                k)]
    (table.sort names)
    (icollect [_ k (ipairs names)]
      [k (tostring (. headers k))])))

(fn wrap-log-request [http-fn]
  (fn [req]
    (io.stderr:write (.. "> " (or req.method "?") " "
                         (util.redact-url (util.append-query (or req.url "?")
                                                             (or req.query {})
                                                             req.query-styles)
                                          req.sensitive-query)
                         "\n"))
    (when req.body
      (io.stderr:write (.. "> body: "
                           (if (= (type req.body) :table)
                               (json.encode req.body)
                               (tostring req.body))
                           "\n")))
    (each [_ [k v] (ipairs (sorted-headers req.headers))]
      (io.stderr:write (.. "> " k ": "
                           (tostring (redact-header k v
                                                    (sensitive-names req.sensitive-headers)))
                           "\n")))
    (http-fn req)))

(fn op? [v]
  (and (= (type v) :table) (not= nil (. v :has-body))))

(fn list-ops [c]
  (let [ops []]
    (each [k v (pairs c)]
      (when (op? v)
        (table.insert ops {:k k :summary (. v :summary)})))
    (table.sort ops (fn [a b] (< a.k b.k)))
    (let [width (accumulate [w 0 _ op (ipairs ops)]
                  (math.max w (length op.k)))]
      (each [_ op (ipairs ops)]
        (print (util.printable (if op.summary
                                   (string.format (.. "%-" width "s  %s") op.k
                                                  op.summary)
                                   op.k)))))))

(fn container? [v]
  "Whether a path can go into v: an array or object, not null."
  (and (= (type v) :table) (not= v json.null)))

(fn pick-fields [value fields]
  "value with only fields kept: an object, or each object of an array."
  (let [pick (fn [obj]
               (collect [_ f (ipairs fields)] f (. obj f)))]
    (when (container? value)
      (if (or (json.array? value) (= (type (. value 1)) :table))
          (json.array (icollect [_ obj (ipairs value)]
                        (when (= (type obj) :table) (pick obj))))
          (pick value)))))

(fn select-path [data path]
  "Value at path in data: .field, [N] (0-based), [] to map the rest of the path
over an array, {a,b} to keep fields. nil when the path doesn't match."
  (if (or (= nil data) (= path "")) data (path:match "^%.")
      (select-path data (path:sub 2)) (path:match "^%[%]")
      (when (container? data)
        (json.array (icollect [_ v (ipairs data)] (select-path v (path:sub 3)))))
      (path:match "^%[%d+%]")
      (let [(index rest) (path:match "^%[(%d+)%](.*)$")]
        (when (container? data)
          (select-path (. data (+ 1 (tonumber index))) rest)))
      (path:match "^{")
      (let [(fields rest) (path:match "^{([^}]+)}(.*)$")]
        (when (and fields (container? data))
          (let [picked (pick-fields data
                                    (icollect [f (fields:gmatch "[^,]+")]
                                      (f:match "^%s*(.-)%s*$")))]
            (if (and (= (type (. picked 1)) :table) (not= rest ""))
                (json.array (icollect [_ obj (ipairs picked)]
                              (select-path obj rest)))
                (select-path picked rest)))))
      (let [(key rest) (path:match "^([^%.%[{]+)(.*)$")]
        (when (and key (container? data))
          (select-path (. data key) rest)))))

(fn request-text [req]
  "Human-readable request, credentials redacted."
  (let [(url payload headers) (http-mod.encode-request req)
        lines [(.. req.method " " (util.redact-url url req.sensitive-query))]]
    (each [_ [k v] (ipairs (sorted-headers headers))]
      (table.insert lines
                    (.. k ": "
                        (redact-header k v
                                       (sensitive-names req.sensitive-headers)))))
    (when payload
      (table.insert lines "")
      (table.insert lines payload))
    (table.concat lines "\n")))

(fn curl-command [req]
  "Runnable curl command reproducing the request."
  (let [(url payload headers) (http-mod.encode-request req)
        parts ["curl" "-X" req.method (util.shell-quote url)]]
    (assert (not (and payload (payload:find "\0" 1 true)))
            "--curl cannot inline a binary body; use --dry-run to inspect it")
    (each [_ [k v] (ipairs (sorted-headers headers))]
      (table.insert parts "-H")
      (table.insert parts (util.shell-quote (.. k ": " v))))
    (when payload
      (table.insert parts "--data-raw")
      (table.insert parts (util.shell-quote payload)))
    (table.concat parts " ")))

(fn printing-transport [render]
  "Transport that prints each request instead of sending it."
  (fn [req]
    (print (render req))
    {:status 0 :headers {} :dry-run true}))

(fn render [v fmt use-color]
  "Render a decoded value as yaml or (default) json."
  (if (= fmt :yaml)
      (let [s (pretty-mod.yaml v 0 use-color)]
        (if (s:match "^\n") (s:sub 2) s))
      (pretty-mod.pretty v 0 use-color)))

(fn header-lines [headers ?redact]
  "Headers as sorted \"name: value\" lines; ?redact masks credentials."
  (table.concat (icollect [_ [k v] (ipairs (sorted-headers headers))]
                  (.. k ": " (if ?redact (tostring (redact-header k v)) v)))
                "\n"))

(fn format-output [resp output use-color ?select]
  "Text to print for a successful response, or nil when there is nothing to show."
  (let [body (if (and ?select resp.body) (select-path resp.body ?select)
                 resp.body)]
    (match (or output :json)
      :status (tostring resp.status)
      :headers (header-lines resp.headers)
      :raw (if ?select
               (when (not= nil body)
                 (if (= (type body) :table) (render body :json false)
                     (tostring body)))
               (when (and resp.raw (> (length resp.raw) 0))
                 resp.raw))
      fmt (when (not= nil body) (render body fmt use-color)))))

(fn exit-code [status ignore-status]
  "Process exit code for an HTTP status: 4 for 4xx, 5 for 5xx, else 0."
  (if (or ignore-status (< status 400)) 0
      (< status 500) 4
      5))

(fn print-http-resp [resp
                     output
                     no-color
                     verbose
                     ?select
                     ?elapsed
                     ?ignore-status]
  (let [error? (and resp.status (>= resp.status 400) (not ?ignore-status))
        use-color (not no-color)
        timing (if ?elapsed (string.format "  %.3fs" ?elapsed) "")]
    (when resp.next-page-status
      (io.stderr:write (string.format "warning: stopped after %d page(s): next page returned HTTP %s\n"
                                      resp.pages resp.next-page-status)))
    (when (or verbose error?)
      (io.stderr:write (.. "HTTP " resp.status timing "\n"))
      (when verbose
        (io.stderr:write (.. (header-lines resp.headers true) "\n\n"))))
    (if error?
        (do
          (when (not= nil resp.body)
            (io.stderr:write (.. (if (= (type resp.body) :string) resp.body
                                     (render resp.body :json use-color))
                                 "\n")))
          (exit-code resp.status false))
        (let [text (format-output resp output use-color ?select)]
          (if text
              (print text)
              (when (not verbose)
                (io.stderr:write (.. "HTTP " resp.status "\n"))))
          0))))

(fn print-resp [resp output no-color verbose ?select ?elapsed ?ignore-status]
  "Print a response; returns the process exit code."
  (if resp.dry-run 0
      (print-http-resp resp output no-color verbose ?select ?elapsed
                       ?ignore-status)))

(fn strip-location [msg]
  "Remove Lua error location prefixes (file.lua:N: or [string \"chunk\"]:N:)."
  (let [(s) (: (tostring msg) :gsub "[^%s:]+%.lua:%d+: " "")
        (s) (s:gsub "%[string \"[^\"]*\"%]:%d+: " "")]
    s))

(local exit-mt {:__tostring #$.message})

(fn exit [code ?message]
  "Stop the current command with an exit code; run prints ?message to stderr."
  (error (setmetatable {:code code :message (or ?message "")} exit-mt) 0))

(fn exit-status [err]
  "(code message) for an error raised while running a command."
  (if (= (getmetatable err) exit-mt)
      (values err.code err.message)
      (values 1 (strip-location (tostring err)))))

(fn die [msg]
  (exit 1 (strip-location (tostring msg))))

(fn executed-steps [result]
  "Step ids in the order they first ran."
  (let [seen {}]
    (icollect [_ id (ipairs result.step-order)]
      (when (not (. seen id))
        (tset seen id true)
        id))))

(fn show-value [v]
  (if (= v "") "\"\"" (tostring v)))

(fn format-servers [servers selected vars]
  "Servers with their variables; * marks the selected server, and each
variable shows the value in effect."
  (let [lines []]
    (each [i s (ipairs servers)]
      (table.insert lines
                    (.. (if (= i selected) "* " "  ") i ". " s.url
                        (if s.description (.. " — " s.description) "")))
      (let [names (icollect [name (pairs s.variables)] name)]
        (table.sort names)
        (each [_ name (ipairs names)]
          (let [v (. s.variables name)
                value (let [given (. vars name)]
                        (if (not= nil given) given v.default))]
            (table.insert lines (.. "       " name " = " (show-value value)
                                    "  (default: " (show-value v.default)
                                    (if v.enum
                                        (.. "; one of: "
                                            (table.concat (icollect [_ e (ipairs v.enum)]
                                                            (show-value e))
                                                          ", "))
                                        "")
                                    ")"))))))
    (table.concat lines "\n")))

(fn print-step [raw-step-id step render full]
  (local step-id (util.printable raw-step-id))
  (if full
      (do
        (print (.. "--- " step-id " request ---"))
        (when step.op-ref
          (print (.. "operation: " (util.printable (tostring step.op-ref)))))
        (when (and step.request step.request.body)
          (print (render step.request.body)))
        (print (.. "--- " step-id " response"
                   (if (and step.response step.response.status)
                       (.. " HTTP " step.response.status)
                       "") " ---")))
      (print (.. "--- " step-id " ---")))
  (when step.response (print (render step.response.body))))

(fn print-arazzo-result [result mode output no-color]
  (let [render #(render $ output (not no-color))
        has-outputs (next (or result.outputs {}))]
    (match (or mode :final)
      ;; progress already went to stderr while the workflow ran
      (where (or :final :progress))
      (when has-outputs
        (print (render result.outputs)))
      (where (or :steps :full))
      (do
        (each [_ step-id (ipairs (executed-steps result))]
          (print-step step-id (. result.steps step-id) render (= mode :full)))
        (when has-outputs
          (print "--- outputs ---")
          (print (render result.outputs)))))))

(fn list-arazzo-workflows [doc]
  (let [wfs (or doc.workflows [])]
    (when (= (length wfs) 0)
      (print "(no workflows)"))
    (let [width (accumulate [w 0 _ wf (ipairs wfs)]
                  (math.max w (length wf.workflowId)))]
      (each [_ wf (ipairs wfs)]
        (print (util.printable (if wf.summary
                                   (string.format (.. "%-" width "s  %s")
                                                  wf.workflowId wf.summary)
                                   wf.workflowId)))))))

{: redact-header
 : wrap-log-request
 : op?
 : list-ops
 : select-path
 : sorted-headers
 : request-text
 : curl-command
 : printing-transport
 : render
 : header-lines
 : format-output
 : exit-code
 : print-http-resp
 : print-resp
 : strip-location
 : die
 : exit
 : exit-status
 : executed-steps
 : show-value
 : format-servers
 : print-arazzo-result
 : list-arazzo-workflows}
