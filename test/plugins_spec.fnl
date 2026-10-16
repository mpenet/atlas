;; ABOUTME: Specs for plugins: loading Lua and Fennel files listed in the config,
;; ABOUTME: refusing files others can change, and resolving the auth they provide.
(local plugins (require :atlas.cli.plugins))

(fn plugin-file [extension text ?mode]
  "A plugin file with text, mode ?mode (default 600); returns its path."
  (let [path (.. (os.tmpname) extension)]
    (with-open [f (io.open path :w)]
      (f:write text))
    (os.execute (.. "chmod " (or ?mode "600") " " path))
    path))

(local lua-plugin
       "return {auth = {demo = function(req, params) return {headers = {authorization = 'Demo ' .. params.token .. ' ' .. req.method}} end}}")

(local fennel-plugin
       "{:auth {:fdemo (fn [req params] {:headers {:x-sig (.. params.token \":\" req.url)}})}}")

(describe "plugins"
          (fn []
            (it "gives a profile's auth the signing function a Lua plugin provides"
                (fn []
                  (let [path (plugin-file ".lua" lua-plugin)
                        auth (plugins.resolve-auth {:plugins [path]}
                                                   {:name "demo"
                                                    :params {:token "t1"}})]
                    (os.remove path)
                    (assert.are.equal "Demo t1 GET"
                                      (. (auth.sign {:method "GET"}
                                                    {:token "t1"})
                                         :headers :authorization))
                    (assert.are.equal path auth.plugin))))
            (it "loads plugins written in Fennel"
                (fn []
                  (let [path (plugin-file ".fnl" fennel-plugin)
                        auth (plugins.resolve-auth {:plugins [path]}
                                                   {:name "fdemo"})]
                    (os.remove path)
                    (assert.are.equal "k:https://x.test/"
                                      (. (auth.sign {:url "https://x.test/"}
                                                    {:token "k"})
                                         :headers :x-sig)))))
            (it "leaves built-in auth alone, without loading any plugin"
                (fn []
                  (let [cfg {:name "bearer" :params {:token "t"}}]
                    (assert.are.equal cfg
                                      (plugins.resolve-auth {:plugins ["/nonexistent/p.lua"]}
                                                            cfg)))))
            (it "says when no plugin provides an auth"
                (fn []
                  (let [path (plugin-file ".lua" lua-plugin)
                        (ok err) (pcall plugins.resolve-auth {:plugins [path]}
                                        {:name "nope"})]
                    (os.remove path)
                    (assert.is_false ok)
                    (assert.is_truthy (: (tostring err) :find
                                         "auth 'nope' is not built in, and no plugin provides it"
                                         1 true)))))
            (it "refuses a plugin that others can change"
                (fn []
                  (each [_ mode (ipairs ["620" "602"])]
                    (let [path (plugin-file ".lua" lua-plugin mode)
                          (ok err) (pcall plugins.resolve-auth
                                          {:plugins [path]} {:name "demo"})]
                      (os.remove path)
                      (assert.is_false ok)
                      (assert.is_truthy (: (tostring err) :find
                                           "can be changed by other users" 1
                                           true)
                                        (tostring err))))))
            (it "refuses plugins that don't provide auth functions"
                (fn []
                  (each [_ [extension text why] (ipairs [[".lua"
                                                          "return 42"
                                                          "must return a table"]
                                                         [".lua"
                                                          "return {auth = {demo = 'x'}}"
                                                          "auth demo must be a function"]
                                                         [".lua"
                                                          "error('boom')"
                                                          "boom"]
                                                         [".txt"
                                                          "{}"
                                                          "must be a .lua or .fnl file"]])]
                    (let [path (plugin-file extension text)
                          (ok err) (pcall plugins.resolve-auth
                                          {:plugins [path]} {:name "demo"})]
                      (os.remove path)
                      (assert.is_false ok)
                      (assert.is_truthy (: (tostring err) :find why 1 true)
                                        (tostring err))))))
            (it "signs Exoscale requests as Exoscale's client does, with the example plugin"
                (fn []
                  (let [digest (require :atlas.digest)
                        auth-mod (require :atlas.auth)
                        path (with-open [f (io.open "doc/examples/plugins/exoscale.fnl")]
                               (plugin-file ".fnl" (f:read :*a)))
                        resolved (plugins.resolve-auth {:plugins [path]}
                                                       {:name "exoscale"
                                                        :params {:key "EXOkey"
                                                                 :secret "s3cret"}})
                        sent []
                        wrapped (auth-mod.wrap-http-fn resolved
                                                       #(do
                                                          (table.insert sent $)
                                                          {:status 200
                                                           :headers {}}))]
                    (os.remove path)
                    (wrapped {:method "GET"
                              :url "https://api.test/v2/template?visibility=public&b=x&b=y"
                              :headers {}})
                    (let [header (. sent 1 :headers :authorization)
                          expires (header:match "expires=(%d+)")
                          message (.. "GET /v2/template\n\npublic\n\n" expires)]
                      (assert.are.equal (.. "EXO2-HMAC-SHA256 credential=EXOkey,signed-query-args=visibility,expires="
                                            expires ",signature="
                                            (digest.base64 (digest.hmac-sha256 "s3cret"
                                                                               message)))
                                        header)))))
            (it "refuses two plugins providing the same auth, and built-in names"
                (fn []
                  (let [a (plugin-file ".lua" lua-plugin)
                        b (plugin-file ".lua" lua-plugin)
                        builtin (plugin-file ".lua"
                                             "return {auth = {bearer = function() end}}")
                        (ok1 err1) (pcall plugins.resolve-auth {:plugins [a b]}
                                          {:name "demo"})
                        (ok2 err2) (pcall plugins.resolve-auth
                                          {:plugins [builtin]} {:name "demo"})]
                    (each [_ p (ipairs [a b builtin])]
                      (os.remove p))
                    (assert.is_false ok1)
                    (assert.is_truthy (: (tostring err1) :find
                                         "provided by two plugins" 1 true))
                    (assert.is_false ok2)
                    (assert.is_truthy (: (tostring err2) :find "built in" 1
                                         true)))))))
