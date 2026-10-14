;; ABOUTME: Profile authentication: OAuth 2.0 flows with a token cache, and
;; ABOUTME: external-tool bearer tokens or per-request signing.
(local json (require :atlas.json))
(local http (require :atlas.http))
(local util (require :atlas.util))
(local socket (require :socket))
(local digest (require :atlas.digest))

;; ---- helpers ----

(fn cache-dir []
  (.. (util.cache-dir) "/tokens"))

(fn token-path [profile-name]
  (.. (cache-dir) "/" (util.url-encode profile-name) ".json"))

(local shell-quote util.shell-quote)

(fn expand-env [s]
  (if (and (= (type s) :string) (s:match "^env:(.+)"))
      (let [(var-name) (s:match "^env:(.+)")]
        (or (os.getenv var-name)
            (error (.. "environment variable not set: " var-name))))
      s))

(fn random-string [n]
  "n characters from [A-Za-z0-9] read from /dev/urandom, without modulo bias."
  (let [chars "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
        nchars (length chars)
        limit (- 256 (% 256 nchars))
        f (assert (io.open "/dev/urandom" :rb)
                  "cannot read /dev/urandom for OAuth state")
        out []]
    (while (< (length out) n)
      (let [byte (string.byte (f:read 1))]
        (when (< byte limit)
          (let [i (+ 1 (% byte nchars))]
            (table.insert out (chars:sub i i))))))
    (f:close)
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
    (os.execute (.. "mkdir -p " (shell-quote dir) " && chmod 700 "
                    (shell-quote dir)))
    (let [f (io.open path :w)]
      (when f
        (f:write (json.encode data))
        (f:close)
        (os.execute (.. "chmod 600 " (shell-quote path)))))))

(fn clear-token [profile-name]
  (os.remove (token-path profile-name)))

(fn token-valid? [data]
  (and data data.access_token
       (or (not data.expires_at) (> data.expires_at (+ (os.time) 30)))))

;; ---- HTTP form post ----

(fn post-form [url params ssl]
  (let [body (util.form-encode params)]
    (http.request {:method :POST
                   :url url
                   :headers {:content-type "application/x-www-form-urlencoded"
                             :accept "application/json"}
                   :raw-body body
                   :ssl (or ssl {})})))

(fn json-body [resp]
  "Response body as a table, null fields left out (a null token or expiry
means none): decoded from the raw text when there is one."
  (let [text (if (= (type resp.raw) :string) resp.raw
                 (= (type resp.body) :string) resp.body)]
    (if text
        (let [(ok decoded) (pcall json.decode text)]
          (when (and ok (= (type decoded) :table))
            decoded))
        (when (= (type resp.body) :table)
          resp.body))))

(fn store-token [resp profile-name ?previous]
  (assert (util.success? resp.status)
          (let [body (json-body resp)
                detail (when body
                         (tostring (or body.error_description body.error "")))]
            (.. "token request failed: HTTP " resp.status
                (if (and detail (> (length detail) 0)) (.. " — " detail) ""))))
  (let [body (assert (json-body resp)
                     (.. "token response is not JSON: " (tostring resp.body)))
        data {:access_token body.access_token
              :token_type (or body.token_type "Bearer")}]
    (when body.expires_in
      (tset data :expires_at (+ (os.time) body.expires_in)))
    (match (or body.refresh_token (?. ?previous :refresh_token))
      refresh (tset data :refresh_token refresh))
    (save-token profile-name data)
    data))

;; ---- refresh ----

(fn try-refresh [profile-name params ssl cached]
  (let [form {:grant_type "refresh_token"
              :refresh_token cached.refresh_token
              :client_id (expand-env params.client_id)}]
    (when params.client_secret
      (tset form :client_secret (expand-env params.client_secret)))
    (let [(ok resp) (pcall post-form params.token_url form ssl)]
      (when (and ok (util.success? resp.status))
        (store-token resp profile-name cached)))))

;; ---- client credentials ----

(fn client-credentials [profile-name params ssl]
  (let [form {:grant_type "client_credentials"
              :client_id (expand-env params.client_id)
              :client_secret (expand-env (or params.client_secret ""))}]
    (when params.scope (tset form :scope params.scope))
    (when params.audience (tset form :audience params.audience))
    (store-token (post-form params.token_url form ssl) profile-name)))

