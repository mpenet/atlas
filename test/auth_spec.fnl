;; ABOUTME: Specs for OAuth flows, token storage, callback listener and external-tool auth.
;; ABOUTME: Run with `make test` (busted, Fennel loader).
(local json (require :lunajson))

;; ---- helpers ----

(fn json-body [t] (json.encode t))

(fn ok-resp [body]
  {:status 200 :headers {} :body body})

(fn err-resp [body ?status]
  {:status (or ?status 400) :headers {} :body body})

(local real-http (require :atlas.http))

(fn seq-mock [& resps]
  "Returns an atlas.http-compatible module whose request fn yields resps in order."
  (var idx 0)
  (var calls [])
  (values {:encode-body real-http.encode-body
           :request (fn [req]
                      (table.insert calls req)
                      (set idx (+ idx 1))
                      (or (. resps idx) (ok-resp {})))} calls))

(fn mock-socket [?sleep-fn]
  {:sleep (or ?sleep-fn (fn [] nil)) :gettime (fn [] (os.time))})

(local real-socket (require :socket))

(fn reload-auth [http-mod ?sock-mod]
  (tset package.loaded :atlas.auth nil)
  (tset package.loaded :atlas.http http-mod)
  (tset package.loaded :socket (or ?sock-mod real-socket))
  (require :atlas.auth))

(fn tmp-profile []
  (.. "test-auth-" (tostring (math.random 100000 999999))))

(fn clean-token [profile-name]
  (os.remove ((. (require :atlas.auth) :token-path) profile-name)))

;; ---- client credentials ----

(describe "oauth-client-credentials"
          (fn []
            (it "sends correct grant_type, client_id and client_secret"
                (fn []
                  (let [(http calls) (seq-mock (ok-resp (json-body {:access_token "tok"
                                                                    :expires_in 3600})))
                        auth (reload-auth http)
                        profile (tmp-profile)]
                    (auth.authenticate profile
                                       {:name "oauth-client-credentials"
                                        :params {:token_url "https://auth.example.com/token"
                                                 :client_id "my-client"
                                                 :client_secret "my-secret"}}
                                       {})
                    (clean-token profile)
                    (assert.are.equal 1 (length calls))
                    (let [req (. calls 1)
                          body req.raw-body]
                      (assert.is_truthy (body:find "grant_type=client_credentials"
                                                   1 true))
                      (assert.is_truthy (body:find "client_id=my-client" 1 true))
                      (assert.is_truthy (body:find "client_secret=my-secret" 1
                                                   true))))))
            (it "includes scope when provided"
                (fn []
                  (let [(http calls) (seq-mock (ok-resp (json-body {:access_token "tok"
                                                                    :expires_in 3600})))
                        auth (reload-auth http)
                        profile (tmp-profile)]
                    (auth.authenticate profile
                                       {:name "oauth-client-credentials"
                                        :params {:token_url "https://auth.example.com/token"
                                                 :client_id "c"
                                                 :client_secret "s"
                                                 :scope "read write"}}
                                       {})
                    (clean-token profile)
                    (let [body (?. calls 1 :raw-body)]
                      (assert.is_truthy (body:find "scope=read" 1 true))))))
            (it "expands env: prefix in client_secret"
                (fn []
                  (os.execute "export _ATLAS_TEST_SECRET=env-secret 2>/dev/null; true")
                  ;; setenv workaround via a known-set var
                  (let [(http calls) (seq-mock (ok-resp (json-body {:access_token "tok"
                                                                    :expires_in 3600})))
                        auth (reload-auth http)
                        profile (tmp-profile)
                        _ (os.execute "export _ATLAS_TEST_SECRET=env-secret")]
                    ;; only test that env: expansion is attempted and errors clearly when var missing
                    (assert.has.error (fn []
                                        (auth.authenticate profile
                                                           {:name "oauth-client-credentials"
                                                            :params {:token_url "https://auth.example.com/token"
                                                                     :client_id "c"
                                                                     :client_secret "env:_ATLAS_DEFINITELY_NOT_SET_XYZ"}}
                                                           {})))
                    (clean-token profile))))
            (it "errors on non-2xx token response"
                (fn []
                  (let [(http) (seq-mock (err-resp (json-body {:error "invalid_client"})
                                                   401))
                        auth (reload-auth http)
                        profile (tmp-profile)]
                    (assert.has.error (fn []
                                        (auth.authenticate profile
                                                           {:name "oauth-client-credentials"
                                                            :params {:token_url "https://auth.example.com/token"
                                                                     :client_id "c"
                                                                     :client_secret "s"}}
                                                           {}))))))))

