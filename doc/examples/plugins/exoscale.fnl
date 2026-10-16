;; Signs Exoscale API requests (EXO2-HMAC-SHA256) as Exoscale's Go client
;; does. In the configuration:
;;
;;   "plugins": ["~/.config/atlas/plugins/exoscale.fnl"],
;;   "profiles": {"exo": {"schema": "https://openapi-v2.exoscale.com/source.json",
;;                        "auth": {"name": "exoscale",
;;                                 "params": {"key": "env:EXOSCALE_API_KEY",
;;                                            "secret": "env:EXOSCALE_API_SECRET"}}}}

(fn signed-query [atlas query]
  "The names of the query parameters given once, sorted, and their values
joined: what the signature covers of the query string."
  (let [counts {}
        by-name {}]
    (each [_ [name value] (ipairs (atlas.url.query query))]
      (tset counts name (+ 1 (or (. counts name) 0)))
      (tset by-name name value))
    (let [names (icollect [name n (pairs counts)]
                  (when (= n 1) name))]
      (table.sort names)
      (values names (table.concat (icollect [_ name (ipairs names)]
                                    (. by-name name)))))))

(fn sign [req params atlas]
  (let [url (atlas.url.parse req.url)
        (names query-values) (signed-query atlas url.query)
        ;; the signature is valid for 10 minutes
        expires (tostring (+ (os.time) 600))
        message (table.concat [(.. req.method " " (or url.path "/"))
                               (or req.body "")
                               query-values
                               ""
                               expires] "\n")]
    {:headers {:authorization (.. "EXO2-HMAC-SHA256 credential=" params.key
                                  (if (next names)
                                      (.. ",signed-query-args="
                                          (table.concat names ";"))
                                      "")
                                  ",expires=" expires ",signature="
                                  (atlas.base64 (atlas.hmac_sha256 params.secret
                                                                   message)))}}))

{:auth {:exoscale sign}}
