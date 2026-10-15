# Library

The engine behind the `atlas` command line, for use from Fennel or Lua: it turns any OpenAPI 3 description into a client whose operations are functions. Path parameters, request bodies, query parameters and headers are handled for you, with the same encoding, TLS verification and redirect handling as the CLI; retries and pagination are available as wrappers you opt into.

Looking for the command line? Start with the [README](../README.md).

## Installation

```sh
luarocks install atlas-oai
```

Or add to your project's rockspec:

```lua
dependencies = { "atlas-oai" }
```

## Quick start

```fennel
(local atlas (require :atlas))

(local client (atlas.client "https://petstore3.swagger.io/api/v3/openapi.json"))

;; call an operation: name every part of the request
(client.list-pets.invoke)
(client.get-pet-by-id.invoke {:path {:petId 42}})
(client.add-pet.invoke {:body {:name "Rex" :status "available"}})
(client.find-pets-by-status.invoke {:query {:status "available"}})

;; positional shorthand, handy at the REPL
(client.get-pet-by-id 42)
```

From Lua:

```lua
local atlas = require("atlas")
local client = atlas.client("https://petstore3.swagger.io/api/v3/openapi.json")
local resp = client["get-pet-by-id"].invoke({path = {petId = 42}})
print(resp.status, resp.body.name)
```

## `atlas.client`

```fennel
(atlas.client schema ?opts)
```

Builds a client from a schema. `schema` is one of (YAML is read as YAML 1.2, so `no`, `on` and `1:20` stay strings, as OpenAPI requires):

- A string URL (`https://…` or `http://…`) — fetched and parsed at call time
- A local file path — read and parsed
- An already-parsed Lua table

