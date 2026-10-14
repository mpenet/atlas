;; ABOUTME: TLS settings for the transport: finds the system CA bundle and maps
;; ABOUTME: ssl options (cafile, capath, certificate, key, verify) to transport settings.

;; where systems keep their PEM bundle of trusted CAs
(local system-bundles ["/etc/ssl/cert.pem"
                       "/etc/ssl/certs/ca-certificates.crt"
                       "/etc/pki/tls/certs/ca-bundle.crt"
                       "/etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem"
                       "/etc/ssl/ca-bundle.pem"])

(local process-env (setmetatable {} {:__index #(os.getenv $2)}))

(fn file-exists? [path]
  (match (io.open path :r)
    f (do
        (f:close)
        true)
    _ false))

(fn ca-bundle [env exists?]
  "Path of the CA bundle: SSL_CERT_FILE, else the first system bundle found."
  (or (. env :SSL_CERT_FILE)
      (accumulate [found nil _ path (ipairs system-bundles) &until found]
        (when (exists? path) path))))

(fn verify-off? [verify]
  (if (= (type verify) :table)
      (accumulate [off false _ v (ipairs verify) &until off]
        (= v "none"))
      (= verify "none")))

(fn options [?ssl ?env ?exists]
  "Transport TLS settings {:verify :cafile :capath :cert :key} for ?ssl
options {:cafile :capath :certificate :key :verify}. Peers are verified
unless verify is \"none\", against cafile or capath when given, else
SSL_CERT_FILE, the system bundle or SSL_CERT_DIR."
  (let [ssl (or ?ssl {})
        env (or ?env process-env)
        exists? (or ?exists file-exists?)
        verify (not (verify-off? ssl.verify))
        result {: verify :cert ssl.certificate :key ssl.key}]
    (when verify
      (if (or ssl.cafile ssl.capath)
          (do
            (set result.cafile ssl.cafile)
            (set result.capath ssl.capath))
          (match (ca-bundle env exists?)
            bundle (set result.cafile bundle)
            _ (set result.capath (. env :SSL_CERT_DIR)))))
    result))

{: ca-bundle : options}
