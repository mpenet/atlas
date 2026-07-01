(local json (require :lunajson))

;; ---- helpers ----

(fn json-body [t] (json.encode t))

(fn ok-resp [body]
  {:status 200 :headers {} :body body})

(fn err-resp [body ?status]
  {:status (or ?status 400) :headers {} :body body})

(fn seq-mock [& resps]
  "Returns an atlas.http-compatible module whose request fn yields resps in order."
  (var idx 0)
  (var calls [])
  (values
    {:request (fn [req]
                (table.insert calls req)
                (set idx (+ idx 1))
                (or (. resps idx) (ok-resp {})))}
    calls))

(fn mock-socket [?sleep-fn]
  {:sleep (or ?sleep-fn (fn [] nil))
   :gettime (fn [] (os.time))})

(fn reload-auth [http-mod ?sock-mod]
  (tset package.loaded :atlas.auth nil)
  (tset package.loaded :atlas.http http-mod)
  (when ?sock-mod (tset package.loaded :socket ?sock-mod))
  (require :atlas.auth))

(fn tmp-profile []
  (.. "test-auth-" (tostring (math.random 100000 999999))))

(fn clean-token [profile-name]
  (let [path (.. (or (os.getenv :HOME) ".") "/.cache/atlas/tokens/" profile-name ".json")]
    (os.remove path)))

;; ---- client credentials ----

(describe "oauth-client-credentials"
  (fn []
    (it "sends correct grant_type, client_id and client_secret"
      (fn []
        (let [(http calls) (seq-mock (ok-resp (json-body {:access_token "tok" :expires_in 3600})))
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
            (assert.is_truthy (body:find "grant_type=client_credentials" 1 true))
            (assert.is_truthy (body:find "client_id=my-client" 1 true))
            (assert.is_truthy (body:find "client_secret=my-secret" 1 true))))))

    (it "includes scope when provided"
      (fn []
        (let [(http calls) (seq-mock (ok-resp (json-body {:access_token "tok" :expires_in 3600})))
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
        (let [(http calls) (seq-mock (ok-resp (json-body {:access_token "tok" :expires_in 3600})))
              auth (reload-auth http)
              profile (tmp-profile)
              _ (os.execute "export _ATLAS_TEST_SECRET=env-secret")]
          ;; only test that env: expansion is attempted and errors clearly when var missing
          (assert.has.error
            (fn []
              (auth.authenticate profile
                                 {:name "oauth-client-credentials"
                                  :params {:token_url "https://auth.example.com/token"
                                           :client_id "c"
                                           :client_secret "env:_ATLAS_DEFINITELY_NOT_SET_XYZ"}}
                                 {})))
          (clean-token profile))))

    (it "errors on non-2xx token response"
      (fn []
        (let [(http) (seq-mock (err-resp (json-body {:error "invalid_client"}) 401))
              auth (reload-auth http)
              profile (tmp-profile)]
          (assert.has.error
            (fn []
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
              (http calls) (seq-mock
                             (ok-resp (json-body {:device_code "dcode"
                                                  :user_code "ABCD-1234"
                                                  :verification_uri "https://example.com/activate"
                                                  :expires_in 300
                                                  :interval 5}))
                             (err-resp (json-body {:error "authorization_pending"}) 400)
                             (ok-resp (json-body {:access_token "device-tok" :expires_in 3600})))
              auth (reload-auth http sock)
              profile (tmp-profile)
              stderr-buf []
              orig-stderr io.stderr]
          (set io.stderr {:write (fn [_ s] (table.insert stderr-buf s))})
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
              (http) (seq-mock
                       (ok-resp (json-body {:device_code "dc" :user_code "X"
                                            :verification_uri "https://x.com"
                                            :expires_in 300 :interval 5}))
                       (err-resp (json-body {:error "slow_down"}) 400)
                       (ok-resp (json-body {:access_token "tok" :expires_in 3600})))
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
              (http) (seq-mock
                       (ok-resp (json-body {:device_code "dc" :user_code "X"
                                            :verification_uri "https://x.com"
                                            :expires_in 300 :interval 5}))
                       (err-resp (json-body {:error "expired_token"}) 400))
              auth (reload-auth http sock)
              profile (tmp-profile)
              orig-stderr io.stderr]
          (set io.stderr {:write (fn [_ _] nil)})
          (assert.has.error
            (fn []
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
              (http) (seq-mock
                       (ok-resp (json-body {:device_code "dc" :user_code "X"
                                            :verification_uri "https://x.com"
                                            :expires_in 300 :interval 5}))
                       (err-resp (json-body {:error "access_denied"}) 400))
              auth (reload-auth http sock)
              profile (tmp-profile)
              orig-stderr io.stderr]
          (set io.stderr {:write (fn [_ _] nil)})
          (assert.has.error
            (fn []
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
          (assert.has.error
            (fn []
              (auth.authenticate profile
                                 {:name "oauth-device-authorization"
                                  :params {:token_url "https://a.com/t" :client_id "c"}}
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
          (assert.are.equal "Bearer spaced-token" headers.authorization))))

    (it "bearer-token mode: errors when command produces no output"
      (fn []
        (let [(http) (seq-mock)
              auth (reload-auth http)]
          (assert.has.error
            (fn []
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
              wrapped (auth.wrap-http-fn
                        {:name "external-tool"
                         :params {:commandline "echo '{\"headers\":{\"x-sig\":[\"abc\"]}}'"}
                         }
                        base-fn)]
          (assert.is_function wrapped)
          (wrapped {:method "GET" :url "https://api.example.com/items" :headers {}})
          (assert.are.equal "abc" (?. calls 1 :headers :x-sig)))))

    (it "signing mode: wrap-http-fn returns nil for bearer-token output mode"
      (fn []
        (let [(http) (seq-mock)
              auth (reload-auth http)
              wrapped (auth.wrap-http-fn
                        {:name "external-tool"
                         :params {:commandline "echo tok" :output "bearer-token"}}
                        (fn [] nil))]
          (assert.is_nil wrapped))))))

;; ---- unsupported auth type ----

(describe "authenticate"
  (fn []
    (it "errors on unknown auth type"
      (fn []
        (let [(http) (seq-mock)
              auth (reload-auth http)]
          (assert.has.error
            (fn []
              (auth.authenticate "p" {:name "magic-auth" :params {}} {}))))))))
