;; ABOUTME: Specs for following Link rel="next" pagination and merging pages.
;; ABOUTME: Run with `make test` (busted, Fennel loader).
(local paginate (require :atlas.paginate))

(fn site [pages]
  "http-fn serving pages keyed by full URL; records requested URLs."
  (let [seen []]
    (values (fn [req]
              (let [util (require :atlas.util)
                    url (util.append-query req.url (or req.query {}))]
                (table.insert seen url)
                (or (. pages url) {:status 404 :headers {} :body nil})))
            seen)))

(fn page [body ?next]
  "A 200 response shaped like the real transport's, with :raw JSON text."
  (let [json (require :atlas.json)]
    {:status 200
     :headers (if ?next {:link (.. "<" ?next ">; rel=\"next\"")} {})
     :body body
     :raw (json.encode body)}))

(describe "paginate.wrap"
          (fn []
            (it "follows next links and concatenates array pages"
                (fn []
                  (let [(http seen) (site {"https://h/items?limit=2" (page [1
                                                                            2]
                                                                           "https://h/items?page=2")
                                           "https://h/items?page=2" (page [3 4]
                                                                          "/items?page=3")
                                           "https://h/items?page=3" (page [5])})
                        f (paginate.wrap http {})
                        resp (f {:method "GET"
                                 :url "https://h/items"
                                 :query {:limit 2}
                                 :headers {:x-auth "a"}})]
                    (assert.are.same [1 2 3 4 5] resp.body)
                    (assert.are.equal 3 resp.pages)
                    (assert.are.same ["https://h/items?limit=2"
                                      "https://h/items?page=2"
                                      "https://h/items?page=3"]
                                     seen))))
            (it "sends the original headers with every page"
                (fn []
                  (let [headers []
                        http (fn [req]
                               (table.insert headers req.headers)
                               (if (= req.url "https://h/a")
                                   (page [1] "https://h/b")
                                   (page [2])))
                        f (paginate.wrap http {})]
                    (f {:method "GET"
                        :url "https://h/a"
                        :headers {:authorization "Bearer t"}})
                    (assert.are.same {:authorization "Bearer t"} (. headers 2)))))
            (it "parses Link headers with several relations"
                (fn []
                  (let [(http) (site {"https://h/a" {:status 200
                                                     :body [1]
                                                     :raw "[1]"
                                                     :headers {:Link "<https://h/a?p=9>; rel=\"last\", <https://h/a?p=2>; rel=\"next\""}}
                                      "https://h/a?p=2" (page [2])})
                        f (paginate.wrap http {})]
                    (assert.are.same [1 2]
                                     (. (f {:method "GET"
                                            :url "https://h/a"
                                            :headers {}})
                                        :body)))))
            (it "does not follow links to another origin"
                (fn []
                  (let [(http seen) (site {"https://h/a" (page [1]
                                                               "https://evil.example/a?p=2")})
                        f (paginate.wrap http {})]
                    (assert.are.same [1]
                                     (. (f {:method "GET"
                                            :url "https://h/a"
                                            :headers {}})
                                        :body))
                    (assert.are.equal 1 (length seen)))))
            (it "does not follow links that only look same-origin"
                (fn []
                  (each [_ link (ipairs ["https://evil.example?@h/a?p=2"
                                         "https://evil.example#@h/a"
                                         "https://h\\@evil.example/a"])]
                    (let [(http seen) (site {"https://h/a" (page [1] link)})
                          f (paginate.wrap http {})]
                      (f {:method "GET" :url "https://h/a" :headers {}})
                      (assert.are.equal 1 (length seen))))))
            (it "requests next pages like the first, sensitive headers marked"
                (fn []
                  (let [seen []
                        json (require :atlas.json)
                        pages {"https://h/a" (page [1] "https://h/a?p=2")
                               "https://h/a?p=2" (page [2])}
                        f (paginate.wrap (fn [req]
                                           (table.insert seen req)
                                           (let [util (require :atlas.util)]
                                             (. pages
                                                (util.append-query req.url
                                                                   (or req.query
                                                                       {})))))
                                         {})]
                    (f {:method "GET"
                        :url "https://h/a"
                        :headers {:x-key "k"}
                        :sensitive-headers [:x-key]})
                    (assert.are.same [:x-key] (. seen 2 :sensitive-headers)))))
            (it "keeps null members in the merged body"
                (fn []
                  (let [json (require :atlas.json)
                        (http) (site {"https://h/a" (page (json.decode "[{\"a\":null}]"
                                                                       true)
                                                          "https://h/a?p=2")
                                      "https://h/a?p=2" (page (json.decode "[{\"a\":null}]"
                                                                           true))})
                        f (paginate.wrap http {})
                        r (f {:method "GET" :url "https://h/a" :headers {}})]
                    (assert.are.equal "[{\"a\":null},{\"a\":null}]"
                                      (json.encode r.body)))))
            (it "stops at max-pages"
                (fn []
                  (let [(http seen) (site {"https://h/1" (page [1]
                                                               "https://h/2")
                                           "https://h/2" (page [2]
                                                               "https://h/3")
                                           "https://h/3" (page [3])})
                        f (paginate.wrap http {:max-pages 2})]
                    (assert.are.same [1 2]
                                     (. (f {:method "GET"
                                            :url "https://h/1"
                                            :headers {}})
                                        :body))
                    (assert.are.equal 2 (length seen)))))
            (it "leaves non-array bodies, non-GET requests and errors alone"
                (fn []
                  (let [(http seen) (site {"https://h/o" (page {:a 1}
                                                               "https://h/o2")})
                        f (paginate.wrap http {})]
                    (assert.are.same {:a 1}
                                     (. (f {:method "GET"
                                            :url "https://h/o"
                                            :headers {}})
                                        :body))
                    (f {:method "POST" :url "https://h/o" :headers {}})
                    (assert.are.equal 2 (length seen)))))
            (it "leaves bodies that only look like an array alone"
                (fn []
                  (let [first {:status 200
                               :headers {:link "<https://h/b>; rel=\"next\""}
                               :body "[1]\n[2]"
                               :raw "[1]\n[2]"}
                        (http seen) (site {"https://h/a" first
                                           "https://h/b" (page [3])})
                        f (paginate.wrap http {})
                        resp (f {:method "GET" :url "https://h/a" :headers {}})]
                    (assert.are.equal first resp)
                    (assert.are.equal 1 (length seen)))))
            (it "returns what it has when a later page fails"
                (fn []
                  (let [(http) (site {"https://h/a" (page [1] "https://h/b")})
                        f (paginate.wrap http {})
                        resp (f {:method "GET" :url "https://h/a" :headers {}})]
                    (assert.are.same [1] resp.body)
                    (assert.are.equal 404 resp.next-page-status))))))

