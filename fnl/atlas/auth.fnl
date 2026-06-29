(local json (require :lunajson))
(local http (require :atlas.http))
(local socket (require :socket))

;; ---- helpers ----

(fn cache-dir []
  (.. (or (os.getenv :HOME) ".") "/.cache/atlas/tokens"))

(fn token-path [profile-name]
  (.. (cache-dir) "/" profile-name ".json"))

(fn shell-quote [s]
  (.. "'" (: (tostring s) :gsub "'" "'\\''") "'"))

(fn url-encode [s]
  (: (tostring s) :gsub "[^%w%-%.%_%~]"
    (fn [c] (string.format "%%%02X" (string.byte c)))))

(fn form-encode [t]
  (let [parts []]
    (each [k v (pairs t)]
      (table.insert parts (.. (url-encode k) "=" (url-encode v))))
    (table.concat parts "&")))

(fn qs-append [base params]
  (.. base "?" (form-encode params)))

(fn expand-env [s]
  (if (and (= (type s) :string) (s:match "^env:(.+)"))
    (let [(var-name) (s:match "^env:(.+)")]
      (or (os.getenv var-name)
          (error (.. "environment variable not set: " var-name))))
    s))

(fn sha256-base64url [s]
  (let [tmp (os.tmpname)
        f (io.open tmp :w)]
    (when f
      (f:write s)
      (f:close)
      (let [h (io.popen (.. "openssl dgst -sha256 -binary " (shell-quote tmp)
                            " | openssl base64 | tr '+/' '-_' | tr -d '='"))
            result (when h (let [r (h:read :*l)] (h:close) r))]
        (os.remove tmp)
        (when (and result (> (length result) 0)) result)))))

(fn random-string [n]
  (let [chars "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
        nchars (length chars)
        out []
        f (io.open "/dev/urandom" :rb)]
    (if f
        (do (for [_ 1 n]
              (let [byte (string.byte (f:read 1))
                    i (+ 1 (% byte nchars))]
                (table.insert out (chars:sub i i))))
            (f:close))
        (do (math.randomseed (os.time))
            (for [_ 1 n]
              (let [i (math.random 1 nchars)]
                (table.insert out (chars:sub i i))))))
    (table.concat out)))

;; ---- token cache ----

(fn load-token [profile-name]
  (let [f (io.open (token-path profile-name) :r)]
    (when f
      (let [(ok data) (pcall json.decode (f:read :*a))]
        (f:close)
        (when (and ok data) data)))))

(fn save-token [profile-name data]
  (let [dir (cache-dir)
        path (token-path profile-name)]
    (os.execute (.. "mkdir -p " (shell-quote dir) " && chmod 700 " (shell-quote dir)))
    (let [f (io.open path :w)]
      (when f
        (f:write (json.encode data))
        (f:close)
        (os.execute (.. "chmod 600 " (shell-quote path)))))))

(fn clear-token [profile-name]
  (os.remove (token-path profile-name)))

(fn token-valid? [data]
  (and data
       data.access_token
       (or (not data.expires_at)
           (> data.expires_at (+ (os.time) 30)))))

;; ---- HTTP form post ----

(fn post-form [url params ssl]
  (let [body (form-encode params)]
    (http.request {:method :POST
                   :url url
                   :headers {:content-type "application/x-www-form-urlencoded"
                              :accept "application/json"}
                   :raw-body body
                   :ssl (or ssl {})})))

(fn store-token [resp profile-name]
  (assert (and (>= resp.status 200) (< resp.status 300))
          (let [detail (when (= (type resp.body) :table)
                         (or resp.body.error_description resp.body.error ""))]
            (.. "token request failed: HTTP " resp.status
                (if (and detail (> (length detail) 0)) (.. " — " detail) ""))))
  (let [body (if (= (type resp.body) :table)
                 resp.body
                 (let [(ok decoded) (pcall json.decode resp.body)]
                   (assert ok (.. "token response is not JSON: " (tostring resp.body)))
                   decoded))
        data {:access_token body.access_token
              :token_type (or body.token_type "Bearer")}]
    (when body.expires_in
      (tset data :expires_at (+ (os.time) body.expires_in)))
    (when body.refresh_token
      (tset data :refresh_token body.refresh_token))
    (save-token profile-name data)
    data))

