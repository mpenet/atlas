;; ABOUTME: Specs for TLS settings: CA bundle discovery and the mapping of
;; ABOUTME: ssl options (cafile, capath, certificate, key, verify) to the transport's verification settings.
(local tls (require :atlas.tls))

(fn only [path]
  "exists? predicate true for path alone."
  #(= $ path))

(describe "tls.ca-bundle"
          (fn []
            (it "prefers SSL_CERT_FILE"
                (fn []
                  (assert.are.equal "/my/ca.pem"
                                    (tls.ca-bundle {:SSL_CERT_FILE "/my/ca.pem"}
                                                   (only "/etc/ssl/cert.pem")))))
            (it "finds the system bundle of each platform"
                (fn []
                  (each [_ path (ipairs ["/etc/ssl/cert.pem"
                                         "/etc/ssl/certs/ca-certificates.crt"
                                         "/etc/pki/tls/certs/ca-bundle.crt"
                                         "/etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem"
                                         "/etc/ssl/ca-bundle.pem"])]
                    (assert.are.equal path (tls.ca-bundle {} (only path))))))
            (it "returns nil when there is none"
                (fn []
                  (assert.is_nil (tls.ca-bundle {} #false))))))

(describe "tls.options"
          (fn []
            (let [env {}
                  exists (only "/etc/ssl/cert.pem")]
              (it "verifies peers against the system bundle by default"
                  (fn []
                    (assert.are.same {:verify true :cafile "/etc/ssl/cert.pem"}
                                     (tls.options nil env exists))))
              (it "maps the ssl option names"
                  (fn []
                    (assert.are.same {:verify true
                                      :cafile "/x.pem"
                                      :cert "c.pem"
                                      :key "k.pem"}
                                     (tls.options {:cafile "/x.pem"
                                                   :certificate "c.pem"
                                                   :key "k.pem"}
                                                  env exists))))
              (it "keeps an explicit capath instead of the bundle"
                  (fn []
                    (assert.are.same {:verify true :capath "/certs"}
                                     (tls.options {:capath "/certs"} env exists))))
              (it "uses SSL_CERT_DIR when there is no bundle file"
                  (fn []
                    (assert.are.same {:verify true :capath "/certs"}
                                     (tls.options nil {:SSL_CERT_DIR "/certs"}
                                                  #false))))
              (it "turns verification off only for verify none"
                  (fn []
                    (assert.are.same {:verify false}
                                     (tls.options {:verify "none"} env exists))
                    (assert.are.same {:verify false}
                                     (tls.options {:verify ["none"]} env exists))
                    (assert.is_true (. (tls.options {:verify "peer"} env exists)
                                       :verify))))
              (it "leaves the CA unset when nothing is found, so verification fails closed"
                  (fn []
                    (assert.are.same {:verify true} (tls.options nil {} #false)))))))
