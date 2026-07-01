# Atlas — Lua/Fennel Library

Atlas turns any OpenAPI 3.x schema into a callable Lua/Fennel API client. Operations become functions; path parameters, request bodies, query params, and headers are handled automatically.

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

;; call an operation
(client.list-pets)
(client.get-pet-by-id 42)
(client.add-pet {:name "Rex" :status "available"})
```

## `atlas.client`

```fennel
(atlas.client schema ?opts)
```

Builds a client from a schema. `schema` is one of:

- A string URL (`https://…` or `http://…`) — fetched and parsed at call time
- A local file path — read and parsed
- An already-parsed Lua table

Returns a table where each key is a kebab-case `operationId` (`getPetById` → `get-pet-by-id`). Each value is a callable that takes positional path parameters, an optional body, and an optional opts table.

### Options

| Key | Type | Description |
|-----|------|-------------|
| `:base-url` | string | Override `servers[1].url` from the schema |
| `:headers` | table | Default headers sent with every request |
| `:timeout` | number | Default timeout in seconds |
| `:ssl` | table | luasec SSL options (`cafile`, `certificate`, `key`, `verify`, …) |
| `:http-fn` | function | Custom HTTP backend — see [HTTP adapter](#http-adapter) |
| `:source-url` | string | Original URL of the schema, used to resolve relative server URLs |

### Base URL resolution

1. `:base-url` in opts — always wins
2. `servers[1].url` from the schema, if it is an absolute `https?://` URL
3. If `servers[1].url` is a root-relative path (e.g. `/api/v1`) and the schema was loaded from a URL, the origin of that URL is prepended
4. If none of these produce an absolute URL, `atlas.client` raises an error — pass `:base-url` explicitly

Server URL variable substitution (`{variable}`) is applied using `default` values from `servers[1].variables`.

## Calling operations

Signature: `(op-name ...path-params ?body ?opts)`

```fennel
;; no params
(client.list-pets)

;; path param
(client.get-pet-by-id 42)

;; body (follows path params when requestBody is declared in the schema)
(client.add-pet {:name "Rex" :status "available"})

;; path params + body
(client.update-pet 42 {:name "Rex" :status "sold"})

;; query params via trailing opts table
(client.find-pets-by-status {:query {:status "available"}})

;; per-request headers and timeout
(client.get-pet-by-id 42 {:headers {:x-request-id "abc"} :timeout 10})

;; path param + body + opts
(client.update-pet 42 {:name "Rex"} {:headers {:x-trace "xyz"}})
```

### Per-request opts

| Key | Type | Description |
|-----|------|-------------|
| `:query` | table | Query parameters, URL-encoded automatically |
| `:headers` | table | Merged over client-level defaults (per-request wins) |
| `:timeout` | number | Overrides client-level timeout for this call |

## Response format

Operations return a table:

```fennel
{:status  200
 :headers {:content-type "application/json" ...}
 :body    <parsed-json-or-raw-string>}
```

- If the response body is valid JSON it is decoded into a Lua table.
- If it is not valid JSON (e.g. plain text, HTML) it is returned as a raw string.
- An empty body produces `nil` for `:body`.

The library never raises on HTTP error statuses — it returns the response table. Check `:status` yourself.

## Content negotiation

Atlas inspects the schema to set `Content-Type` and `Accept` automatically:

- `Content-Type` is set to the first content type declared in `requestBody.content` (typically `application/json`).
- `Accept` is set to the first content type declared in any `200`-range response's `content` map.

Per-request headers override these.

## $ref resolution

All `$ref` pointers in the schema are resolved recursively before the client is built. Circular references are detected and replaced with an empty table. This means parameters, request bodies, and response schemas that use `$ref` work transparently — you do not need to pre-resolve the schema yourself.

## `atlas.load-schema`

```fennel
(atlas.load-schema path ?ssl ?headers)
```

Fetches and parses a schema. Used internally by `atlas.client` but exposed for cases where you want the raw parsed table:

```fennel
(local schema (atlas.load-schema "https://api.example.com/openapi.json"))
(local client (atlas.client schema {:base-url "https://staging.example.com"}))
```

For HTTPS schemas, `?ssl` is a luasec options table. `?headers` are sent with the fetch request (useful for authenticated schema endpoints).

## HTTP adapter

The default HTTP backend uses luasocket + luasec. Replace it by passing `:http-fn`:

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
  ;;   :body    — already-decoded body table (or nil); encode it yourself if needed
  ;;   :timeout — timeout in seconds (or nil)
  ;;   :ssl     — luasec options table (or nil)
  {:status 200 :headers {} :body {:ok true}})
```

The default `atlas.http.request` function handles query-string encoding, JSON encoding of the body, and luasec SSL options — your replacement must handle all of these itself.

## Operation metadata

Each operation on the client exposes metadata fields:

```fennel
(. client.get-pet-by-id :summary)      ;; "Find pet by ID" (or nil)
(. client.get-pet-by-id :has-body?)    ;; true if operation has requestBody
(. client.get-pet-by-id :n-path)       ;; number of path parameters
(. client.get-pet-by-id :fnl/docstring) ;; multi-line Fennel REPL documentation
(. client.get-pet-by-id :cli/help)     ;; multi-line CLI-oriented help string
```

## Fennel REPL integration

The `:fnl/docstring` field is picked up by the Fennel REPL's `(doc op)` form:

```fennel
>> (local atlas (require :atlas))
>> (local c (atlas.client "https://petstore3.swagger.io/api/v3/openapi.json"))
>> (doc c.get-pet-by-id)
GET /pet/{petId}

Find pet by ID.

Usage: (get-pet-by-id petId)

Path params:
  petId            integer [required] — ID of pet to return

Responses:
  200    successful operation
  404    Pet not found
```

## SSL / TLS

Pass luasec options in `:ssl`:

```fennel
;; custom CA bundle
(atlas.client schema {:ssl {:cafile "/etc/ssl/internal-ca.pem"}})

;; mutual TLS (client certificate)
(atlas.client schema {:ssl {:certificate "/path/to/client.pem"
                             :key         "/path/to/client.key"}})

;; skip server certificate verification (not for production)
(atlas.client schema {:ssl {:verify "none"}})
```

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
(let [(ok resp) (pcall client.get-pet-by-id 42)]
  (if ok
      (print resp.status)
      (print (.. "error: " (tostring resp)))))
```
