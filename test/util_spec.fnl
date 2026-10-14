;; ABOUTME: Specs for shared helpers in atlas.util.
;; ABOUTME: Run with `make test` (busted, Fennel loader).
(local util (require :atlas.util))

(describe "camel->kebab"
          (fn []
            (it "simple camelCase"
                (fn []
                  (assert.are.equal "get-pet" (util.camel->kebab "getPet"))))
            (it "multi-word"
                (fn []
                  (assert.are.equal "get-pet-by-id"
                                    (util.camel->kebab "getPetById"))))
            (it "consecutive caps"
                (fn []
                  (assert.are.equal "get-api-key"
                                    (util.camel->kebab "getAPIKey"))))
            (it "leading uppercase run"
                (fn []
                  (assert.are.equal "http-request"
                                    (util.camel->kebab "HTTPRequest"))))
            (it "acronym before word"
                (fn []
                  (assert.are.equal "get-https-url"
                                    (util.camel->kebab "getHTTPSUrl"))))
            (it "all lowercase passthrough"
                (fn []
                  (assert.are.equal "listpets" (util.camel->kebab "listpets"))))))

(describe "extract-path-params"
          (fn []
            (it "extracts single param"
                (fn []
                  (assert.are.same ["petId"]
                                   (util.extract-path-params "/pet/{petId}"))))
            (it "extracts multiple params"
                (fn []
                  (assert.are.same ["userId" "postId"]
                                   (util.extract-path-params "/users/{userId}/posts/{postId}"))))
            (it "returns empty for no params"
                (fn [] (assert.are.same [] (util.extract-path-params "/pets"))))))

(describe "resolve-path"
          (fn []
            (it "substitutes a single param"
                (fn []
                  (let [result (util.resolve-path "/pet/{petId}" {:petId 42})]
                    (assert.are.equal "/pet/42" result))))
            (it "substitutes multiple params"
                (fn []
                  (let [result (util.resolve-path "/users/{userId}/posts/{postId}"
                                                  {:postId 99 :userId 1})]
                    (assert.are.equal "/users/1/posts/99" result))))
            (it "coerces numbers to strings"
                (fn []
                  (let [result (util.resolve-path "/items/{id}" {:id 7})]
                    (assert.are.equal "/items/7" result))))
            (it "errors on missing param"
                (fn []
                  (assert.has.error (fn []
                                      (util.resolve-path "/pet/{petId}" {})))
                  (assert.has.error (fn []
                                      (util.resolve-path "/a/{x}/b/{y}" {:x 1})))))
            (it "percent-encodes reserved characters in values"
                (fn []
                  (assert.are.equal "/items/a%2Fb%3Fc%20d"
                                    (util.resolve-path "/items/{id}"
                                                       {:id "a/b?c d"}))))))

(describe "url-encode"
          (fn []
            (it "keeps unreserved characters"
                (fn []
                  (assert.are.equal "aZ09-._~" (util.url-encode "aZ09-._~"))))
            (it "encodes everything else"
                (fn []
                  (assert.are.equal "%2F%3F%26%3D%20%25"
                                    (util.url-encode "/?&= %"))))))

(describe "url-decode"
          (fn []
            (it "decodes percent escapes and plus signs"
                (fn []
                  (assert.are.equal "4/0Ab c" (util.url-decode "4%2F0Ab+c"))))))

(describe "form-encode"
          (fn []
            (it "encodes pairs in sorted key order"
                (fn []
                  (assert.are.equal "a=1&b=x%20y"
                                    (util.form-encode {:b "x y" :a 1}))))
            (it "repeats key for array values"
                (fn []
                  (assert.are.equal "id=1&id=2" (util.form-encode {:id [1 2]}))))
            (it "returns empty string for empty table"
                (fn []
                  (assert.are.equal "" (util.form-encode {}))))))

