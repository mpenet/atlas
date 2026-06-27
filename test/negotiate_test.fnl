(local negotiate (require :atlas.negotiate))

(describe "pick-content-type"
  #(do
    (it "prefers application/json"
      #(assert.equal "application/json"
                     (negotiate.pick-content-type
                       {:requestBody {:content {:application/json {}
                                                :text/plain {}}}})))
    (it "falls back to form encoding"
      #(assert.equal "application/x-www-form-urlencoded"
                     (negotiate.pick-content-type
                       {:requestBody {:content {:application/x-www-form-urlencoded {}}}})))
    (it "falls back to multipart"
      #(assert.equal "multipart/form-data"
                     (negotiate.pick-content-type
                       {:requestBody {:content {:multipart/form-data {}}}})))
    (it "picks first available when none preferred"
      #(assert.is_not_nil
         (negotiate.pick-content-type
           {:requestBody {:content {:text/plain {}}}})))
    (it "returns nil with no requestBody"
      #(assert.is_nil (negotiate.pick-content-type {})))))

(describe "pick-accept"
  #(do
    (it "collects content type from response"
      #(assert.equal "application/json"
                     (negotiate.pick-accept
                       {:responses {"200" {:content {:application/json {}}}}})))
    (it "deduplicates across multiple responses"
      #(assert.equal "application/json"
                     (negotiate.pick-accept
                       {:responses {"200" {:content {:application/json {}}}
                                    "404" {:content {:application/json {}}}}})))
    (it "joins multiple distinct content types"
      #(let [accept (negotiate.pick-accept
                      {:responses {"200" {:content {:application/json {}}}
                                   "404" {:content {:text/plain {}}}}})]
         (assert.truthy (accept:find "application/json"))
         (assert.truthy (accept:find "text/plain"))))
    (it "returns nil for empty responses"
      #(assert.is_nil (negotiate.pick-accept {:responses {}})))))