;; ---- refresh ----

(fn try-refresh [profile-name params ssl cached]
  (let [(ok resp) (pcall post-form params.token_url
                         {:grant_type "refresh_token"
                          :refresh_token cached.refresh_token
                          :client_id (expand-env params.client_id)}
                         ssl)]
    (when (and ok (>= resp.status 200) (< resp.status 300))
      (store-token resp profile-name))))

;; ---- client credentials ----

(fn client-credentials [profile-name params ssl]
  (let [form {:grant_type "client_credentials"
              :client_id (expand-env params.client_id)
              :client_secret (expand-env (or params.client_secret ""))}]
    (when params.scope (tset form :scope params.scope))
    (when params.audience (tset form :audience params.audience))
    (store-token (post-form params.token_url form ssl) profile-name)))

;; ---- authorization code (browser) ----

(fn open-browser [url]
  (let [h (io.popen "uname -s")
        sys (if h (let [s (h:read :*l)] (h:close) s) "Linux")
        quoted (shell-quote url)]
    (if (= sys "Darwin")
        (os.execute (.. "open " quoted))
        (os.execute (.. "xdg-open " quoted " 2>/dev/null &")))))

(fn start-local-server [?port]
  (let [srv (socket.tcp)
        (ok-b err-b) (srv:bind "127.0.0.1" (or ?port 0))]
    (assert ok-b (.. "OAuth callback bind failed: " (tostring err-b)))
    (let [(ok-l err-l) (srv:listen 1)]
      (assert ok-l (.. "OAuth callback listen failed: " (tostring err-l)))
      (let [(_ port) (srv:getsockname)]
        (values srv port)))))

(fn wait-for-callback [srv expected-state]
  (srv:settimeout 120)
  (let [(client err) (srv:accept)]
    (assert client (.. "OAuth callback timed out: " (tostring err)))
    (client:settimeout 10)
    (let [first (client:receive "*l")]
      (var line (client:receive "*l"))
      (while (and line (> (length line) 2))
        (set line (client:receive "*l")))
      (if (not first)
          (do (client:send "HTTP/1.1 400 Bad Request\r\nConnection: close\r\n\r\n")
              (client:close)
              (srv:close)
              (error "malformed OAuth callback request"))
          (let [(path) (first:match "GET (%S+) ")]
            (if (not path)
                (do (client:send "HTTP/1.1 400 Bad Request\r\nConnection: close\r\n\r\n")
                    (client:close)
                    (srv:close)
                    (error "malformed OAuth callback request"))
                (let [(code) (path:match "[?&]code=([^&]+)")
                      (state) (path:match "[?&]state=([^&]+)")]
                  (client:send (.. "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nConnection: close\r\n\r\n"
                                   "<html><body><h1>Authentication successful.</h1>"
                                   "<p>You can close this tab.</p></body></html>"))
                  (client:close)
                  (srv:close)
                  (assert code "no authorization code in callback")
                  (assert (= state expected-state) "OAuth state mismatch — possible CSRF")
                  code)))))))

(fn authorization-code [profile-name params ssl]
  (let [(srv port) (start-local-server params.redirect_port)
        redirect-host (or params.redirect_host "127.0.0.1")
        redirect-uri (.. "http://" redirect-host ":" port (or params.redirect_path "/callback"))
        state (random-string 16)
        code-verifier (random-string 64)
        code-challenge (sha256-base64url code-verifier)
        auth-params {:response_type "code"
                     :client_id (expand-env params.client_id)
                     :redirect_uri redirect-uri
                     :state state
                     :scope (or params.scope "")}]
    (when (and code-challenge (> (length code-challenge) 0))
      (tset auth-params :code_challenge code-challenge)
      (tset auth-params :code_challenge_method "S256"))
    (let [auth-url (qs-append params.authorize_url auth-params)]
      (io.stderr:write (.. "Opening browser for authentication...\n"))
      (io.stderr:write (.. "If browser does not open, visit:\n" auth-url "\n"))
      (open-browser auth-url)
      (let [code (wait-for-callback srv state)
            form {:grant_type "authorization_code"
                  :code code
                  :redirect_uri redirect-uri
                  :client_id (expand-env params.client_id)}]
        (when params.client_secret
          (tset form :client_secret (expand-env params.client_secret)))
        (when (and code-challenge (> (length code-challenge) 0))
          (tset form :code_verifier code-verifier))
        (store-token (post-form params.token_url form ssl) profile-name)))))