(describe "resolve-reference"
          (fn []
            (it "keeps absolute URLs"
                (fn []
                  (assert.are.equal "https://x/y.json"
                                    (util.resolve-reference "dir/a.yaml"
                                                            "https://x/y.json"))))
            (it "keeps absolute paths"
                (fn []
                  (assert.are.equal "/etc/a.json"
                                    (util.resolve-reference "dir/a.yaml"
                                                            "/etc/a.json"))))
            (it "resolves relative to a file's directory"
                (fn []
                  (assert.are.equal "dir/specs/api.json"
                                    (util.resolve-reference "dir/a.yaml"
                                                            "./specs/api.json"))))
            (it "resolves relative to a file in the current directory"
                (fn []
                  (assert.are.equal "api.json"
                                    (util.resolve-reference "a.yaml" "api.json"))))
            (it "resolves relative to a URL"
                (fn []
                  (assert.are.equal "https://h/p/api.json"
                                    (util.resolve-reference "https://h/p/a.yaml"
                                                            "./api.json"))))
            (it "resolves parent segments"
                (fn []
                  (assert.are.equal "https://h/api.json"
                                    (util.resolve-reference "https://h/p/a.yaml"
                                                            "../api.json"))))))

(describe "append-query"
          (fn []
            (it "returns url unchanged without params"
                (fn []
                  (assert.are.equal "https://h/p"
                                    (util.append-query "https://h/p" {}))))
            (it "adds a query string"
                (fn []
                  (assert.are.equal "https://h/p?a=1"
                                    (util.append-query "https://h/p" {:a 1}))))
            (it "extends an existing query string"
                (fn []
                  (assert.are.equal "https://h/p?x=0&a=1"
                                    (util.append-query "https://h/p?x=0" {:a 1}))))))

(fn eval-with-env [env code]
  (let [h (io.popen (.. env " lua -e "
                        (string.format "%q"
                                       (.. "package.path='./lua/?.lua;'..package.path "
                                           code))))
        out (h:read "*a")]
    (h:close)
    (out:match "^%s*(.-)%s*$")))

(describe "atlas directories"
          (fn []
            (it "honors XDG_CACHE_HOME and XDG_CONFIG_HOME"
                (fn []
                  (assert.are.equal "/x/c/atlas"
                                    (eval-with-env "XDG_CACHE_HOME=/x/c"
                                                   "print(require('atlas.util')['cache-dir']())"))
                  (assert.are.equal "/x/k/atlas"
                                    (eval-with-env "XDG_CONFIG_HOME=/x/k"
                                                   "print(require('atlas.util')['config-dir']())"))))
            (it "defaults to ~/.cache and ~/.config"
                (fn []
                  (assert.are.equal "/h/.cache/atlas"
                                    (eval-with-env "env -u XDG_CACHE_HOME HOME=/h"
                                                   "print(require('atlas.util')['cache-dir']())"))
                  (assert.are.equal "/h/.config/atlas"
                                    (eval-with-env "env -u XDG_CONFIG_HOME HOME=/h"
                                                   "print(require('atlas.util')['config-dir']())"))))))

(describe "resolve-reference URL edge cases"
          (fn []
            (it "resolves root-relative refs against a URL origin"
                (fn []
                  (assert.are.equal "https://ex.com/openapi.yaml"
                                    (util.resolve-reference "https://ex.com/specs/a.yaml"
                                                            "/openapi.yaml"))))
            (it "adds the separator for a base URL without path"
                (fn []
                  (assert.are.equal "https://ex.com/openapi.yaml"
                                    (util.resolve-reference "https://ex.com"
                                                            "openapi.yaml"))))
            (it "does not climb above the URL root"
                (fn []
                  (assert.are.equal "https://ex.com/x.yaml"
                                    (util.resolve-reference "https://ex.com/a.yaml"
                                                            "../x.yaml"))))
            (it "ignores the query string of the base"
                (fn []
                  (assert.are.equal "https://ex.com/o.yaml"
                                    (util.resolve-reference "https://ex.com/a.yaml?x=1/2"
                                                            "o.yaml"))))))

(describe "secrets"
          (fn []
            (it "recognizes credential-like names"
                (fn []
                  (each [_ n (ipairs ["api_key"
                                      "X-API-Key"
                                      "access_token"
                                      "client_secret"
                                      "sig"
                                      "signature"
                                      "password"
                                      "cookie"])]
                    (assert.is_true (util.secret-name? n)))
                  (assert.is_false (util.secret-name? "page"))))
            (it "redacts secret query parameters in URLs"
                (fn []
                  (assert.are.equal "https://h/x?api_key=<redacted>&page=2"
                                    (util.redact-url "https://h/x?api_key=SECRET&page=2"))))))
