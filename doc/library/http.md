# HTTP

[Documentation](../README.md) › [Library](../library.md) › HTTP

How requests are sent, and how to change it: your own transport, retries, pagination, TLS and proxies.

## HTTP adapter

The default HTTP backend is libcurl. Replace it by passing `:http-fn`:

```fennel
(ezu.client schema {:http-fn my-fn})
```

The function receives a single table and must return a `{:status :headers :body}` response:

```fennel
(fn my-fn [req]
  ;; req fields:
  ;;   :method  — "GET", "POST", etc.
  ;;   :url     — full URL; it may already carry a query string (next pages)
  ;;   :query   — table of query params (or nil), to add to :url
  ;;   :query-styles — how to serialize each query param ({:style :explode :json});
  ;;              (ezu.util.append-query url query query-styles) does it
  ;;   :raw-body — the body already encoded, when set (multipart, signing)
  ;;   :headers — table of request headers
  ;;   :body    — body value (table or string, or nil); encode it yourself if needed
  ;;   :timeout — timeout in seconds (or nil)
  ;;   :ssl     — TLS options table (or nil)
  {:status 200 :headers {} :body {:ok true}})
```

A response may also carry `:raw`, the body's text; pagination merges pages from it when present, from `:body` otherwise. Responses from `ezu.http.request` carry `:timings`: the seconds from the start of the exchange to the end of each phase, as libcurl measures them (`:namelookup`, `:connect`, `:appconnect` for TLS, `:pretransfer`, `:starttransfer` for the first byte, `:total`). After redirects, they are the last exchange's, with `:redirects`, the time of the ones before it, counted in `:total`.

The default `ezu.http.request` function handles query-string encoding, content-type aware body encoding, timeouts and TLS options — your replacement must handle all of these itself.

A request may carry `:stream`, a function called with the status and headers of a response that isn't a redirect, when the first piece of its body arrives (so never for an empty body): when it returns a function, that function receives each piece of the body as it arrives (then nil), and the response comes back with `:streamed true` and no body. What that function raises ends the request and is never retried (tables keep their identity, marked `:permanent`), nor is a failure after the first piece. Redirects and responses it declines are buffered as usual.

It also follows redirects for GET and HEAD (301, 302, 303, 307, 308; up to 5, then an error). On a redirect to another origin, credential headers (`Authorization`, cookies, anything key/token/secret-like) are dropped; a redirect from `https` to `http` is not followed. Header names and values are checked before sending, so a value containing a line break is rejected rather than injecting extra headers. `ezu.http.encode-body` and `ezu.http.decode-response` are exported if you want to reuse the default encoding.

## Retries and pagination

Both are opt-in `http-fn` wrappers, composable with your own:

```fennel
(local http (require :ezu.http))
(local retry (require :ezu.retry))
(local paginate (require :ezu.paginate))

;; retry.wrap: 408/429/5xx and network errors, Retry-After aware
;; paginate.wrap: follows Link rel="next" on GET arrays
(ezu.client schema
              {:http-fn (-> http.request
                            (retry.wrap {:attempts 3})
                            (paginate.wrap {:max-pages 10}))})
```

`retry.wrap` options: `:attempts` (extra tries), `:unsafe` (also retry non-GET/HEAD/OPTIONS), `:max-wait` (cap per wait, seconds). A paginated response has `:pages`, and `:next-page-status` when a later page failed.

## SSL / TLS

Server certificates are verified, chain and host name, against the system's CA bundle: `$SSL_CERT_FILE` when set, else the first of `/etc/ssl/cert.pem`, `/etc/ssl/certs/ca-certificates.crt`, `/etc/pki/tls/certs/ca-bundle.crt`, `/etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem` and `/etc/ssl/ca-bundle.pem` that exists, else the directory in `$SSL_CERT_DIR`. Without any of them, HTTPS requests fail rather than go unverified.

`:ssl` changes this:

| Key | Description |
|-----|-------------|
| `cafile` | PEM bundle of CAs to trust instead of the system's |
| `capath` | Directory of CA certificates to trust instead of the system's |
| `certificate` | PEM client certificate, for mutual TLS |
| `key` | PEM private key of the client certificate |
| `verify` | `"none"` to skip verification (not for production) |

```fennel
;; custom CA bundle
(ezu.client schema {:ssl {:cafile "/etc/ssl/internal-ca.pem"}})

;; mutual TLS (client certificate)
(ezu.client schema {:ssl {:certificate "/path/to/client.pem" :key "/path/to/client.key"}})

;; skip server certificate verification (not for production)
(ezu.client schema {:ssl {:verify "none"}})
```

## Proxies

Requests go through the proxy named by the standard environment variables: `https_proxy`/`HTTPS_PROXY` for HTTPS, `http_proxy` for HTTP, `all_proxy`/`ALL_PROXY` for both, with hosts listed in `no_proxy`/`NO_PROXY` reached directly. Credentials can be part of the proxy URL (`http://user:pass@proxy:3128`).
