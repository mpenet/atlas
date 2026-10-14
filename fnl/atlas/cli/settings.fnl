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
      (when tls.ca_cert (tset ssl :cafile tls.ca_cert))
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

(fn display-options [profile p config]
  "Output settings: command line, then profile, then config."
  {:output (or p.output (?. profile :output) (?. config :output))
   :no-color (or p.no-color (?. profile :no-color) (?. config :no-color))
   :verbose (or p.verbose (?. profile :verbose) (?. config :verbose))})

(fn lazy-auth-headers [profile-name auth-cfg ssl]
  "Getter for the profile's auth headers, authenticating on first use only."
  (var headers nil)
  (fn []
    (when (= nil headers)
      (let [(ok h) (pcall auth.get-headers profile-name auth-cfg ssl)]
        (assert ok (.. "authentication failed: " (tostring h)))
        (set headers (collect [k v (pairs h)] (k:lower) v))))
    headers))

(fn with-auth-headers [auth-headers names base-fn]
  "Adds auth headers to each request; headers already set explicitly win, and
when they cover every auth header (names), auth doesn't run at all."
  (fn [req]
    (let [headers (collect [k v (pairs (or req.headers {}))]
                    k
                    v)
          covered (and (next names)
                       (accumulate [all true _ n (ipairs names) &until (not all)]
                         (not= nil (util.header headers n))))]
      (when (not covered)
        (each [k v (pairs (auth-headers))]
          (when (= nil (util.header headers k))
            (tset headers k v))))
      (base-fn (doto (collect [k v (pairs req)] k v)
                 (tset :headers headers))))))

(fn with-profile-query [query base-fn]
  "Adds the profile's query parameters to each request; explicit ones win."
  (fn [req]
    (let [merged (collect [k v (pairs query)] k v)]
      (each [k v (pairs (or req.query {}))]
        (tset merged k v))
      (base-fn (doto (collect [k v (pairs req)] k v)
                 (tset :query merged))))))

(fn client-options [profile-name profile p config ?transport]
  "Client options shared by op and az: profile headers, ssl, timeout, servers,
and the http-fn: auth headers (added on first use), pagination, retries,
request signing, logging, and the transport (or dry-run printing)."
  (let [ssl (merge-ssl profile p.ssl)
        verbose (. (display-options profile p config) :verbose)
        auth-cfg (let [a (?. profile :auth)]
                   (when (and a a.name (not= a.name "")) a))
        auth-names (if auth-cfg (auth.header-names auth-cfg) [])
        auth-headers (when auth-cfg
                       (if (and p.dry-run (not p.curl))
                           ;; --dry-run redacts credentials anyway: don't authenticate
                           #(collect [_ n (ipairs auth-names)] n "<auth>")
                           (lazy-auth-headers profile-name auth-cfg ssl)))
        transport (if p.curl (printing-transport curl-command) p.dry-run
                      (printing-transport request-text)
                      (or ?transport http-mod.request))
        logged (if verbose (wrap-log-request transport) transport)
        signed (or (when auth-cfg (auth.wrap-http-fn auth-cfg logged)) logged)
        retrying (retry.wrap signed (retry-options profile p config))
        pagination (paginate-options profile p config)
        paginated (if pagination (paginate.wrap retrying pagination) retrying)
        queried (if (?. profile :query)
                    (with-profile-query profile.query paginated)
                    paginated)]
    {:headers (collect [k v (pairs (or (?. profile :headers) {}))]
                (k:lower)
                v)
     :auth-headers auth-headers
     :auth-header-names auth-names
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
     ;; auth headers are added outside retries and pagination: computed once
     ;; per request, reused by every attempt and page, and an auth failure is
     ;; reported rather than retried as if it were a network error
     :http-fn (if auth-headers (with-auth-headers auth-headers auth-names
                                 queried)
                  queried)}))

(fn fetch-schema [url opts]
  "Fetch and parse a schema URL through opts.transport. Credentials are only
sent after the server answers 401/403, so help and listings don't trigger
authentication. opts: {:transport :headers :ssl :auth-headers}"
  (let [send #(opts.transport {:method "GET" :url url :headers $ :ssl opts.ssl})
        first (send (or opts.headers {}))
        resp (if (and opts.auth-headers
                      (or (= first.status 401) (= first.status 403)))
                 (let [headers (collect [k v (pairs (or opts.headers {}))]
                                 k
                                 v)]
                   (each [k v (pairs (opts.auth-headers))]
                     (when (= nil (util.header headers k))
                       (tset headers k v)))
                   (send headers))
                 first)]
    (assert (util.success? resp.status)
            (string.format "HTTP %s fetching schema from %s" resp.status url))
    (atlas.parse-schema (or resp.raw "") url)))

(fn load-schema-cached [url opts]
  "Schema at url from the cache when fresh, else fetched and cached.
opts: fetch-schema options plus {:ttl seconds :reload bool :cache bool}"
  (let [use-cache (not= opts.cache false)
        cached (when (and use-cache (not opts.reload))
                 (cache.get url (or opts.ttl 3600)))]
    (or cached (let [schema (fetch-schema url opts)]
                 (when use-cache (cache.put url schema))
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
 : display-options
 : fetch-schema
 : load-schema-cached}
