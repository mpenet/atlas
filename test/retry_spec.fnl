;; ABOUTME: Specs for retrying idempotent requests on transient failures.
;; ABOUTME: Run with `make test` (busted, Fennel loader).
(local retry (require :atlas.retry))

(fn scripted [responses]
  "http-fn returning responses in order; a string entry raises that error."
  (let [calls []]
    (values (fn [req]
              (table.insert calls req)
              (let [r (. responses (length calls))]
                (if (= (type r) :string) (error r) r))) calls)))

(fn sleeper []
  (let [slept []]
    (values (fn [s] (table.insert slept s)) slept)))

(describe "retry.wrap"
          (fn []
            (it "retries retryable statuses until success"
                (fn []
                  (let [(http calls) (scripted [{:status 503 :headers {}}
                                                {:status 502 :headers {}}
                                                {:status 200 :headers {}}])
                        (sleep slept) (sleeper)
                        f (retry.wrap http {:attempts 2 :sleep sleep})]
                    (assert.are.equal 200 (. (f {:method "GET"}) :status))
                    (assert.are.equal 3 (length calls))
                    (assert.are.same [1 2] slept))))
            (it "returns the last response when attempts run out"
                (fn []
                  (let [(http calls) (scripted [{:status 503 :headers {}}
                                                {:status 503 :headers {}}])
                        f (retry.wrap http {:attempts 1 :sleep (sleeper)})]
                    (assert.are.equal 503 (. (f {:method "GET"}) :status))
                    (assert.are.equal 2 (length calls)))))
            (it "does not retry other statuses"
                (fn []
                  (let [(http calls) (scripted [{:status 404 :headers {}}])
                        f (retry.wrap http {:attempts 3 :sleep (sleeper)})]
                    (f {:method "GET"})
                    (assert.are.equal 1 (length calls)))))
            (it "retries transport errors and re-raises the last one"
                (fn []
                  (let [(http calls) (scripted ["connection refused" "timeout"])
                        f (retry.wrap http {:attempts 1 :sleep (sleeper)})
                        (ok err) (pcall f {:method "GET"})]
                    (assert.is_false ok)
                    (assert.is_truthy (: (tostring err) :find "timeout" 1 true))
                    (assert.are.equal 2 (length calls)))))
            (it "does not retry unsafe methods by default"
                (fn []
                  (let [(http calls) (scripted [{:status 503 :headers {}}])
                        f (retry.wrap http {:attempts 3 :sleep (sleeper)})]
                    (f {:method "POST"})
                    (assert.are.equal 1 (length calls)))))
            (it "retries unsafe methods when allowed"
                (fn []
                  (let [(http calls) (scripted [{:status 503 :headers {}}
                                                {:status 201 :headers {}}])
                        f (retry.wrap http
                                      {:attempts 1
                                       :unsafe true
                                       :sleep (sleeper)})]
                    (assert.are.equal 201 (. (f {:method "POST"}) :status)))))
            (it "honors Retry-After seconds, capped by max-wait"
                (fn []
                  (let [(http) (scripted [{:status 429
                                           :headers {:Retry-After "7"}}
                                          {:status 429
                                           :headers {:retry-after "900"}}
                                          {:status 200 :headers {}}])
                        (sleep slept) (sleeper)
                        f (retry.wrap http
                                      {:attempts 2 :max-wait 60 :sleep sleep})]
                    (f {:method "GET"})
                    (assert.are.same [7 60] slept))))
            (it "honors Retry-After HTTP dates"
                (fn []
                  (let [now (os.time)
                        date (os.date "!%a, %d %b %Y %H:%M:%S GMT" (+ now 30))
                        (http) (scripted [{:status 503
                                           :headers {:retry-after date}}
                                          {:status 200 :headers {}}])
                        (sleep slept) (sleeper)
                        f (retry.wrap http {:attempts 1 :sleep sleep :now #now})]
                    (f {:method "GET"})
                    (assert.are.same [30] slept))))
            (it "passes through untouched with zero attempts"
                (fn []
                  (let [(http calls) (scripted [{:status 503 :headers {}}])
                        f (retry.wrap http {:attempts 0 :sleep (sleeper)})]
                    (f {:method "GET"})
                    (assert.are.equal 1 (length calls)))))))
