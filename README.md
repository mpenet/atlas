# anis

Runtime OpenAPI 3.x client for Fennel. Points at any schema, builds a callable client. No code generation.

## Install

```sh
luarocks install anis
```

Dependencies: `lunajson`, `luasocket`, `luasec`.

Build from source:

```sh
make build   # requires fennel on PATH
```

## Quick start

```fennel
(local anis (require :anis))

; from a local file
(local api (anis.build-client (anis.load-schema "petstore.json")))

; or directly from a URL
(local api (anis.build-client (anis.load-schema "https://petstore3.swagger.io/api/v3/openapi.json")))

(api.get-pet-by-id api 1)
(api.add-pet api {:name "Buddy" :status "available"})
(api.update-pet api 1 {:name "Buddy" :status "sold"})
(api.find-pets-by-status api {:status "available"})
```

The base URL is read from `servers[1].url` in the schema. Override it via opts:

```fennel
(local api (anis.build-client (anis.load-schema "petstore.json")
                               {:base-url "https://staging.example.com/api/v3"
                                :headers {:authorization "Bearer <token>"}}))
```

## API

### `anis.load-schema`

```fennel
(anis.load-schema path)
```

Reads an OpenAPI 3.x JSON schema from a local file or remote URL and returns a parsed schema table.

| Arg | Type | Description |
|-----|------|-------------|
| `path` | string | Local file path or `http(s)://` URL |

```fennel
; local file
(anis.load-schema "petstore.json")

; remote URL
(anis.load-schema "https://petstore3.swagger.io/api/v3/openapi.json")
```

### `anis.build-client`

```fennel
(anis.build-client schema ?opts)
```

Builds a client table from a parsed schema. Each `operationId` in the schema becomes a function on the returned table, named in kebab-case.

| Arg | Type | Description |
|-----|------|-------------|
| `schema` | table | Parsed OpenAPI schema |
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
(api.list-pets api)

; path params — positional, in template order
(api.get-pet-by-id api 42)

; body — follows path params for operations with requestBody
(api.add-pet api {:name "Rex" :status "available"})

; path params + body
(api.update-pet api 42 {:name "Rex" :status "sold"})

; query params — trailing map, any operation
(api.find-pets-by-status api {:status "available"})

; path params + query
(api.get-pet-by-id api 42 {:fields "name,status"})
```

Signature pattern: `(op-name client ...path-params ?body ?query)`

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

(local api (anis.build-client schema {:http-fn my-http}))
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
>> (doc api.get-pet-by-id)

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