;; ---- device authorization ----

(fn request-device-code [params ssl]
  "Start the device flow; returns the device authorization response body."
  (let [form {:client_id (expand-env params.client_id)}]
    (when params.scope (tset form :scope params.scope))
    (let [resp (post-form (or params.device_authorization_url
                              (error "oauth-device-authorization requires device_authorization_url"))
                          form ssl)]
      (assert (util.success? resp.status)
              (.. "device authorization request failed: HTTP " resp.status))
      (let [body (assert (json-body resp)
                         "device authorization response is not JSON")]
        (assert body.device_code
                "device authorization response missing device_code")
        (assert body.user_code
                "device authorization response missing user_code")
        body))))

(fn poll-device-token [profile-name params ssl device]
  "Poll the token endpoint until the user approves, honouring slow_down;
returns the stored token, raising on expiry, denial or timeout."
  (var deadline (+ (os.time) (or device.expires_in 300)))
  (var interval (or device.interval 5))
  (var token nil)
  (while (and (not token) (< (os.time) deadline))
    (socket.sleep interval)
    (let [(ok resp) (pcall post-form params.token_url
                           {:grant_type "urn:ietf:params:oauth:grant-type:device_code"
                            :device_code device.device_code
                            :client_id (expand-env params.client_id)}
                           ssl)
          body (when ok (json-body resp))]
      (if (and body (util.success? resp.status))
          (set token (store-token resp profile-name))
          (match (?. body :error)
            "slow_down" (set interval (+ interval 5))
            "expired_token" (error "device code expired")
            "access_denied" (error "device authorization denied by user")))))
  (or token (error "device authorization timed out")))

(fn device-authorization [profile-name params ssl]
  (let [device (request-device-code params ssl)]
    (io.stderr:write (.. "Open this URL to authenticate:\n  "
                         (or device.verification_uri_complete
                             device.verification_uri)
                         "\nUser code: " device.user_code
                         "\nWaiting for authorization...\n"))
    (poll-device-token profile-name params ssl device)))

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
    (let [(ok-l err-l) (srv:listen 8)]
      (assert ok-l (.. "OAuth callback listen failed: " (tostring err-l)))
      (let [(_ port) (srv:getsockname)]
        (values srv port)))))

(fn parse-query [qs]
  (collect [k v (qs:gmatch "([^&=]+)=?([^&]*)")]
    (util.url-decode k)
    (util.url-decode v)))

(fn reply [client status body]
  (client:send (.. "HTTP/1.1 " status
                   "\r\nContent-Type: text/html; charset=utf-8\r\n"
                   "Connection: close\r\n\r\n<html><body>" body "</body></html>"))
  (client:close))

(fn read-request-target [client]
  "Request target of an HTTP request, after draining its headers."
  (client:settimeout 10)
  (let [first (client:receive "*l")]
    (var line first)
    (while (and line (> (length line) 0))
      (set line (client:receive "*l")))
    (when first (first:match "^GET (%S+) "))))

(fn wait-for-callback [srv expected-state callback-path]
  "Accept connections until the OAuth redirect to callback-path arrives;
other requests (favicon, probes) get a 404. Returns the authorization code."
  (let [deadline (+ (socket.gettime) 120)]
    (var result nil)
    (while (= result nil)
      (srv:settimeout (math.max 0 (- deadline (socket.gettime))))
      (let [(client err) (srv:accept)]
        (when (not client)
          (srv:close)
          (error (.. "OAuth callback timed out: " (tostring err))))
        (let [target (read-request-target client)
              (path qs) (when target (target:match "^([^?]*)%??(.*)$"))]
          (if (not= path callback-path)
              (reply client "404 Not Found" "Not found.")
              (let [params (parse-query qs)]
                (set result
                     (if params.error
                         {:failure (.. "authorization failed: " params.error
                                       (if params.error_description
                                           (.. " — " params.error_description)
                                           ""))}
                         (not= params.state expected-state)
                         {:failure "OAuth state mismatch — possible CSRF"}
                         (not params.code)
                         {:failure "no authorization code in callback"}
                         {:code params.code}))
                (if result.code
                    (reply client "200 OK"
                           "<h1>Authentication successful.</h1><p>You can close this tab.</p>")
                    (reply client "400 Bad Request"
                           "<h1>Authentication failed.</h1>")))))))
    (srv:close)
    (when result.failure (error result.failure))
    result.code))

