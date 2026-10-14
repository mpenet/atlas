;; ABOUTME: Config and profile resolution for the CLI: profiles, TLS, retry and
;; ABOUTME: pagination settings, and the client options shared by op and az.
(local atlas (require :atlas))
(local auth (require :atlas.auth))
(local cache (require :atlas.cache))
(local retry (require :atlas.retry))
(local paginate (require :atlas.paginate))
(local util (require :atlas.util))
(local http-mod (require :atlas.http))
(local json (require :lunajson))
(local {: wrap-log-request : request-text : curl-command : printing-transport}
       (require :atlas.cli.output))

(fn config-path []
  (.. (util.config-dir) "/config.json"))

(fn load-config []
  (let [f (io.open (config-path) :r)]
    (if f
        (let [(ok cfg) (pcall json.decode (f:read :*a))]
          (f:close)
          (if ok cfg (error (.. "corrupt config: " (config-path)))))
        {})))

(fn merge-profiles [base child]
  (let [result (collect [k v (pairs base)] k v)]
    (each [k v (pairs child)]
      (if (and (= k :headers) (= (type v) :table)
               (= (type (. result k)) :table))
          (let [merged (collect [hk hv (pairs (. result k))]
                         hk
                         hv)]
            (each [hk hv (pairs v)] (tset merged hk hv))
            (tset result k merged))
          (tset result k v)))
    result))

(fn resolve-profile [name profiles ?seen]
  (let [seen (or ?seen {})
        p (. profiles name)]
    (assert p (.. "Profile not found: " name))
    (assert (not (. seen name)) (.. "Circular extends: " name))
    (tset seen name true)
    (if p.extends
        (let [base (resolve-profile p.extends profiles seen)
              child (collect [k v (pairs p)] k v)]
          (tset child :extends nil)
          (merge-profiles base child))
        p)))

(fn tls->ssl [tls]
  (when tls
    (let [ssl {}]
      (when tls.cert (tset ssl :certificate tls.cert))
      (when tls.key (tset ssl :key tls.key))
      (when tls.insecure (tset ssl :verify "none"))
      (when (next ssl) ssl))))

(fn merge-ssl [profile cli-ssl]
  (let [ssl (collect [k v (pairs (or (?. profile :ssl) {}))]
              k
              v)
        tls (tls->ssl (?. profile :tls))]
    (when tls
      (each [k v (pairs tls)] (tset ssl k v)))
    (when cli-ssl
      (each [k v (pairs cli-ssl)] (tset ssl k v)))
    ssl))

(fn retry-options [profile p config]
  "Retry settings: CLI flags, then profile, then config, then defaults."
  (let [pick #(let [v (. p $1)]
                (if (not= nil v) v
                    (not= nil (?. profile :retry $2)) (?. profile :retry $2)
                    (not= nil (?. config :retry $2)) (?. config :retry $2)
                    $3))]
    {:attempts (pick :retry :attempts 2)
     :unsafe (pick :retry-unsafe :unsafe false)
     :max-wait (pick :retry-max-wait :max-wait 300)}))

(fn paginate-options [profile p config]
  "Pagination settings, or nil when disabled."
  (when (not p.no-paginate)
    {:max-pages (or p.max-pages (?. profile :max-pages) (?. config :max-pages)
                    25)}))

(fn client-options [profile-name profile p config]
  "Client options shared by op and az: headers (profile + auth), ssl,
timeout, base-url and the http-fn (request logging, request signing)."
  (let [ssl (merge-ssl profile p.ssl)
        verbose (or p.verbose (?. profile :verbose) (?. config :verbose))
        auth-cfg (let [a (?. profile :auth)]
                   (when (and a a.name (not= a.name "")) a))
        headers (collect [k v (pairs (or (?. profile :headers) {}))]
                  (k:lower)
                  v)
        transport (if p.curl (printing-transport curl-command)
                      p.dry-run (printing-transport request-text)
                      http-mod.request)
        base-fn (if verbose (wrap-log-request transport) transport)]
    (when auth-cfg
      (let [(ok h) (pcall auth.get-headers profile-name auth-cfg ssl)]
        (assert ok (.. "authentication failed: " (tostring h)))
        (each [k v (pairs h)]
          (tset headers (k:lower) v))))
    {:headers headers
     :ssl ssl
     :timeout (or p.timeout (?. profile :timeout) (?. config :timeout))
     :base-url (or p.base-url (?. profile :base-url))
     :server-index (or p.server-index (?. profile :server-index))
     :server-vars (let [vars (collect [k v (pairs (or (?. profile :server) {}))]
                               k
                               v)]
                    (each [k v (pairs (or p.server-vars {}))]
                      (tset vars k v))
                    vars)
     :http-fn (let [retrying (retry.wrap (or (when auth-cfg
                                               (auth.wrap-http-fn auth-cfg
                                                                  base-fn))
                                             base-fn)
                                         (retry-options profile p config))
                    pagination (paginate-options profile p config)]
                (if pagination (paginate.wrap retrying pagination) retrying))}))

(fn load-schema-cached [url ttl reload? ssl headers]
  (let [cached (when (not reload?) (cache.get url ttl))]
    (if cached
        cached
        (let [schema (atlas.load-schema url ssl headers)]
          (cache.put url schema)
          schema))))

{: config-path
 : load-config
 : merge-profiles
 : resolve-profile
 : tls->ssl
 : merge-ssl
 : retry-options
 : paginate-options
 : client-options
 : load-schema-cached}
