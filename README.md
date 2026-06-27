# atlas

Runtime OpenAPI 3.x client for Fennel and Lua. Point it at any schema — local file, URL, or parsed table — and get back a callable client. No code generation, no build step.

Also ships as a standalone CLI for exploring and calling any HTTP API that has an OpenAPI schema.

## Install

**Lua library:**

```sh
luarocks install atlas
```

**CLI — standalone binary** (no Lua required at runtime):

```sh
# download from https://github.com/mpenet/atlas/releases, then:
install -m 755 atlas-bin /usr/local/bin/atlas
```

**CLI — from source:**

```sh
make deps     # installs luarocks dependencies
make install  # builds and installs bin/atlas to /usr/local/bin
```

## Library

### Creating a client

```fennel
(local atlas (require :atlas))

(local client (atlas.client "https://petstore3.swagger.io/api/v3/openapi.json"))
```

`atlas.client` accepts a schema as a file path, an `http(s)://` URL, or an already-parsed table. The base URL is read from `servers[1].url` in the schema.

```fennel
(atlas.client schema ?opts)
```

| Option | Type | Description |
|--------|------|-------------|
| `:base-url` | string | Override `servers[1].url` |
| `:headers` | table | Default headers sent with every request |
| `:timeout` | number | Default request timeout in seconds |
| `:ssl` | table | SSL options passed to luasec (`cafile`, `verify`, …) |
| `:http-fn` | fn | Custom HTTP backend — see [HTTP adapter](#http-adapter) |

### Calling operations

Each `operationId` in the schema becomes a function on the client, converted to kebab-case (`getPetById` → `get-pet-by-id`).

Signature: `(op-name ...path-params ?body ?opts)`

```fennel
; no params
(client.list-pets)

; path param
(client.get-pet-by-id 42)

; body (follows path params when requestBody is declared)
(client.add-pet {:name "Rex" :status "available"})

; path params + body
(client.update-pet 42 {:name "Rex" :status "sold"})

; query params via trailing opts map
(client.find-pets-by-status {:query {:status "available"}})

; per-request headers and timeout
(client.get-pet-by-id 42 {:headers {:x-request-id "abc"} :timeout 10})
```

Per-request opts:

| Key | Description |
|-----|-------------|
| `:query` | Query parameters |
| `:headers` | Merged over client-level defaults |
| `:timeout` | Overrides client-level timeout |

### HTTP adapter

The built-in adapter uses luasocket, luasec, and lunajson:

- Routes `https://` through luasec, `http://` through luasocket
- URL-encodes query params
- Sets `Content-Type` and `Accept` from the schema's content declarations
- Sets `Content-Length` automatically when a body is present
- Returns `{:status N :headers {} :body table-or-string-or-nil}`

Swap it out by passing `:http-fn`:

```fennel
(fn my-http [{: method : url : headers : query : body}]
  ; must return {:status N :headers {} :body ...}
  )

(local client (atlas.client schema {:http-fn my-http}))
```

### Content negotiation

`Content-Type` is selected from `requestBody.content` in this order:

1. `application/json`
2. `application/x-www-form-urlencoded`
3. `multipart/form-data`
4. First key present

`Accept` is the union of all `responses.*.content` keys.

### Docstrings

Every operation carries a docstring inspectable in the REPL:

```
>> (doc client.get-pet-by-id)

GET /pet/{petId}

Find pet by ID.

Usage: (get-pet-by-id petId)

Path params:
  petId            integer [required] — ID of pet to return

Responses:
  200    successful operation
  404    Pet not found
```

## CLI

```
atlas <schema-or-profile> [operation] [path-params...] [options]
```

### Basic usage

```sh
# list all operations
atlas https://petstore3.swagger.io/api/v3/openapi.json --list

# show documentation for an operation
atlas https://petstore3.swagger.io/api/v3/openapi.json get-pet-by-id --help

# call an operation
atlas https://petstore3.swagger.io/api/v3/openapi.json get-pet-by-id 42

# query params
atlas https://petstore3.swagger.io/api/v3/openapi.json find-pets-by-status --query.status=available

# request body — inline, file, or stdin
atlas https://petstore3.swagger.io/api/v3/openapi.json add-pet -d '{"name":"Rex","status":"available"}'
atlas https://petstore3.swagger.io/api/v3/openapi.json add-pet --body=@pet.json
cat pet.json | atlas https://petstore3.swagger.io/api/v3/openapi.json add-pet -d @-

# headers, timeout, verbose output
atlas https://petstore3.swagger.io/api/v3/openapi.json get-pet-by-id 42 \
  --header.authorization="Bearer tok" --timeout=10 -v
```

### Options

| Flag | Description |
|------|-------------|
| `--list` | List all operations with summaries |
| `--help` | Show documentation for an operation |
| `--body=JSON\|@file\|@-` | Request body — inline JSON, file path, or stdin |
| `-d JSON\|@file\|@-` | Alias for `--body` |
| `--query.KEY=VAL` | Query parameter |
| `--header.KEY=VAL` | Per-request header |
| `--timeout=N` | Timeout in seconds |
| `--base-url=URL` | Override the base URL |
| `--output=FORMAT` | `json` (default), `raw`, `status`, `headers` |
| `--no-color` | Disable colored output |
| `-v`, `--verbose` | Print status line and response headers |

### Profiles

Save named configurations in `~/.config/atlas/config.json` to avoid repeating URLs and credentials:

```json
{
  "profiles": {
    "petstore": {
      "schema": "https://petstore3.swagger.io/api/v3/openapi.json",
      "timeout": 30
    },
    "myapi": {
      "schema": "https://api.example.com/openapi.json",
      "base-url": "https://staging.example.com",
      "headers": { "authorization": "Bearer <token>" },
      "ssl": { "cafile": "/etc/ssl/ca.pem" }
    }
  }
}
```

Use the profile name in place of the schema URL:

```sh
atlas petstore --list
atlas petstore get-pet-by-id 42
atlas myapi add-pet -d '{"name":"Rex"}'
```

Manage profiles from the CLI:

```sh
atlas profile list
atlas profile show myapi
atlas profile add myapi \
  --schema=https://api.example.com/openapi.json \
  --base-url=https://staging.example.com \
  --header.authorization="Bearer <token>" \
  --timeout=30
atlas profile remove myapi
```

### Shell completion

```sh
# fish
atlas completion fish > ~/.config/fish/completions/atlas.fish

# bash — add to ~/.bashrc
source <(atlas completion bash)

# zsh — add to ~/.zshrc
atlas completion zsh > "${fpath[1]}/_atlas"
```

Completion provides profile names as the first argument, operation names as the second (fetched live from the schema), and subcommand names for `profile`.

## Building from source

```sh
make deps     # lunajson, luasocket, luasec, fennel, busted
make build    # compile Fennel → Lua
make test     # run test suite
make install  # install bin/atlas to /usr/local/bin
make binary   # build standalone binary → bin/atlas-bin
```

`make binary` requires `fennel`, `lua 5.4`, `openssl`, and `pkg-config`. It statically links Lua, luasocket, and luasec — the resulting binary only needs OpenSSL at runtime.

## License

MIT