Returns a table where each key is a kebab-case `operationId` (`getPetById` → `get-pet-by-id`). An operation without `operationId` is named after its method and path (`GET /pets/{petId}` → `get-pets-pet-id`), unless an `operationId` already takes that name. Each value is an operation: call `op.invoke` with a request table (recommended), or call the operation directly with positional arguments as a shorthand. See [Calling operations](#calling-operations).

### Options

| Key | Type | Description |
|-----|------|-------------|
| `:base-url` | string | Override `servers[1].url` from the schema |
| `:server-index` | number | Which of `servers` to use, 1-based (default 1) |
| `:server-vars` | table | Values for the selected server's `variables`, e.g. `{:zone "de-fra-1"}`; unknown names and values outside a variable's `enum` raise an error |
| `:headers` | table | Default headers sent with every request |
| `:timeout` | number | Default timeout in seconds |
| `:ssl` | table | TLS options (`cafile`, `capath`, `certificate`, `key`, `verify`) — see [SSL / TLS](#ssl--tls) |
| `:http-fn` | function | Custom HTTP backend — see [HTTP adapter](#http-adapter) |
| `:source-url` | string | Location of a schema passed as a parsed table, used to resolve relative server URLs and external `$ref`s |
| `:load-schema` | function | `(fn [location opts])` returning a parsed document; replaces `atlas.load-schema` for the schema and its external `$ref`s. `opts` is `{:ssl :headers :timeout}`, or `{:ssl :timeout :credentials false}` for a document on another origin than the spec's, which must be fetched without credentials |

### Base URL resolution

1. `:base-url` in opts — always wins
2. `servers[1].url` from the schema, if it is an absolute `https?://` URL (a schema without `servers` has one at `/`, as OpenAPI says)
3. If `servers[1].url` is relative to the host (`/api/v1`, or `//api.example.com/v1`) and the schema was loaded from a URL, it is resolved against that URL
4. If none of these produce an absolute URL, `atlas.client` raises an error — pass `:base-url` explicitly

An operation, or its path item, that declares its own `servers` uses one of them instead: the one at `:server-index` when it has that many, else its first (a relative one resolved against the client's base URL), unless `:base-url` was given. `:server-vars` may name the variables of any of the servers in use; each server takes those it declares.

Server URL variables (`{variable}`) take their value from `:server-vars`, falling back to the `default` in `servers[1].variables`:

```fennel
(atlas.client exoscale-spec {:server-vars {:zone "de-fra-1"}})
;; https://api-{zone}.exoscale.com/v2 → https://api-de-fra-1.exoscale.com/v2
```

## Calling operations

### `invoke`: the recommended form

```fennel
(op.invoke {:path {} :query {} :headers {} :body v :timeout n})
```

Every part of the request is named, so nothing depends on argument order or on whether the operation declares a body. All keys are optional.

```fennel
;; path params, by name
(client.update-pet.invoke {:path {:ownerId "o1" :petId 42}
                           :body {:name "Rex" :status "sold"}})

;; query params; array values repeat the key: status=available&status=sold
(client.find-pets-by-status.invoke {:query {:status ["available" "sold"]}})

;; headers and timeout for this call
(client.get-pet-by-id.invoke {:path {:petId 42}
                              :headers {:x-request-id "abc"}
                              :timeout 10})

;; a body operation called without a body
(client.add-pet.invoke {:query {:dry-run "1"}})
```

| Key | Type | Description |
|-----|------|-------------|
| `:path` | table | Path parameters by name; values are percent-encoded (`"a/b c"` → `a%2Fb%20c`) |
| `:query` | table | Query parameters, serialized in each declared parameter's `style` and `explode` (by default an array repeats the key, `{:id [1 2]}` → `id=1&id=2`; `explode: false` gives `id=1,2`; `deepObject` gives `filter[a]=1`) |
| `:headers` | table | Merged over client-level defaults; names are case-insensitive, per-request wins |
| `:body` | any | Request body, encoded according to the operation's `Content-Type` |
| `:timeout` | number | Overrides the client-level timeout for this call |

`op.url-for` takes the same table and returns the URL `invoke` would request, without sending anything:

```fennel
(client.update-pet.url-for {:path {:ownerId "o1" :petId 42} :query {:v 2}})
;; => "https://…/owners/o1/pets/42?v=2"
```

Parameters declared on the path item (shared by all of its methods) are merged with the operation's own; operation-level definitions win.

### Positional shorthand

Calling the operation directly is shorthand for quick REPL use:

```fennel
(op-name ...path-params ?body ?opts)
```

```fennel
(client.get-pet-by-id 42)
(client.update-pet "o1" 42 {:name "Rex"})
(client.find-pets-by-status {:query {:status "available"}})
```

Path parameters follow the order of the URL template (`/owners/{ownerId}/pets/{petId}` → `ownerId petId`). The body slot exists only when the operation declares a `requestBody`; pass `nil` there to send opts without a body: `(client.add-pet nil {:query {:dry-run "1"}})`. Prefer `invoke` in code that should keep working when a spec changes: if an operation gains a `requestBody`, positional opts would shift into the body slot.

The trailing `?opts` table accepts the same `:query`, `:headers` and `:timeout` keys as `invoke`.

## Response format

`invoke` and positional calls return a table:

```fennel
{:status 200
 :headers {:content-type "application/json" ...}
 :body <decoded-json-or-string>
 :raw "<response body exactly as received>"}
```

- JSON responses (`application/json`, `*/*+json`) are decoded into Lua tables, arrays marked as such (see [JSON values](#json-values)); malformed JSON falls back to the raw string.
- Other content types (text, HTML, XML, …) are returned as strings, untouched.
- Responses without a `Content-Type` are decoded when they parse as JSON.
- An empty body produces `nil` for `:body`.

The library never raises on HTTP error statuses — it returns the response table. Check `:status` yourself.

## Content negotiation

Atlas inspects the schema to set `Content-Type` and `Accept` automatically:

- `Content-Type` is the first of `application/json`, `application/x-www-form-urlencoded`, `multipart/form-data` declared in `requestBody.content`, else any declared type.
- `Accept` lists every media type declared across the operation's responses.

Client-level and per-request headers override these; header names are matched case-insensitively.

The request body is encoded to match `Content-Type`: tables are sent as JSON, form-encoded for `application/x-www-form-urlencoded`, or as `multipart/form-data` parts. String bodies are sent as-is, so other formats (XML, plain text, binary) work by passing an already-serialized string. `op.content-type` tells you which type an operation uses.

Multipart file parts are tables with `:filename`, `:content` and an optional `:content-type` (default `application/octet-stream`):

```fennel
(client.upload-form.invoke
  {:body {:description "avatar"
          :file {:filename "photo.png" :content png-bytes :content-type "image/png"}}})
```

## $ref resolution

All `$ref`s are resolved when the client is built, so parameters, request bodies, response schemas and path items that use `$ref` work transparently:

- Local refs (`#/components/schemas/Pet`), with JSON-pointer escapes (`~1`, `~0`) and percent-escapes decoded.
- Refs into other documents (`common.yaml#/Pet`, `https://…/shared.json#/Error`), resolved relative to the document that contains them. Each document is loaded once; this needs the schema's location, i.e. passing a path or URL to `atlas.client` (or `:source-url` with a parsed table).
- Every ref to the same place resolves to the same table, so a recursive schema is a cyclic table: for `Node` with a `next` property referring to `Node`, `node.properties.next` is `node`. Resolution is linear in the size of the spec. Code that walks `op.spec` or `op.body-schema` must not assume a tree (and must not serialise them as is).
- A ref that points nowhere raises an error naming the ref, rather than silently dropping what it described.

## `atlas.servers`

```fennel
(atlas.servers schema)
;; => [{:url "https://api-{zone}.exoscale.com/v2"
;;      :description nil
;;      :variables {:zone {:default "ch-gva-2" :enum ["ch-gva-2" "de-fra-1" …]}}}]
```

Lists a parsed schema's servers and their variables, e.g. to offer a choice before building a client with `:server-index` and `:server-vars`.

## `atlas.server-url`

```fennel
(atlas.server-url (. (atlas.servers schema) 1) {:zone "de-fra-1"})
;; => "https://api-de-fra-1.exoscale.com/v2"
```

A server's URL with its variables replaced by the given values or their defaults. Raises an error for a variable the server doesn't declare or a value outside its `enum`.

## `atlas.load-schema`

```fennel
(atlas.load-schema path ?opts)
```

Fetches and parses a schema. Used internally by `atlas.client` but exposed for cases where you want the raw parsed table:

```fennel
(local schema (atlas.load-schema "https://api.example.com/openapi.json"))
(local client (atlas.client schema {:base-url "https://staging.example.com"}))
```

`?opts` is `{:ssl {} :headers {} :timeout seconds}`: for HTTPS schemas, `:ssl` takes the [TLS options](#ssl--tls), `:headers` are sent with the fetch request (useful for authenticated schema endpoints), and `:timeout` bounds it.

`atlas.parse-schema` parses schema text you fetched yourself: `(atlas.parse-schema text location)` returns the document, raising when it is not valid JSON or YAML, or not a mapping (an HTML error page, say). `location` names the document in error messages.

## HTTP adapter

The default HTTP backend is libcurl. Replace it by passing `:http-fn`:

```fennel
(atlas.client schema {:http-fn my-fn})
```

The function receives a single table and must return a `{:status :headers :body}` response:

```fennel
(fn my-fn [req]
  ;; req fields:
  ;;   :method  — "GET", "POST", etc.
  ;;   :url     — full URL with no query string
  ;;   :query   — table of query params (or nil)
  ;;   :headers — table of request headers
  ;;   :body    — body value (table or string, or nil); encode it yourself if needed
  ;;   :timeout — timeout in seconds (or nil)
  ;;   :ssl     — TLS options table (or nil)
  {:status 200 :headers {} :body {:ok true}})
```

The default `atlas.http.request` function handles query-string encoding, content-type aware body encoding, timeouts and TLS options — your replacement must handle all of these itself.

It also follows redirects for GET and HEAD (301, 302, 303, 307, 308; up to 5, then an error). On a redirect to another origin, credential headers (`Authorization`, cookies, anything key/token/secret-like) are dropped; a redirect from `https` to `http` is not followed. Header names and values are checked before sending, so a value containing a line break is rejected rather than injecting extra headers. `atlas.http.encode-body` and `atlas.http.decode-response` are exported if you want to reuse the default encoding.

## Retries and pagination

Both are opt-in `http-fn` wrappers, composable with your own:

```fennel
(local http (require :atlas.http))
(local retry (require :atlas.retry))
(local paginate (require :atlas.paginate))

;; retry.wrap: 408/429/5xx and network errors, Retry-After aware
;; paginate.wrap: follows Link rel="next" on GET arrays
(atlas.client schema
              {:http-fn (-> http.request
                            (retry.wrap {:attempts 3})
                            (paginate.wrap {:max-pages 10}))})
```

`retry.wrap` options: `:attempts` (extra tries), `:unsafe` (also retry non-GET/HEAD/OPTIONS), `:max-wait` (cap per wait, seconds). A paginated response has `:pages`, and `:next-page-status` when a later page failed.

## Validation

`atlas.validate.check` returns a list of `"path: problem"` strings for a decoded value against a JSON Schema (the subset OpenAPI bodies use; `pattern` and `format` are not checked). Combined with an operation's `:body-schema`:

```fennel
(local validate (require :atlas.validate))
(validate.check client.create-instance.body-schema body :body)
;; => ["body.instance-type: required" "body.disk-size: expected integer, got string"]
```

## Operation metadata

Each operation on the client exposes metadata fields, e.g. `(. client.get-pet-by-id :path)`:

| Field | Example | Description |
|-------|---------|-------------|
| `:name` | `"get-pet-by-id"` | Its key in the client |
| `:operation-id` | `"getPetById"` | The spec's `operationId` (nil when it has none) |
| `:method` | `"get"` | HTTP method |
| `:path` | `"/pet/{petId}"` | Path template |
| `:path-params` | `["petId"]` | Path parameters, in template order |
| `:parameters` | | Declared parameters, path-level ones merged in |
| `:summary` | `"Find pet by ID"` | Summary, or nil |
| `:has-body` | `false` | Whether the operation takes a request body |
| `:content-type` | `"application/json"` | Request content type atlas chose, nil without a body |
| `:body-schema` | | Request body schema for that content type |
| `:spec` | | The operation object from the spec, `$ref`s resolved (may contain cycles) |
| `:fnl/docstring` | | Documentation for the Fennel REPL, rendered on first access |

## Fennel REPL integration

The `:fnl/docstring` field is picked up by the Fennel REPL's `(doc op)` form:

```fennel
>> (local atlas (require :atlas))
>> (local c (atlas.client "https://petstore3.swagger.io/api/v3/openapi.json"))
>> (doc c.get-pet-by-id)
GET /pet/{petId}

Find pet by ID.

Usage: (get-pet-by-id.invoke {:path {:petId …}})
       (get-pet-by-id petId)

Path params:
  petId            integer [required] — ID of pet to return

Responses:
  200    successful operation
  404    Pet not found
```

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
(atlas.client schema {:ssl {:cafile "/etc/ssl/internal-ca.pem"}})

;; mutual TLS (client certificate)
(atlas.client schema {:ssl {:certificate "/path/to/client.pem" :key "/path/to/client.key"}})

;; skip server certificate verification (not for production)
(atlas.client schema {:ssl {:verify "none"}})
```

## Proxies

Requests go through the proxy named by the standard environment variables: `https_proxy`/`HTTPS_PROXY` for HTTPS, `http_proxy` for HTTP, `all_proxy`/`ALL_PROXY` for both, with hosts listed in `no_proxy`/`NO_PROXY` reached directly. Credentials can be part of the proxy URL (`http://user:pass@proxy:3128`).

## JSON values

Response bodies are decoded with `atlas.json`, which keeps arrays apart from objects even when empty: a decoded `[]` is a table marked as an array, so it prints and re-encodes as `[]`, never `{}`. A body you build in Lua has no such mark, so mark empty arrays yourself:

```fennel
(local json (require :atlas.json))

;; sends "tags": []
(client.update-pet.invoke {:body {:name "Rex" :tags (json.array [])}})

;; true for any decoded array
(json.array? (. resp.body :tags))
```

JSON `null` is `json.null`, a value of its own: in arrays it keeps its place (`[1,null,3]` has three elements), and in response bodies a `null` member is kept (`{"a": null}` gives `{:a json.null}`), so a body prints and re-encodes as it was received. Test for it with `(= x json.null)`; it is truthy, like any table. `json.decode` leaves null members out unless its second argument is true; arrays always keep theirs.

`json.decode` and `json.encode` are available for your own JSON handling; `json.encode` sorts object keys, writes integers exactly and decimals in their shortest exact form.

## Error handling

`atlas.client` raises if:

- The schema cannot be fetched or parsed
- No usable base URL can be determined

Individual operation calls raise if:

- A required path parameter is missing
- The HTTP transport fails (network error, not an HTTP error status)
- JSON encoding of the request body fails

Wrap in `pcall` for recoverable error handling:

```fennel
(let [(ok resp) (pcall client.get-pet-by-id.invoke {:path {:petId 42}})]
  (if ok
      (print resp.status)
      (print (.. "error: " (tostring resp)))))
```