;; ---- device authorization ----

(describe "oauth-device-authorization"
          (fn []
            (it "displays user_code and polls until success"
                (fn []
                  (let [sleep-calls []
                        sock (mock-socket (fn [n] (table.insert sleep-calls n)))
                        (http calls) (seq-mock (ok-resp (json-body {:device_code "dcode"
                                                                    :user_code "ABCD-1234"
                                                                    :verification_uri "https://example.com/activate"
                                                                    :expires_in 300
                                                                    :interval 5}))
                                               (err-resp (json-body {:error "authorization_pending"})
                                                         400)
                                               (ok-resp (json-body {:access_token "device-tok"
                                                                    :expires_in 3600})))
                        auth (reload-auth http sock)
                        profile (tmp-profile)
                        stderr-buf []
                        orig-stderr io.stderr]
                    (set io.stderr
                         {:write (fn [_ s] (table.insert stderr-buf s))})
                    (auth.authenticate profile
                                       {:name "oauth-device-authorization"
                                        :params {:device_authorization_url "https://auth.example.com/device"
                                                 :token_url "https://auth.example.com/token"
                                                 :client_id "my-client"}}
                                       {})
                    (set io.stderr orig-stderr)
                    (clean-token profile)
                    (assert.are.equal 3 (length calls))
                    ;; sleep happens before each poll, so 2 polls = 2 sleeps
                    (assert.are.equal 2 (length sleep-calls))
                    (assert.are.equal 5 (. sleep-calls 1))
                    (let [stderr (table.concat stderr-buf)]
                      (assert.is_truthy (stderr:find "ABCD-1234" 1 true))))))
            (it "applies slow_down backoff"
                (fn []
                  (let [sleep-calls []
                        sock (mock-socket (fn [n] (table.insert sleep-calls n)))
                        (http) (seq-mock (ok-resp (json-body {:device_code "dc"
                                                              :user_code "X"
                                                              :verification_uri "https://x.com"
                                                              :expires_in 300
                                                              :interval 5}))
                                         (err-resp (json-body {:error "slow_down"})
                                                   400)
                                         (ok-resp (json-body {:access_token "tok"
                                                              :expires_in 3600})))
                        auth (reload-auth http sock)
                        profile (tmp-profile)
                        orig-stderr io.stderr]
                    (set io.stderr {:write (fn [_ _] nil)})
                    (auth.authenticate profile
                                       {:name "oauth-device-authorization"
                                        :params {:device_authorization_url "https://a.com/d"
                                                 :token_url "https://a.com/t"
                                                 :client_id "c"}}
                                       {})
                    (set io.stderr orig-stderr)
                    (clean-token profile)
                    (assert.are.equal 2 (length sleep-calls))
                    (assert.are.equal 5 (. sleep-calls 1))
                    (assert.are.equal 10 (. sleep-calls 2)))))
            (it "errors on expired_token"
                (fn []
                  (let [sock (mock-socket)
                        (http) (seq-mock (ok-resp (json-body {:device_code "dc"
                                                              :user_code "X"
                                                              :verification_uri "https://x.com"
                                                              :expires_in 300
                                                              :interval 5}))
                                         (err-resp (json-body {:error "expired_token"})
                                                   400))
                        auth (reload-auth http sock)
                        profile (tmp-profile)
                        orig-stderr io.stderr]
                    (set io.stderr {:write (fn [_ _] nil)})
                    (assert.has.error (fn []
                                        (auth.authenticate profile
                                                           {:name "oauth-device-authorization"
                                                            :params {:device_authorization_url "https://a.com/d"
                                                                     :token_url "https://a.com/t"
                                                                     :client_id "c"}}
                                                           {}))
                                      "device code expired")
                    (set io.stderr orig-stderr)
                    (clean-token profile))))
            (it "errors on access_denied"
                (fn []
                  (let [sock (mock-socket)
                        (http) (seq-mock (ok-resp (json-body {:device_code "dc"
                                                              :user_code "X"
                                                              :verification_uri "https://x.com"
                                                              :expires_in 300
                                                              :interval 5}))
                                         (err-resp (json-body {:error "access_denied"})
                                                   400))
                        auth (reload-auth http sock)
                        profile (tmp-profile)
                        orig-stderr io.stderr]
                    (set io.stderr {:write (fn [_ _] nil)})
                    (assert.has.error (fn []
                                        (auth.authenticate profile
                                                           {:name "oauth-device-authorization"
                                                            :params {:device_authorization_url "https://a.com/d"
                                                                     :token_url "https://a.com/t"
                                                                     :client_id "c"}}
                                                           {}))
                                      "device authorization denied by user")
                    (set io.stderr orig-stderr)
                    (clean-token profile))))
            (it "errors when device_authorization_url is missing"
                (fn []
                  (let [(http) (seq-mock)
                        auth (reload-auth http (mock-socket))
                        profile (tmp-profile)]
                    (assert.has.error (fn []
                                        (auth.authenticate profile
                                                           {:name "oauth-device-authorization"
                                                            :params {:token_url "https://a.com/t"
                                                                     :client_id "c"}}
                                                           {}))))))))

