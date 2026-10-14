;; ABOUTME: Converts Restish configs (v1 apis.json, v2 restish.json) into atlas
;; ABOUTME: profiles, reporting the settings that have no atlas equivalent.

(local auth-names ;; Restish auth type → atlas auth name, where they differ
       {:http-basic :basic :oauth-device-code :oauth-device-authorization})

(local unsupported-api-keys [:url_overrides
                             :pagination
                             :allowed_operation_origins
                             :command_layout])

(fn sorted-keys [t]
  (doto (icollect [k (pairs (or t {}))]
          k)
    (table.sort)))

(fn pairs->map [value sep]
  "v1 maps pass through; v2 lists of \"KEY<sep>VALUE\" become maps."
  (if (= nil value) nil (= nil (. value 1)) (when (next value) value)
      (collect [_ item (ipairs value)]
        (let [(k v) (item:match (.. "^(.-)%s*" sep "%s*(.*)$"))]
          (when k (values k v))))))

(fn convert-auth [auth where warn]
  "atlas auth for a Restish auth block (v1 `name`, v2 `type`), or nil."
  (let [kind (or auth.type auth.name "")]
    (when (not= kind "")
      (let [params (collect [k v (pairs (or auth.params {}))]
                     (if (= k :scopes) (values :scope v) (values k v)))]
        (when params.issuer_url
          (warn where
                "uses issuer_url (OIDC discovery); set authorize_url and token_url"))
        {:name (or (. auth-names kind) kind)
         :params (when (next params) params)}))))

(fn convert-tls [api prof]
  "atlas tls from v1 api.tls or v2 profile client_cert/client_key/ca_cert."
  (let [v1 (or api.tls {})
        tls {:cert (or prof.client_cert v1.cert)
             :key (or prof.client_key v1.key)
             :ca_cert (or prof.ca_cert v1.ca_cert)
             :insecure (when v1.insecure
                         true)}]
    (when (next tls) tls)))

(fn convert-profile [config api-name api profile-name prof warn]
  (let [where (if (= profile-name :default) api-name
                  (.. api-name "." profile-name))
        base (or prof.base_url prof.base api.base_url api.base)
        operation-base (or prof.operation_base api.operation_base)
        specs (or api.spec_files [])
        schema (or api.spec_url (. specs 1))
        auth (or prof.auth
                 (when prof.auth_ref
                   (or (?. config :auth_profiles prof.auth_ref)
                       (warn where
                             (.. "auth_ref '" prof.auth_ref
                                 "' not found in auth_profiles")))))]
    (when (> (length specs) 1)
      (warn where (string.format "%d spec_files; using the first (%s)"
                                 (length specs) (. specs 1))))
    (when (= nil schema)
      (warn where
            "no spec_files; set \"schema\" (atlas does not discover specs)"))
    (when prof.credentials
      (warn where "credentials are not supported; add an auth block"))
    (when prof.tls_signer
      (warn where "tls_signer is not supported"))
    (values where
            {:base-url (when base (.. base (or operation-base "")))
             : schema
             :headers (pairs->map prof.headers ":")
             :query (pairs->map prof.query "=")
             :tls (convert-tls api prof)
             :server (let [vars (collect [k v (pairs (or api.server_variables
                                                         {}))]
                                  k
                                  v)]
                       (each [k v (pairs (or prof.server_variables {}))]
                         (tset vars k v))
                       (when (next vars) vars))
             :auth (when auth (convert-auth auth where warn))})))

(fn convert [config]
  "(profiles warnings) for a parsed Restish config of either version: atlas
profiles keyed by name (API name for its default profile, API.PROFILE
otherwise) and sorted messages about settings that don't carry over."
  (let [apis (or config.apis
                 (collect [k v (pairs config)]
                   (when (not= (k:sub 1 1) "$") (values k v))))
        profiles {}
        warnings []
        warn (fn [where message]
               (table.insert warnings (.. where ": " message))
               nil)]
    (each [_ api-name (ipairs (sorted-keys apis))]
      (let [api (. apis api-name)]
        (each [_ key (ipairs unsupported-api-keys)]
          (when (. api key)
            (warn api-name (.. key " are not supported"))))
        (each [_ profile-name (ipairs (sorted-keys (or api.profiles
                                                       {:default {}})))]
          (let [(name profile) (convert-profile config api-name api
                                                profile-name
                                                (or (?. api :profiles
                                                        profile-name)
                                                    {})
                                                warn)]
            (tset profiles name profile)))))
    (table.sort warnings)
    (values profiles warnings)))

(fn find-config [env home exists?]
  "Path of the Restish config, searched as Restish does: restish.json, then the
legacy apis.json, in RSH_CONFIG_DIR, XDG_CONFIG_HOME/restish, ~/.config/restish,
then the older macOS and ~/.restish locations. nil when there is none."
  (let [dirs []]
    (when (. env :RSH_CONFIG_DIR)
      (table.insert dirs (. env :RSH_CONFIG_DIR)))
    (when (. env :XDG_CONFIG_HOME)
      (table.insert dirs (.. (. env :XDG_CONFIG_HOME) "/restish")))
    (each [_ d (ipairs [:/.config/restish
                        "/Library/Application Support/restish"
                        :/.restish])]
      (table.insert dirs (.. home d)))
    (accumulate [found nil _ file (ipairs [:restish.json :apis.json])
                 &until found]
      (accumulate [hit nil _ dir (ipairs dirs) &until hit]
        (let [path (.. dir "/" file)]
          (when (exists? path) path))))))

{: convert : find-config}
