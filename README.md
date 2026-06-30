# Atlas

<img width="225" height="225" src="https://github.com/user-attachments/assets/31408610-9fc2-47b1-a493-191d84eade9e" />

OpenAPI 3.x toolbox.

* Fennel/Lua client — point it at any schema (local file, URL, or parsed table) and get back a callable client.
* Standalone OpenAPI CLI — similar to Restish, with profiles, OAuth, mTLS, and shell completion.

## Install

**Lua library:**

```sh
luarocks install atlas-oai
```

**CLI — standalone binary** (no Lua required at runtime), download from https://github.com/mpenet/atlas/releases, then:

```sh
install -m 755 atlas-bin /usr/local/bin/atlas
```

**Build CLI from source:**

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

```clojure
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
# GET /pet/{petId}
#
# Find pet by ID.
#
# Usage: atlas <profile-or-schema> get-pet-by-id <petId>
#
# Path params:
#   petId            integer [required] — ID of pet to return
#
# Responses:
#   200    successful operation
#   404    Pet not found

# call an operation
atlas https://petstore3.swagger.io/api/v3/openapi.json get-pet-by-id 42

# query params
atlas https://petstore3.swagger.io/api/v3/openapi.json find-pets-by-status --query.status=available

# request body — inline, file, or stdin
atlas https://petstore3.swagger.io/api/v3/openapi.json add-pet -d '{"name":"Rex","status":"available"}'
atlas https://petstore3.swagger.io/api/v3/openapi.json add-pet --body=@pet.json
cat pet.json | atlas https://petstore3.swagger.io/api/v3/openapi.json add-pet -d @-

# request body — individual fields (numbers coerced automatically)
atlas https://petstore3.swagger.io/api/v3/openapi.json add-pet --body.name=Rex --body.status=available

# headers, timeout, verbose output
atlas https://petstore3.swagger.io/api/v3/openapi.json get-pet-by-id 42 \
  --header.authorization="Bearer tok" --timeout=10 -v

# extract a nested value from the response
atlas https://petstore3.swagger.io/api/v3/openapi.json get-inventory --select=.available

# index into an array
atlas https://petstore3.swagger.io/api/v3/openapi.json find-pets-by-status --select=.pets[0].name

# iterate an array — returns all matching values
atlas https://petstore3.swagger.io/api/v3/openapi.json find-pets-by-status --select=.pets[].name
```

HTTP 4xx/5xx responses are printed to stderr and exit with status 1. With `-v` the response headers are included.

### Options

| Flag | Description |
|------|-------------|
| `--list` | List all operations with summaries |
| `--help` | Show documentation for an operation |
| `--body=JSON\|@file\|@-` | Request body — inline JSON, file path, or stdin |
| `-d JSON\|@file\|@-` | Alias for `--body` |
| `--body.KEY=VAL` | Build request body from individual fields (numbers coerced automatically) |
| `--query.KEY=VAL` | Query parameter |
| `--header.KEY=VAL` | Per-request header |
| `--timeout=N` | Timeout in seconds |
| `--base-url=URL` | Override the base URL |
| `--output=FORMAT` | `json` (default), `raw`, `status`, `headers` |
| `--select=PATH` | Extract a nested value from the response (e.g. `.items[0].name`, `.items[].name`) |
| `--no-color` | Disable colored output |
| `-v`, `--verbose` | Print status line and response headers |
| `--reload` | Re-fetch and re-cache the schema |
| `--cache-ttl=N` | Schema cache TTL in seconds (default: 3600) |

### Profiles

Save named configurations in `~/.config/atlas/config.json`:

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
      "timeout": 30
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

#### Profile inheritance

Use `extends` to inherit from another profile, overriding only what differs:

```json
{
  "profiles": {
    "myapi": {
      "schema": "https://api.example.com/openapi.json",
      "base-url": "https://api.example.com",
      "tls": { "cert": "/path/to/client.pem", "key": "/path/to/client.key" },
      "auth": { "name": "oauth-authorization-code", "params": { "..." : "..." } }
    },
    "myapi-staging": {
      "extends": "myapi",
      "schema": "https://staging.example.com/openapi.json",
      "base-url": "https://staging.example.com"
    }
  }
}
```

`myapi-staging` inherits `tls` and `auth` from `myapi`. `headers` are deep-merged (child adds or overrides keys); all other fields are replaced by the child when present. Chains (`A extends B extends C`) and circular reference detection are supported. `atlas profile show` displays the fully resolved profile.

Manage profiles from the CLI:

```sh
atlas profile list
atlas profile show myapi
```

### Authentication

Add an `auth` block to a profile. atlas uses the same config shape as restish.

#### OAuth 2.0 — Authorization Code (browser)

Opens a browser, listens on a local callback server, and caches the token (with auto-refresh). Uses PKCE S256.

