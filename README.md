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
(local client (anis.client "petstore.json"))

; from a URL
(local client (anis.client "https://petstore3.swagger.io/api/v3/openapi.json"))

(client.get-pet-by-id client 1)
(client.add-pet client {:name "Buddy" :status "available"})
(client.update-pet client 1 {:name "Buddy" :status "sold"})
(client.find-pets-by-status client {:status "available"})
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
(client.list-pets client)

; path params — positional, in template order
(client.get-pet-by-id client 42)

; body — follows path params for operations with requestBody
(client.add-pet client {:name "Rex" :status "available"})

; path params + body
(client.update-pet client 42 {:name "Rex" :status "sold"})

; query params — trailing map, any operation
(client.find-pets-by-status client {:status "available"})

; path params + query
(client.get-pet-by-id client 42 {:fields "name,status"})
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