;; ---- external tool ----

(describe "external-tool auth"
          (fn []
            (it "bearer-token mode: injects Authorization header from command output"
                (fn []
                  (let [(http) (seq-mock)
                        auth (reload-auth http)
                        headers (auth.get-headers "test-profile"
                                                  {:name "external-tool"
                                                   :params {:commandline "echo 'my-token'"
                                                            :output "bearer-token"}}
                                                  {})]
                    (assert.are.equal "Bearer my-token" headers.authorization))))
            (it "bearer-token mode: trims whitespace from command output"
                (fn []
                  (let [(http) (seq-mock)
                        auth (reload-auth http)
                        headers (auth.get-headers "test-profile"
                                                  {:name "external-tool"
                                                   :params {:commandline "printf '  spaced-token  '"
                                                            :output "bearer-token"}}
                                                  {})]
                    (assert.are.equal "Bearer spaced-token"
                                      headers.authorization))))
            (it "bearer-token mode: errors when command produces no output"
                (fn []
                  (let [(http) (seq-mock)
                        auth (reload-auth http)]
                    (assert.has.error (fn []
                                        (auth.get-headers "test-profile"
                                                          {:name "external-tool"
                                                           :params {:commandline "true"
                                                                    :output "bearer-token"}}
                                                          {}))))))
            (it "signing mode: get-headers returns empty table"
                (fn []
                  (let [(http) (seq-mock)
                        auth (reload-auth http)
                        headers (auth.get-headers "test-profile"
                                                  {:name "external-tool"
                                                   :params {:commandline "echo '{}'"}}
                                                  {})]
                    (assert.are.same {} headers))))
            (it "signing mode: wrap-http-fn injects headers from tool output"
                (fn []
                  (let [(http calls) (seq-mock (ok-resp {}))
                        auth (reload-auth http)
                        base-fn (?. http :request)
                        wrapped (auth.wrap-http-fn {:name "external-tool"
                                                    :params {:commandline "echo '{\"headers\":{\"x-sig\":[\"abc\"]}}'"}}
                                                   base-fn)]
                    (assert.is_function wrapped)
                    (wrapped {:method "GET"
                              :url "https://api.example.com/items"
                              :headers {}})
                    (assert.are.equal "abc" (?. calls 1 :headers :x-sig)))))
            (it "signing mode: wrap-http-fn returns nil for bearer-token output mode"
                (fn []
                  (let [(http) (seq-mock)
                        auth (reload-auth http)
                        wrapped (auth.wrap-http-fn {:name "external-tool"
                                                    :params {:commandline "echo tok"
                                                             :output "bearer-token"}}
                                                   (fn [] nil))]
                    (assert.is_nil wrapped))))))

