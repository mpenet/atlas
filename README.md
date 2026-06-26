# anis

Runtime OpenAPI 3.x client for Fennel. Points at any schema, builds a callable client. No code generation.

## Install

```sh
luarocks install anis
```

Dependencies: `lunajson`, `luasocket`, `luasec`.

Build from source:

```sh
make deps    # install luarocks dependencies
make build   # requires fennel on PATH
```

## Quick start

```fennel
(local anis (require :anis))

; from a local file
(local client (anis.client "petstore.json"))

; from a URL
(local client (anis.client "https://petstore3.swagger.io/api/v3/openapi.json"))

(client.get-pet-by-id 1)
(client.add-pet {:name "Buddy" :status "available"})
(client.update-pet 1 {:name "Buddy" :status "sold"})
(client.find-pets-by-status {:status "available"})
```

The base URL is read from `servers[1].url` in the schema. Override it via opts:

```fennel
(local client (anis.client "petstore.json"
                               {:base-url "https://staging.example.com/api/v3"
                                :headers {:authorization "Bearer <token>"}}))
```

## API

### `anis.client`

```fennel
(anis.client schema ?opts)
```

Builds a client table from an OpenAPI 3.x schema. Each `operationId` becomes a function on the returned table, named in kebab-case.

`schema` can be a local file path, an `http(s)://` URL, or an already-parsed table.

| Arg | Type | Description |
|-----|------|-------------|
| `schema` | string or table | File path, URL, or parsed schema table |
| `?opts` | table | Optional — see below |

| Option | Type | Description |
|--------|------|-------------|
| `:base-url` | string | Overrides `schema.servers[1].url` |
| `:headers` | table | Default headers sent with every request |
| `:http-fn` | fn | Custom HTTP backend — see [HTTP adapter](#http-adapter) |

### Calling operations

Operation names are derived from `operationId` converted to kebab-case (`getPetById` → `get-pet-by-id`).

```fennel
; no path params, no body
(client.list-pets)

; path params — positional, in template order
(client.get-pet-by-id 42)

; body — follows path params for operations with requestBody
(client.add-pet {:name "Rex" :status "available"})

; path params + body
(client.update-pet 42 {:name "Rex" :status "sold"})

; query params — nested under :query in trailing opts
(client.find-pets-by-status {:query {:status "available"}})

; path params + query + per-request options
(client.get-pet-by-id 42 {:query {:fields "name,status"} :timeout 10})

; per-request headers
(client.list-pets {:headers {:x-request-id "abc"} :timeout 5})
```

Signature pattern: `(op-name ...path-params ?body ?opts)`

`?opts` keys:

| Key | Description |
|-----|-------------|
| `:query` | Query params map |
| `:headers` | Per-request headers, merged over client defaults |
| `:timeout` | Request timeout in seconds |

### HTTP adapter

The default adapter uses luasocket + luasec with lunajson. It:

- Routes `https://` through luasec, `http://` through luasocket
- URL-encodes query params and appends to URL
- Sets `content-type` and `accept` headers from the schema
- Sets `content-length` automatically when a body is present
- Returns `{:status code :headers {} :body table-or-nil}`

To use a custom HTTP backend, pass `:http-fn` in opts:

```fennel
(fn my-http [{:method :url :headers :query :body}]
  ; ... return {:status code :headers {} :body table-or-nil}
  )

(local client (anis.client schema {:http-fn my-http}))
```

### Content negotiation

`Content-Type` is picked from `requestBody.content` keys in preference order:

1. `application/json`
2. `application/x-www-form-urlencoded`
3. `multipart/form-data`
4. First available

`Accept` is built from the union of all `responses.*.content` keys.

### REPL docstrings

Every operation carries a docstring readable via `(doc)`:

```
>> (doc client.get-pet-by-id)

GET /pet/{petId}

Find pet by ID.

Usage: (get-pet-by-id client petId)

Path params:
  petId          integer [required] — ID of pet to return

Responses:
  200    successful operation
  404    Pet not found
```

## License

MIT
