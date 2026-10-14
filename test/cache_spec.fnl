;; ABOUTME: Specs for the on-disk schema cache: round trips, expiry and
;; ABOUTME: damaged entries. Run with `make test` (uses a scratch cache dir).
(local cache (require :atlas.cache))

(fn unique-url []
  (.. "https://cache.test/" (os.time) "-" (math.random 1 1000000000) ".json"))

(describe "schema cache"
          (fn []
            (it "returns a stored schema while it is fresh"
                (fn []
                  (let [url (unique-url)]
                    (cache.put url {:openapi "3.0.0" :paths {}})
                    (assert.are.same {:openapi "3.0.0" :paths {}}
                                     (cache.get url 60)))))
            (it "keeps cached schemas private to the user"
                (fn []
                  (let [url (unique-url)]
                    (cache.put url {:a 1})
                    (let [dir (: (cache.path url) :match "^(.*)/")
                          p (io.popen (.. "ls -ld '" dir "'"))
                          mode (p:read :*l)]
                      (p:close)
                      (assert.are.equal "drwx------" (mode:sub 1 10))))))
            (it "returns nothing for unknown URLs"
                (fn []
                  (assert.is_nil (cache.get (unique-url) 60))))
            (it "treats entries older than the TTL as missing"
                (fn []
                  (let [url (unique-url)]
                    (cache.put url {:a 1})
                    (assert.is_nil (cache.get url 0)))))
            (it "ignores damaged entries"
                (fn []
                  (let [url (unique-url)]
                    (cache.put url {:a 1})
                    (let [f (io.open (cache.path url) :w)]
                      (f:write "{not json")
                      (f:close))
                    (assert.is_nil (cache.get url 60)))))))