;; ---- external tool ----

(fn run-external [params stdin-json]
  (assert params.commandline "external-tool auth requires params.commandline")
  (var tmp-path nil)
  (let [cmd (if stdin-json
                (let [tmp (os.tmpname)
                      f (io.open tmp :w)]
                  (assert f "failed to write external tool input")
                  (f:write stdin-json)
                  (f:close)
                  (set tmp-path tmp)
                  (.. "/bin/sh -c "
                      (shell-quote (.. params.commandline " < " (shell-quote tmp)))))
                (.. "/bin/sh -c " (shell-quote params.commandline)))
        h (io.popen cmd)]
    (assert h "failed to start external auth command")
    (let [out (h:read "*a")]
      (h:close)
      (when tmp-path (os.remove tmp-path))
      out)))

(fn external-bearer [params]
  (let [out (: (run-external params nil) :match "^%s*(.-)%s*$")]
    (assert (and out (> (length out) 0)) "external auth command produced no output")
    {:authorization (.. "Bearer " out)}))

(fn external-signing-headers [params req]
  (let [body (when (not params.omitbody) (or req.body ""))
        payload (json.encode {:method (or req.method "GET")
                              :uri req.url
                              :headers (or req.headers {})
                              :body body})
        raw (run-external params payload)]
    (when (and raw (> (length raw) 0))
      (let [(ok result) (pcall json.decode raw)]
        (when (and ok result result.headers)
          result.headers)))))

;; ---- public API ----

(fn authenticate [profile-name auth-config ssl]
  (let [params auth-config.params]
    (match auth-config.name
      "oauth-authorization-code" (authorization-code profile-name params ssl)
      "oauth-client-credentials" (client-credentials profile-name params ssl)
      _ (error (.. "unsupported auth type: " auth-config.name)))))

(fn ensure-token [profile-name auth-config ssl]
  (let [cached (load-token profile-name)]
    (if (token-valid? cached)
        cached.access_token
        (let [data (if (and cached cached.refresh_token)
                       (do (io.stderr:write "Refreshing token...\n")
                           (or (try-refresh profile-name auth-config.params ssl cached)
                               (do (io.stderr:write "Token refresh failed, re-authenticating...\n")
                                   (authenticate profile-name auth-config ssl))))
                       (authenticate profile-name auth-config ssl))]
          data.access_token))))

(fn get-headers [profile-name auth-config ssl]
  "Returns static headers for any auth type.
  For external-tool with output=bearer-token: runs command once, returns Authorization header.
  For external-tool signing mode: returns {} — per-request headers come via wrap-http-fn.
  OAuth types: returns {:authorization 'Bearer <token>'}."
  (match auth-config.name
    "external-tool" (if (= (?. auth-config :params :output) "bearer-token")
                        (external-bearer auth-config.params)
                        {})
    _ {:authorization (.. "Bearer " (ensure-token profile-name auth-config ssl))}))

(fn wrap-http-fn [auth-config base-fn]
  "Returns a per-request signing wrapper, or nil if not needed."
  (when (and (= auth-config.name "external-tool")
             (not= (?. auth-config :params :output) "bearer-token"))
    (let [params auth-config.params]
      (fn [req]
        (let [extra (external-signing-headers params req)]
          (when extra
            (let [headers (or req.headers {})]
              (each [k vs (pairs extra)]
                (tset headers k (if (= (type vs) :table) (. vs 1) vs)))
              (tset req :headers headers)))
          (base-fn req))))))

{: get-headers : wrap-http-fn : authenticate : clear-token}