;; ---- unsupported auth type ----

(describe "authenticate"
          (fn []
            (it "errors on unknown auth type"
                (fn []
                  (let [(http) (seq-mock)
                        auth (reload-auth http)]
                    (assert.has.error (fn []
                                        (auth.authenticate "p"
                                                           {:name "magic-auth"
                                                            :params {}}
                                                           {}))))))))

;; ---- request signing ----

(describe "external-tool signing"
          (fn []
            (it "signs and sends the full URL including the query string"
                (fn []
                  (let [(http calls) (seq-mock (ok-resp {}))
                        auth (reload-auth http)
                        input (os.tmpname)
                        wrapped (auth.wrap-http-fn {:name "external-tool"
                                                    :params {:commandline (.. "cat > "
                                                                              input
                                                                              "; echo '{}'")}}
                                                   http.request)]
                    (wrapped {:method "GET"
                              :url "https://api.example.com/items"
                              :query {:b "2" :a "x y"}
                              :headers {}})
                    (let [f (io.open input)
                          signed (json.decode (f:read :*a))]
                      (f:close)
                      (os.remove input)
                      (assert.are.equal "https://api.example.com/items?a=x%20y&b=2"
                                        signed.uri)
                      (assert.are.equal "https://api.example.com/items?a=x%20y&b=2"
                                        (. calls 1 :url))
                      (assert.is_nil (. calls 1 :query))))))))

;; ---- authorization code callback ----

(fn send-to [port lines]
  (let [socket (require :socket)
        c (assert (socket.connect "127.0.0.1" port))]
    (c:send (.. (table.concat lines "\r\n") "\r\n\r\n"))
    c))

(describe "oauth callback listener"
          (fn []
            (it "url-decodes the authorization code"
                (fn []
                  (let [auth (reload-auth (pick-values 1 (seq-mock)))
                        (srv port) (auth.start-local-server)
                        c (send-to port
                                   ["GET /callback?code=4%2F0Ab%2Bc&state=S1 HTTP/1.1"
                                    "Host: x"])]
                    (assert.are.equal "4/0Ab+c"
                                      (auth.wait-for-callback srv "S1"
                                                              "/callback"))
                    (c:close))))
            (it "ignores requests to other paths"
                (fn []
                  (let [auth (reload-auth (pick-values 1 (seq-mock)))
                        (srv port) (auth.start-local-server)
                        c1 (send-to port
                                    ["GET /favicon.ico HTTP/1.1" "Host: x"])
                        c2 (send-to port
                                    ["GET /callback?code=abc&state=S1 HTTP/1.1"
                                     "Host: x"])]
                    (assert.are.equal "abc"
                                      (auth.wait-for-callback srv "S1"
                                                              "/callback"))
                    (c1:close)
                    (c2:close))))
            (it "reports provider errors"
                (fn []
                  (let [auth (reload-auth (pick-values 1 (seq-mock)))
                        (srv port) (auth.start-local-server)
                        c (send-to port
                                   ["GET /callback?error=access_denied&error_description=nope&state=S1 HTTP/1.1"])
                        (ok err) (pcall auth.wait-for-callback srv "S1"
                                        "/callback")]
                    (c:close)
                    (assert.is_false ok)
                    (assert.is_truthy (: (tostring err) :find "access_denied")))))
            (it "rejects a state mismatch without reporting success to the browser"
                (fn []
                  (let [auth (reload-auth (pick-values 1 (seq-mock)))
                        (srv port) (auth.start-local-server)
                        c (send-to port
                                   ["GET /callback?code=abc&state=EVIL HTTP/1.1"])
                        (ok err) (pcall auth.wait-for-callback srv "S1"
                                        "/callback")
                        reply (c:receive "*a")]
                    (c:close)
                    (assert.is_false ok)
                    (assert.is_truthy (: (tostring err) :find "state mismatch"))
                    (assert.is_nil (reply:find "successful")))))))

