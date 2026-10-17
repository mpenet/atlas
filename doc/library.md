# Library

[Documentation](README.md) › Library

The engine behind the `ezu` command line, for use from Fennel or Lua: it turns any OpenAPI 3 description into a client whose operations are functions. Path parameters, request bodies, query parameters and headers are handled for you, with the same encoding, TLS verification and redirect handling as the CLI; retries and pagination are available as wrappers you opt into.

Looking for the command line? Start with the [README](../README.md).

## Installation

```sh
luarocks install ezu
```

Or add to your project's rockspec:

```lua
dependencies = { "ezu" }
```

## Quick start

```fennel
(local ezu (require :ezu))

(local client (ezu.client "https://petstore3.swagger.io/api/v3/openapi.json"))

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
local ezu = require("ezu")
local client = ezu.client("https://petstore3.swagger.io/api/v3/openapi.json")
local resp = client["get-pet-by-id"].invoke({path = {petId = 42}})
print(resp.status, resp.body.name)
```

## Pages

- [Clients](library/clients.md): `ezu.client` and its options, base URL resolution, `$ref` resolution, a spec's servers, loading specs.
- [Operations](library/operations.md): `invoke` and the positional shorthand, responses, content negotiation, operation metadata, the Fennel REPL, errors.
- [HTTP](library/http.md): the HTTP adapter and streamed responses, retries and pagination, TLS, proxies.
- [Data](library/data.md): JSON values (arrays, null) and validation against a schema.