(fn raw-page [raw ?next]
  (let [http (require :atlas.http)
        resp (http.decode-response 200
                                   (if ?next
                                       {:link (.. "<" ?next ">; rel=\"next\"")
                                        :content-type "application/json"}
                                       {:content-type "application/json"})
                                   raw)]
    resp))

(describe "paginate.wrap edge cases"
          (fn []
            (it "returns single-page responses untouched"
                (fn []
                  (let [first (raw-page "[1,null,3,0.1,12345678901234567890]")
                        f (paginate.wrap (fn [] first) {})]
                    (assert.are.equal first
                                      (f {:method "GET"
                                          :url "https://h/a"
                                          :headers {}})))))
            (it "keeps nulls and number text when merging pages"
                (fn []
                  (let [pages {"https://h/a" (raw-page "[1,null]" "https://h/b")
                               "https://h/b" (raw-page "[0.1, 12345678901234567890]")}
                        f (paginate.wrap (fn [req] (. pages req.url)) {})
                        resp (f {:method "GET" :url "https://h/a" :headers {}})]
                    (assert.are.equal "[1,null,0.1, 12345678901234567890]"
                                      resp.raw)
                    (assert.are.equal 4
                                      (select "#" (table.unpack resp.body 1 4)))
                    (assert.are.equal 0.1 (. resp.body 3)))))
            (it "does not follow userinfo tricks to another host"
                (fn []
                  (let [seen []
                        f (paginate.wrap (fn [req]
                                           (table.insert seen req.url)
                                           (raw-page "[1]"
                                                     "https://h:443@evil.example/p2"))
                                         {})]
                    (f {:method "GET" :url "https://h/a" :headers {}})
                    (assert.are.same ["https://h/a"] seen))))
            (it "distinguishes IPv6 hosts"
                (fn []
                  (let [seen []
                        f (paginate.wrap (fn [req]
                                           (table.insert seen req.url)
                                           (raw-page "[1]"
                                                     "https://[2001:db8::2]/p2"))
                                         {})]
                    (f {:method "GET"
                        :url "https://[2001:db8::1]/a"
                        :headers {}})
                    (assert.are.equal 1 (length seen)))))))

(describe "paginate.next-link parsing"
          (fn []
            (it "handles commas inside URLs and uppercase REL"
                (fn []
                  (assert.are.equal "https://h/x?ids=1,2&page=2"
                                    (paginate.next-link {:link "<https://h/x?ids=1,2&page=2>; REL=\"next\""}))))
            (it "handles commas inside quoted parameters"
                (fn []
                  (assert.are.equal "https://h/n"
                                    (paginate.next-link {:link "<https://h/p>; rel=\"prev\"; title=\"a, b\", <https://h/n>; rel=\"next\""}))))))

(describe "paginate.wrap with styled queries"
          (fn []
            (it "builds the first URL in the query's declared styles"
                (fn []
                  (let [seen []
                        f (paginate.wrap (fn [req]
                                           (table.insert seen req)
                                           {:status 200 :headers {} :raw "[]"})
                                         {})]
                    (f {:method "GET"
                        :url "https://h/items"
                        :query {:filter {:status {:in ["a"]}}}
                        :query-styles {:filter {:json true}}
                        :headers {}})
                    (assert.are.equal 1 (length seen)))))))