;; ---- authorization code request ----

(describe "oauth-authorization-code"
          (fn []
            (it "sends an S256 PKCE challenge derived from the verifier"
                (fn []
                  (let [(http calls) (seq-mock (ok-resp (json-body {:access_token "t"})))
                        auth (reload-auth http)
                        profile (tmp-profile)
                        opened []]
                    (auth.authenticate profile
                                       {:name "oauth-authorization-code"
                                        :params {:authorize_url "https://a.example.com/authorize"
                                                 :token_url "https://a.example.com/token"
                                                 :client_id "cid"}}
                                       {}
                                       {:open-browser (fn [url]
                                                        (table.insert opened
                                                                      url)
                                                        (let [state (url:match "[?&]state=([^&]+)")
                                                              port (url:match "redirect_uri=http%%3A%%2F%%2F127%.0%.0%.1%%3A(%d+)")]
                                                          (: (send-to port
                                                                      [(.. "GET /callback?code=c1&state="
                                                                           state
                                                                           " HTTP/1.1")])
                                                             :close)))})
                    (clean-token profile)
                    (let [digest (require :atlas.digest)
                          challenge (: (. opened 1) :match
                                       "code_challenge=([^&]+)")
                          verifier (: (. calls 1 :raw-body) :match
                                      "code_verifier=([^&]+)")]
                      (assert.is_truthy (: (. opened 1) :find
                                           "code_challenge_method=S256" 1 true))
                      (assert.are.equal (digest.pkce-challenge verifier)
                                        challenge)
                      (assert.is_truthy (: (. calls 1 :raw-body) :find
                                           "code=c1" 1 true))))))))

;; ---- refresh ----

(describe "token refresh"
          (fn []
            (it "sends client_secret and keeps the old refresh token when none is returned"
                (fn []
                  (let [(http calls) (seq-mock (ok-resp (json-body {:access_token "new"
                                                                    :expires_in 60})))
                        auth (reload-auth http)
                        profile (tmp-profile)
                        cfg {:name "oauth-client-credentials"
                             :params {:token_url "https://a.example.com/token"
                                      :client_id "cid"
                                      :client_secret "sec"}}]
                    (auth.save-token profile
                                     {:access_token "old"
                                      :expires_at 1
                                      :refresh_token "r1"})
                    (assert.are.same {:authorization "Bearer new"}
                                     (auth.get-headers profile cfg {}))
                    (let [saved (auth.load-token profile)]
                      (clean-token profile)
                      (assert.is_truthy (: (. calls 1 :raw-body) :find
                                           "client_secret=sec" 1 true))
                      (assert.is_truthy (: (. calls 1 :raw-body) :find
                                           "grant_type=refresh_token" 1 true))
                      (assert.are.equal "r1" saved.refresh_token)))))))

;; ---- token storage ----

(describe "token storage"
          (fn []
            (it "keeps profile names inside the token directory"
                (fn []
                  (let [auth (reload-auth (pick-values 1 (seq-mock)))]
                    (assert.is_nil (: (auth.token-path "../../evil") :find
                                      "/../" 1 true)))))))

;; ---- static credentials ----

