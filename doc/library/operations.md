# Operations

[Documentation](../README.md) › [Library](../library.md) › Operations

Calling the operations of a client, and what comes back.

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
| `:querystring` | string | The whole query string, already encoded (OpenAPI 3.2 `in: querystring`); `:query` is ignored when it is given |
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

- JSON responses (`application/json`, `*/*+json`) are decoded into Lua tables, arrays marked as such (see [JSON values](data.md#json-values)); malformed JSON falls back to the raw string.
- JSON Lines (`application/x-ndjson`, `application/ndjson`, `application/jsonl`) are decoded into an array of the lines' values, blank lines skipped; a line that isn't JSON leaves the whole body a string.
- YAML responses (`application/yaml`, `application/x-yaml`, `*/yaml`, `*/*+yaml`) are decoded like JSON; malformed YAML stays a string.
- Other content types (text, HTML, XML, …) are returned as strings, untouched.
- Responses without a `Content-Type` are decoded when they parse as JSON.
- An empty body produces `nil` for `:body`.

The library never raises on HTTP error statuses — it returns the response table. Check `:status` yourself.

## Content negotiation

Atlas inspects the schema to set `Content-Type` and `Accept` automatically:

- `Content-Type` is the first of `application/json`, `application/x-www-form-urlencoded`, `multipart/form-data` declared in `requestBody.content`, else another declared type; a range (`*/*`, `application/*`) comes last and sends JSON. In a multipart body, an array is one part per element, all with its name (several files under one field).
- `Accept` lists every media type declared across the operation's responses.

Client-level and per-request headers override these; header names are matched case-insensitively.

The request body is encoded to match `Content-Type`: tables are sent as JSON, form-encoded for `application/x-www-form-urlencoded`, or as `multipart/form-data` parts. String bodies are sent as-is, so other formats (XML, plain text, binary) work by passing an already-serialized string. `op.content-type` tells you which type an operation uses.

Multipart file parts are tables with `:filename`, `:content` and an optional `:content-type` (default `application/octet-stream`):

```fennel
(client.upload-form.invoke
  {:body {:description "avatar"
          :file {:filename "photo.png" :content png-bytes :content-type "image/png"}}})
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
