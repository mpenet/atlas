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
(local http  (require :anis.http))
(local json  (require :lunajson))

(local schema (anis.load-schema "petstore.json" json.decode))

(local api (anis.build-client schema
                               "https://petstore3.swagger.io/api/v3"
                               (http.make json.encode json.decode)
                               {:headers {:authorization "Bearer <token>"}}))

(api.get-pet-by-id api 1)
(api.add-pet api {:name "Buddy" :status "available"})
(api.update-pet api 1 {:name "Buddy" :status "sold"})
(api.find-pets-by-status api {:status "available"})
```

## API

### `anis.load-schema`

```fennel
(anis.load-schema path json-decode)
```

Reads an OpenAPI 3.x JSON file and returns a parsed schema table.

| Arg | Type | Description |
|-----|------|-------------|
| `path` | string | Path to the JSON schema file |
| `json-decode` | fn | `(fn [string]) → table` — any JSON decoder |

### `anis.build-client`

```fennel
(anis.build-client schema base-url http-fn ?opts)
```

Builds a client table from a parsed schema. Each `operationId` in the schema becomes a function on the returned table, named in kebab-case.

| Arg | Type | Description |
|-----|------|-------------|
| `schema` | table | Parsed OpenAPI schema |
| `base-url` | string | Base URL, e.g. `"https://api.example.com"` |
| `http-fn` | fn | See [HTTP adapter](#http-adapter) |
| `?opts` | table | Optional. `{:headers {}}` for default headers sent with every request |

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

`anis.http/make` returns an `http-fn` backed by luasocket + luasec.

```fennel
(local http (require :anis.http))
(local http-fn (http.make json-encode json-decode))
```

| Arg | Type | Description |
|-----|------|-------------|
| `json-encode` | fn | `(fn [table]) → string` |
| `json-decode` | fn | `(fn [string]) → table` |

The adapter:
- Routes `https://` through luasec, `http://` through luasocket
- URL-encodes query params and appends to URL
- Sets `content-type` and `accept` headers from the schema
- Sets `content-length` automatically when a body is present
- Returns `{:status code :headers {} :body table-or-nil}`

To use a different HTTP backend, pass any function with the signature:

```fennel
(fn http-fn [{:method :url :headers :query :body}]) → response
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