(fn authorization-code [profile-name params ssl ?opts]
  (let [(srv port) (start-local-server params.redirect_port)
        redirect-host (or params.redirect_host "127.0.0.1")
        redirect-path (or params.redirect_path "/callback")
        redirect-uri (.. "http://" redirect-host ":" port redirect-path)
        state (random-string 32)
        code-verifier (random-string 64)
        auth-params {:response_type "code"
                     :client_id (expand-env params.client_id)
                     :redirect_uri redirect-uri
                     :state state
                     :scope (or params.scope "")
                     :code_challenge (digest.pkce-challenge code-verifier)
                     :code_challenge_method "S256"}]
    (let [auth-url (util.append-query params.authorize_url auth-params)]
      (io.stderr:write (.. "Opening browser for authentication...\n"))
      (io.stderr:write (.. "If browser does not open, visit:\n" auth-url "\n"))
      ((or (?. ?opts :open-browser) open-browser) auth-url)
      (let [code (wait-for-callback srv state redirect-path)
            form {:grant_type "authorization_code"
                  :code code
                  :redirect_uri redirect-uri
                  :client_id (expand-env params.client_id)}]
        (when params.client_secret
          (tset form :client_secret (expand-env params.client_secret)))
        (tset form :code_verifier code-verifier)
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
                      (shell-quote (.. "( " params.commandline " ) < "
                                       (shell-quote tmp)))))
                (.. "/bin/sh -c " (shell-quote params.commandline)))
        h (io.popen cmd)]
    (assert h "failed to start external auth command")
    (let [out (h:read "*a")]
      (h:close)
      (when tmp-path (os.remove tmp-path))
      out)))

(fn external-bearer [params]
  (let [out (: (run-external params nil) :match "^%s*(.-)%s*$")]
    (assert (and out (> (length out) 0))
            "external auth command produced no output")
    {:authorization (.. "Bearer " out)}))

(fn external-signing-headers [params req]
  (let [body (when (not params.omitbody)
               (or req.raw-body (when (= (type req.body) :string) req.body)
                   (when req.body
                     (let [(ok s) (pcall json.encode req.body)]
                       (when ok s))) ""))
        payload (json.encode {:method (or req.method "GET")
                              :uri req.url
                              :headers (or req.headers {})
                              :body (or body "")})
        raw (run-external params payload)]
    (when (and raw (> (length raw) 0))
      (let [(ok result) (pcall json.decode raw)]
        (when (and ok result result.headers)
          result.headers)))))

;; ---- public API ----

(fn authenticate [profile-name auth-config ssl ?opts]
  "Run the configured OAuth flow and cache the token.
?opts: {:open-browser (fn [url])} to replace the system browser launcher."
  (let [params auth-config.params]
    (match auth-config.name
      "oauth-authorization-code" (authorization-code profile-name params ssl
                                                     ?opts)
      "oauth-client-credentials" (client-credentials profile-name params ssl)
      "oauth-device-authorization" (device-authorization profile-name params
                                                         ssl)
      _ (error (.. "unsupported auth type: " auth-config.name)))))

(fn ensure-token [profile-name auth-config ssl]
  (let [cached (load-token profile-name)]
    (if (token-valid? cached)
        cached.access_token
        (let [data (if (and cached cached.refresh_token)
                       (do
                         (io.stderr:write "Refreshing token...\n")
                         (or (try-refresh profile-name auth-config.params ssl
                                          cached)
                             (do
                               (io.stderr:write "Token refresh failed, re-authenticating...\n")
                               (authenticate profile-name auth-config ssl))))
                       (authenticate profile-name auth-config ssl))]
          data.access_token))))

(fn required-param [auth-config key]
  (let [v (?. auth-config :params key)]
    (assert (and v (not= v ""))
            (string.format "%s auth requires params.%s" auth-config.name key))
    (expand-env v)))