(describe "static auth types"
          (fn []
            (let [auth (reload-auth (pick-values 1 (seq-mock)))
                  home (os.getenv :HOME)]
              (it "bearer sends the token"
                  (fn []
                    (assert.are.same {:authorization "Bearer t0k"}
                                     (auth.get-headers "p"
                                                       {:name "bearer"
                                                        :params {:token "t0k"}}
                                                       {}))))
              (it "bearer reads env: values"
                  (fn []
                    (assert.are.same {:authorization (.. "Bearer " home)}
                                     (auth.get-headers "p"
                                                       {:name "bearer"
                                                        :params {:token "env:HOME"}}
                                                       {}))))
              (it "basic encodes username and password"
                  (fn []
                    (assert.are.same {:authorization "Basic QWxhZGRpbjpvcGVuIHNlc2FtZQ=="}
                                     (auth.get-headers "p"
                                                       {:name "basic"
                                                        :params {:username "Aladdin"
                                                                 :password "open sesame"}}
                                                       {}))))
              (it "api-key in a header"
                  (fn []
                    (assert.are.same {:x-api-key "k1"}
                                     (auth.get-headers "p"
                                                       {:name "api-key"
                                                        :params {:name "X-API-Key"
                                                                 :in "header"
                                                                 :value "k1"}}
                                                       {}))))
              (it "api-key in the query string is added to every request"
                  (fn []
                    (let [cfg {:name "api-key"
                               :params {:name "api_key"
                                        :in "query"
                                        :value "k1"}}
                          sent []
                          wrapped (auth.wrap-http-fn cfg
                                                     (fn [req]
                                                       (table.insert sent req)
                                                       {:status 200}))]
                      (assert.are.same {} (auth.get-headers "p" cfg {}))
                      (wrapped {:method "GET"
                                :url "https://x/y"
                                :query {:a "1"}})
                      (assert.are.same {:a "1" :api_key "k1"} (. sent 1 :query)))))
              (it "rejects missing parameters with a clear message"
                  (fn []
                    (let [(ok err) (pcall auth.get-headers "p"
                                          {:name "basic"
                                           :params {:username "u"}}
                                          {})]
                      (assert.is_false ok)
                      (assert.is_truthy (: (tostring err) :find
                                           "basic auth requires params.password"
                                           1 true)))))
              (it "rejects unknown auth types"
                  (fn []
                    (let [(ok err) (pcall auth.get-headers "p"
                                          {:name "magic" :params {}} {})]
                      (assert.is_false ok)
                      (assert.is_truthy (: (tostring err) :find
                                           "unsupported auth type: magic" 1 true))))))))

(describe "api-key query parameter"
          (fn []
            (it "is not added twice when the URL already carries it"
                (fn []
                  (let [auth (reload-auth (pick-values 1 (seq-mock)))
                        sent []
                        wrapped (auth.wrap-http-fn {:name "api-key"
                                                    :params {:name "api_key"
                                                             :in "query"
                                                             :value "K"}}
                                                   (fn [req]
                                                     (table.insert sent req)
                                                     {:status 200}))]
                    (wrapped {:method "GET"
                              :url "https://h/items?api_key=K&page=2"})
                    (assert.is_nil (?. sent 1 :query :api_key)))))))

(describe "auth.header-names"
          (fn []
            (let [auth (reload-auth (pick-values 1 (seq-mock)))]
              (it "names the header each auth type supplies, without authenticating"
                  (fn []
                    (assert.are.same ["authorization"]
                                     (auth.header-names {:name "bearer"}))
                    (assert.are.same ["authorization"]
                                     (auth.header-names {:name "oauth-client-credentials"}))
                    (assert.are.same ["authorization"]
                                     (auth.header-names {:name "external-tool"
                                                         :params {:output "bearer-token"}}))
                    (assert.are.same ["x-api-key"]
                                     (auth.header-names {:name "api-key"
                                                         :params {:name "X-API-Key"
                                                                  :in "header"}}))
                    (assert.are.same []
                                     (auth.header-names {:name "api-key"
                                                         :params {:name "k"
                                                                  :in "query"}}))
                    (assert.are.same []
                                     (auth.header-names {:name "external-tool"
                                                         :params {}})))))))
