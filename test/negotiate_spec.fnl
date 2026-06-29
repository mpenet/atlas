(local negotiate (require :atlas.negotiate))

(describe "pick-content-type"
  (fn []
    (it "picks application/json"
      (fn []
        (assert.are.equal "application/json"
          (negotiate.pick-content-type
            {:requestBody {:content {:application/json {}}}}))))
    (it "prefers json over form-urlencoded"
      (fn []
        (assert.are.equal "application/json"
          (negotiate.pick-content-type
            {:requestBody {:content {"application/x-www-form-urlencoded" {}
                                     :application/json {}}}}))))
    (it "falls back to any content type"
      (fn []
        (assert.is_not_nil
          (negotiate.pick-content-type
            {:requestBody {:content {:text/plain {}}}}))))
    (it "returns nil when no requestBody"
      (fn []
        (assert.is_nil (negotiate.pick-content-type {}))))))

(describe "pick-accept"
  (fn []
    (it "returns content type from response"
      (fn []
        (assert.are.equal "application/json"
          (negotiate.pick-accept
            {:responses {"200" {:content {:application/json {}}}}}))))
    (it "deduplicates across responses"
      (fn []
        (assert.are.equal "application/json"
          (negotiate.pick-accept
            {:responses {"200" {:content {:application/json {}}}
                         "400" {:content {:application/json {}}}}}))))
    (it "sorts for stability"
      (fn []
        (let [op {:responses {"200" {:content {:application/json {}
                                               :text/plain {}}}}}]
          (assert.are.equal "application/json, text/plain"
            (negotiate.pick-accept op)))))
    (it "returns nil when no responses have content"
      (fn []
        (assert.is_nil
          (negotiate.pick-accept
            {:responses {"204" {:description "no content"}}}))))
    (it "is stable across repeated calls"
      (fn []
        (let [op {:responses {"200" {:content {:application/json {}
                                               :text/xml {}
                                               :text/plain {}}}}}]
          (assert.are.equal (negotiate.pick-accept op) (negotiate.pick-accept op)))))))
