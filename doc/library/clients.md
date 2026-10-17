# Clients

[Documentation](../README.md) › [Library](../library.md) › Clients

A client is built from a spec: each of its operations becomes a function. These functions build clients and read what a spec says about its servers.

## `ezu.client`

```fennel
(ezu.client schema ?opts)
```

Builds a client from a schema. `schema` is one of (YAML is read as YAML 1.2, so `no`, `on` and `1:20` stay strings, as OpenAPI requires):

- A string URL (`https://…` or `http://…`) — fetched and parsed at call time
- A local file path — read and parsed
- An already-parsed Lua table

Returns a table where each key is a kebab-case `operationId` (`getPetById` → `get-pet-by-id`). An operation without `operationId` is named after its method and path (`GET /pets/{petId}` → `get-pets-pet-id`), unless an `operationId` already takes that name. Each value is an operation: call `op.invoke` with a request table (recommended), or call the operation directly with positional arguments as a shorthand. See [Calling operations](operations.md#calling-operations).

### Options

| Key | Type | Description |
|-----|------|-------------|
| `:base-url` | string | Override `servers[1].url` from the schema |
| `:server-index` | number | Which of `servers` to use, 1-based (default 1) |
| `:server-vars` | table | Values for the selected server's `variables`, e.g. `{:zone "de-fra-1"}`; unknown names and values outside a variable's `enum` raise an error |
| `:headers` | table | Default headers sent with every request |
| `:timeout` | number | Default timeout in seconds |
| `:ssl` | table | TLS options (`cafile`, `capath`, `certificate`, `key`, `verify`) — see [SSL / TLS](http.md#ssl--tls) |
| `:http-fn` | function | Custom HTTP backend — see [HTTP adapter](http.md#http-adapter) |
| `:source-url` | string | Location of a schema passed as a parsed table, used to resolve relative server URLs and external `$ref`s |
| `:load-schema` | function | `(fn [location opts])` returning a parsed document; replaces `ezu.load-schema` for the schema and its external `$ref`s. `opts` is `{:ssl :headers :timeout}`, or `{:ssl :timeout :credentials false}` for a document on another origin than the spec's, which must be fetched without credentials |

### Base URL resolution

1. `:base-url` in opts — always wins
2. `servers[1].url` from the schema, if it is an absolute `https?://` URL (a schema without `servers` has one at `/`, as OpenAPI says)
3. If `servers[1].url` is relative to the host (`/api/v1`, or `//api.example.com/v1`) and the schema was loaded from a URL, it is resolved against that URL
4. If none of these produce an absolute URL, `ezu.client` raises an error — pass `:base-url` explicitly

An operation, or its path item, that declares its own `servers` uses one of them instead: the one at `:server-index` when it has that many, else its first (a relative one resolved against the client's base URL), unless `:base-url` was given. `:server-vars` may name the variables of any of the servers in use; each server takes those it declares.

Server URL variables (`{variable}`) take their value from `:server-vars`, falling back to the `default` in `servers[1].variables`:

```fennel
(ezu.client exoscale-spec {:server-vars {:zone "de-fra-1"}})
;; https://api-{zone}.exoscale.com/v2 → https://api-de-fra-1.exoscale.com/v2
```

## $ref resolution

All `$ref`s are resolved when the client is built, so parameters, request bodies, response schemas and path items that use `$ref` work transparently:

- Local refs (`#/components/schemas/Pet`), with JSON-pointer escapes (`~1`, `~0`) and percent-escapes decoded.
- Refs into other documents (`common.yaml#/Pet`, `https://…/shared.json#/Error`), resolved relative to the document that contains them. Each document is loaded once; this needs the schema's location, i.e. passing a path or URL to `ezu.client` (or `:source-url` with a parsed table).
- Every ref to the same place resolves to the same table, so a recursive schema is a cyclic table: for `Node` with a `next` property referring to `Node`, `node.properties.next` is `node`. Resolution is linear in the size of the spec. Code that walks `op.spec` or `op.body-schema` must not assume a tree (and must not serialise them as is).
- A ref that points nowhere raises an error naming the ref, rather than silently dropping what it described.

## `ezu.servers`

```fennel
(ezu.servers schema)
;; => [{:url "https://api-{zone}.exoscale.com/v2"
;;      :description nil
;;      :variables {:zone {:default "ch-gva-2" :enum ["ch-gva-2" "de-fra-1" …]}}}]
```

Lists a parsed schema's servers and their variables, e.g. to offer a choice before building a client with `:server-index` and `:server-vars`.

## `ezu.server-url`

```fennel
(ezu.server-url (. (ezu.servers schema) 1) {:zone "de-fra-1"})
;; => "https://api-de-fra-1.exoscale.com/v2"
```

A server's URL with its variables replaced by the given values or their defaults. Raises an error for a variable the server doesn't declare or a value outside its `enum`.

## `ezu.base-url`

```fennel
(ezu.base-url schema {:server-index 1 :server-vars {:zone "de-fra-1"}})
;; => "https://api-de-fra-1.exoscale.com/v2"
```

The URL a client built with the same options sends requests to: `:base-url` if given, else the chosen server's URL with its variables, made absolute against `:source-url` (the spec's location) when the server is relative. Operations that declare their own servers can still go elsewhere.

## `ezu.load-schema`

```fennel
(ezu.load-schema path ?opts)
```

Fetches and parses a schema. Used internally by `ezu.client` but exposed for cases where you want the raw parsed table:

```fennel
(local schema (ezu.load-schema "https://api.example.com/openapi.json"))
(local client (ezu.client schema {:base-url "https://staging.example.com"}))
```

`?opts` is `{:ssl {} :headers {} :timeout seconds}`: for HTTPS schemas, `:ssl` takes the [TLS options](http.md#ssl--tls), `:headers` are sent with the fetch request (useful for authenticated schema endpoints), and `:timeout` bounds it.

`ezu.parse-schema` parses schema text you fetched yourself: `(ezu.parse-schema text location)` returns the document, raising when it is not valid JSON or YAML, or not a mapping (an HTML error page, say). `location` names the document in error messages.