(fn api-key-in-query? [auth-config]
  (and (= auth-config.name "api-key") (= (?. auth-config :params :in) "query")))

(fn get-headers [profile-name auth-config ssl]
  "Returns static headers for any auth type.
  bearer / basic / api-key (header): headers built from params.
  api-key in the query string: returns {} — the parameter is added via wrap-http-fn.
  For external-tool with output=bearer-token: runs command once, returns Authorization header.
  For external-tool signing mode: returns {} — per-request headers come via wrap-http-fn.
  OAuth types: returns {:authorization 'Bearer <token>'}."
  (match auth-config.name
    "bearer" {:authorization (.. "Bearer " (required-param auth-config :token))}
    "basic" {:authorization (.. "Basic "
                                (digest.base64 (.. (required-param auth-config
                                                                   :username)
                                                   ":"
                                                   (required-param auth-config
                                                                   :password))))}
    "api-key" (if (api-key-in-query? auth-config)
                  {}
                  {(: (required-param auth-config :name) :lower) (required-param auth-config
                                                                                 :value)})
    "external-tool" (if (= (?. auth-config :params :output) "bearer-token")
                        (external-bearer auth-config.params)
                        {})
    _ {:authorization (.. "Bearer " (ensure-token profile-name auth-config ssl))}))

(fn header-names [auth-config]
  "Lowercased names of the headers get-headers will supply, without running
any auth flow; signing tools and query api-keys supply none up front."
  (match auth-config.name
    "api-key" (if (api-key-in-query? auth-config) []
                  [(: (or (?. auth-config :params :name) "") :lower)])
    "external-tool" (if (= (?. auth-config :params :output) "bearer-token")
                        ["authorization"]
                        [])
    _ ["authorization"]))

(fn wrap-api-key-query [auth-config base-fn]
  (let [name (required-param auth-config :name)
        value (required-param auth-config :value)]
    (fn [req]
      ;; next-page URLs from pagination may already carry the key
      (let [in-url? (let [url (or req.url "")
                          param (.. (util.url-encode name) "=")]
                      (or (not= nil (url:find (.. "?" param) 1 true))
                          (not= nil (url:find (.. "&" param) 1 true))))
            out (collect [k v (pairs req)] k v)]
        (when (not in-url?)
          (set out.query (doto (collect [k v (pairs (or req.query {}))]
                                 k
                                 v)
                           (tset name value))))
        ;; logs and dry runs must mask it whatever its name
        (set out.sensitive-query
             (doto (icollect [_ n (ipairs (or req.sensitive-query []))]
                     n)
               (table.insert name)))
        (base-fn out)))))

(fn wrap-signing [auth-config base-fn]
  (when (and (= auth-config.name "external-tool")
             (not= (?. auth-config :params :output) "bearer-token"))
    (let [params auth-config.params]
      (fn [caller-req]
        ;; signing rewrites url, body and headers: work on a copy
        (local req (collect [k v (pairs caller-req)] k v))
        (tset req :headers (collect [k v (pairs (or req.headers {}))]
                             k
                             v))
        ;; sign the URL that goes on the wire, query string included
        (when req.query
          (tset req :url (util.append-query req.url req.query))
          (tset req :query nil))
        ;; pre-encode body so signing and wire use identical bytes
        (when (and req.body (not req.raw-body))
          (let [(_ payload headers) (http.encode-request req)]
            (tset req :raw-body payload)
            (tset req :headers headers)
            (tset req :body nil)))
        (let [extra (external-signing-headers params req)]
          (when extra
            (each [k vs (pairs extra)]
              (tset req.headers k (if (= (type vs) :table) (. vs 1) vs))))
          (base-fn req))))))

(fn wrap-http-fn [auth-config base-fn]
  "Returns a per-request wrapper (query api-key or signing), or nil if not needed."
  (if (api-key-in-query? auth-config)
      (wrap-api-key-query auth-config base-fn)
      (wrap-signing auth-config base-fn)))

{: get-headers
 : header-names
 : wrap-http-fn
 : authenticate
 : clear-token
 : save-token
 : load-token
 : token-path
 : start-local-server
 : wait-for-callback}