```json
{
  "profiles": {
    "myapi": {
      "schema": "https://api.example.com/openapi.json",
      "auth": {
        "name": "oauth-authorization-code",
        "params": {
          "authorize_url": "https://auth.example.com/oauth/authorize",
          "token_url": "https://auth.example.com/oauth/token",
          "client_id": "my-client",
          "scope": "openid email",
          "redirect_host": "localhost",
          "redirect_port": 8484,
          "redirect_path": "/"
        }
      }
    }
  }
}
```

`redirect_host`, `redirect_port`, and `redirect_path` must match a redirect URI registered with your OAuth provider. The defaults are `127.0.0.1`, a random port, and `/callback` — override them to match what your provider has registered.

If `client_secret` is omitted the flow runs as a public client (PKCE only). Set it for confidential clients:

```json
"client_secret": "env:MY_CLIENT_SECRET"
```

Values prefixed with `env:` are read from the environment at runtime.

#### OAuth 2.0 — Client Credentials

```json
{
  "profiles": {
    "myapi": {
      "schema": "https://api.example.com/openapi.json",
      "auth": {
        "name": "oauth-client-credentials",
        "params": {
          "token_url": "https://auth.example.com/oauth/token",
          "client_id": "env:CLIENT_ID",
          "client_secret": "env:CLIENT_SECRET",
          "scope": "read write",
          "audience": "https://api.example.com"
        }
      }
    }
  }
}
```

#### External tool

Delegates auth to an arbitrary shell command. Use this for custom signing, proprietary auth schemes, or credential helpers.

```json
{
  "profiles": {
    "myapi": {
      "schema": "https://api.example.com/openapi.json",
      "auth": {
        "name": "external-tool",
        "params": {
          "commandline": "my-auth-helper",
          "omitbody": false,
          "output": "bearer-token"
        }
      }
    }
  }
}
```

| Param | Description |
|-------|-------------|
| `commandline` | Shell command to execute (`/bin/sh -c`) |
| `omitbody` | If `true`, omit the request body from stdin (default: `false`) |
| `output` | `"bearer-token"` for plain-token output (see below) |

**Default mode (JSON signing):** the tool is called per-request. atlas writes a JSON object to stdin:

```json
{"method":"GET","uri":"https://api.example.com/items","headers":{},"body":""}
```

The tool must write a JSON object to stdout with headers to inject:

```json
{"headers":{"X-Signature":["abc123"],"Authorization":["Bearer tok"]}}
```

**Bearer-token mode (`output: "bearer-token"`):** the tool is called once (not per-request). It receives no stdin and must write a plain token to stdout. atlas injects `Authorization: Bearer <token>`.

```sh
# example: call a credential helper that prints a token
my-auth-helper --get-token
```

`atlas auth myapi` prints the headers the tool produces. There is no token cache for external tool auth.

#### Token management

```sh
# force re-authentication (clears cached token, opens browser)
atlas auth myapi

# clear cached token without re-authenticating
atlas auth myapi --logout
```

Tokens are cached in `~/.cache/atlas/tokens/<profile>.json` (mode 0600). The token is refreshed automatically using the refresh token when it expires. If the refresh fails, atlas re-authenticates interactively.

### mTLS

Add a `tls` block to a profile for mutual TLS (client certificate authentication). The schema is also fetched using the client certificate.

```json
{
  "profiles": {
    "myapi": {
      "schema": "https://api.example.com/openapi.json",
      "tls": {
        "cert": "/path/to/client.pem",
        "key": "/path/to/client.key",
        "insecure": false
      }
    }
  }
}
```

| Key | Description |
|-----|-------------|
| `cert` | Path to PEM client certificate |
| `key` | Path to PEM private key |
| `insecure` | Set `true` to skip server certificate verification |

For custom CA bundles or other luasec options, use `ssl` alongside or instead of `tls`:

```json
"ssl": { "cafile": "/etc/ssl/internal-ca.pem" }
```

`tls` and `ssl` are merged, with `tls` taking precedence for fields they share.

#### Combined example (OAuth + mTLS)

```json
{
  "profiles": {
    "internal-api": {
      "schema": "https://api.internal.example.com/openapi.json",
      "tls": {
        "cert": "/home/user/.pki/client.pem",
        "key": "/home/user/.pki/client.key"
      },
      "auth": {
        "name": "oauth-authorization-code",
        "params": {
          "authorize_url": "https://dex.internal.example.com/auth",
          "token_url": "https://dex.internal.example.com/token",
          "client_id": "my-cli",
          "scope": "openid email groups",
          "redirect_host": "localhost",
          "redirect_port": 8484,
          "redirect_path": "/"
        }
      }
    }
  }
}
```

### Schema caching

Schemas fetched from URLs are cached in `~/.cache/atlas/schemas/` with a 1-hour TTL by default.

```sh
# force re-fetch
atlas myapi --reload --list

# set cache TTL to 5 minutes
atlas myapi --cache-ttl=300 --list
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

`make binary` requires `fennel`, `lua`, `openssl`, and `pkg-config`. It statically links Lua, luasocket, luasec, and OpenSSL — the resulting binary is standalone with no runtime dependencies.

## License

Copyright © 2026 Max Penet
Distributed under the Mozilla Public License Version 2.0
