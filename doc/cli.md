# Atlas CLI

A standalone OpenAPI 3.x CLI. Point it at a schema or named profile and call operations directly from the shell.

## Installation

**Standalone binary** (no Lua required):

```sh
# download from https://github.com/mpenet/atlas/releases, then:
install -m 755 atlas-bin /usr/local/bin/atlas
```

**From source:**

```sh
make deps     # install luarocks dependencies
make install  # build and install to /usr/local/bin/atlas
```

**As a LuaRocks package** (requires Lua 5.4, luasocket, luasec in PATH):

```sh
luarocks install atlas-oai
```

## Synopsis

```
atlas <schema-or-profile> [operation] [path-params...] [options]
atlas profile <list|show> [name]
atlas auth <profile> [--logout]
atlas completion <fish|bash|zsh>
```

## Basic usage

```sh
# list all operations
atlas https://petstore3.swagger.io/api/v3/openapi.json --list

# show documentation for an operation
atlas https://petstore3.swagger.io/api/v3/openapi.json get-pet-by-id --help

# call an operation
atlas https://petstore3.swagger.io/api/v3/openapi.json get-pet-by-id 42

# query parameters
atlas https://petstore3.swagger.io/api/v3/openapi.json find-pets-by-status --query.status=available

# verbose — print status line and response headers
atlas https://petstore3.swagger.io/api/v3/openapi.json get-pet-by-id 42 -v
```

## Options reference

| Flag | Description |
|------|-------------|
| `--list` | List all operations with summaries |
| `--help` | Show documentation for an operation (or list all if no operation given) |
| `--body=JSON\|@file\|@-` | Request body — inline JSON, file path, or stdin |
| `-d JSON\|@file\|@-` | Alias for `--body` |
| `--body.KEY=VAL` | Set individual body fields (numbers coerced automatically) |
| `--query.KEY=VAL` | Query parameter (repeatable) |
| `--header.KEY=VAL` | Per-request header (repeatable) |
| `--timeout=N` | Timeout in seconds |
| `--base-url=URL` | Override the base URL from the schema |
| `--output=FORMAT` | Output format: `json` (default), `raw`, `status`, `headers` |
| `--select=PATH` | Extract a value from the response — see [Response selection](#response-selection) |
| `--no-color` | Disable colored JSON output |
| `-v`, `--verbose` | Print status line and response headers before the body |
| `--reload` | Bypass the schema cache and re-fetch |
| `--cache-ttl=N` | Schema cache TTL in seconds (default: 3600) |

## Request body

Three ways to supply a body:

```sh
# inline JSON
atlas myapi add-pet -d '{"name":"Rex","status":"available"}'

# from a file
atlas myapi add-pet --body=@pet.json

# from stdin
cat pet.json | atlas myapi add-pet -d @-

# individual fields (numbers coerced automatically)
atlas myapi add-pet --body.name=Rex --body.status=available --body.age=3
```

`--body.KEY=VAL` and `--body=…` are mutually exclusive. If both are given, `--body=…` wins.

## Response selection

`--select` extracts a nested value from the JSON response using a path expression.

| Syntax | Meaning |
|--------|---------|
| `.key` | Object field |
| `[N]` | Array index (0-based) |
| `[]` | Iterate all array elements |
| `.{f1,f2}` | Pick fields from an object or each element of an array |

Examples:

```sh
# scalar field
atlas myapi get-inventory --select=.available

# nested field
atlas myapi get-pet-by-id 42 --select=.category.name

# first element of an array
atlas myapi find-pets-by-status --select=.pets[0].name

# all names in an array
atlas myapi find-pets-by-status --select=.pets[].name

# pick fields from each object in an array
atlas myapi find-pets-by-status --select=.pets[].{id,name,status}

# chained
atlas myapi find-pets-by-status --select=.pets[].category.name
```

When `--select` matches multiple values (via `[]`), all matches are printed one per line. If the path does not match, nothing is printed and exit status is 0.

## Output formats

| `--output` | Description |
|-----------|-------------|
| `json` | Pretty-printed JSON with color (default) |
| `raw` | `tostring()` of the body — useful for plain-text responses |
| `status` | HTTP status code only |
| `headers` | Response headers only, one per line (`key: value`) |

HTTP 4xx/5xx responses are always printed to stderr and exit with status 1.

## Verbose mode

`-v` / `--verbose` prints the status line and all response headers before the body:

```
HTTP 200  0.124s
content-type: application/json
...

{ ... body ... }
```

## Profiles

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

Use a profile name instead of a schema URL:

```sh
atlas petstore --list
atlas petstore get-pet-by-id 42
atlas myapi add-pet -d '{"name":"Rex"}'
```

### Profile fields

| Field | Type | Description |
|-------|------|-------------|
| `schema` | string | Schema URL or local path |
| `base-url` | string | Override the schema's server URL |
| `headers` | object | Default headers for every request |
| `timeout` | number | Default timeout in seconds |
| `cache-ttl` | number | Schema cache TTL override for this profile |
| `auth` | object | Authentication configuration — see [Authentication](#authentication) |
| `tls` | object | mTLS configuration — see [mTLS](#mtls) |
| `ssl` | object | Raw luasec options merged with `tls` |
| `extends` | string | Inherit from another profile |

### Profile inheritance

Use `extends` to derive from another profile:

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

Rules:
- `headers` are **deep-merged** — child adds or overrides individual keys, parent keys survive.
- All other fields are **replaced** when present in the child.
- Chains (`A extends B extends C`) are supported.
- Circular `extends` references are detected and raise an error.

```sh
# inspect the fully-resolved profile
atlas profile show myapi-staging
```

## Profile management

```sh
atlas profile list           # list all profiles (name + schema)
atlas profile show <name>    # show fully resolved profile as JSON
```

## Authentication

Add an `auth` block to a profile. Values prefixed with `env:` are read from environment variables at runtime.

### OAuth 2.0 — Authorization Code

Opens a browser, listens on a local callback server, and caches the token. Uses PKCE S256. Tokens are refreshed automatically.

```json
{
  "auth": {
    "name": "oauth-authorization-code",
    "params": {
      "authorize_url": "https://auth.example.com/oauth/authorize",
      "token_url": "https://auth.example.com/oauth/token",
      "client_id": "my-client",
      "scope": "openid email",
      "redirect_host": "127.0.0.1",
      "redirect_port": 8484,
      "redirect_path": "/callback"
    }
  }
}
```

`redirect_host`, `redirect_port`, and `redirect_path` must match a redirect URI registered with your OAuth provider. Defaults: `127.0.0.1`, random port, `/callback`.

If `client_secret` is omitted the flow runs as a public client (PKCE only):

```json
"client_secret": "env:MY_CLIENT_SECRET"
```

### OAuth 2.0 — Client Credentials

For service-to-service or CI use:

```json
{
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
```

`scope` and `audience` are optional.

### OAuth 2.0 — Device Authorization

For headless environments (CI, SSH sessions, devices without a browser). Atlas displays a user code and URL on stderr, then polls until the user approves on another device.

```json
{
  "auth": {
    "name": "oauth-device-authorization",
    "params": {
      "device_authorization_url": "https://auth.example.com/oauth/device/authorize",
      "token_url": "https://auth.example.com/oauth/token",
      "client_id": "my-client",
      "scope": "openid email"
    }
  }
}
```

Atlas handles `authorization_pending` polling, `slow_down` backoff (adds 5 s per instruction), and `expired_token` / `access_denied` errors. Tokens are cached and refreshed automatically.

### External tool

Delegates authentication to an arbitrary shell command.

```json
{
  "auth": {
    "name": "external-tool",
    "params": {
      "commandline": "my-auth-helper",
      "omitbody": false,
      "output": "bearer-token"
    }
  }
}
```

| Param | Description |
|-------|-------------|
| `commandline` | Shell command executed via `/bin/sh -c` |
| `omitbody` | Omit the request body from stdin (default: `false`) |
| `output` | `"bearer-token"` for plain-token mode (see below) |

**Default mode (per-request signing):** the command is called for every request. Atlas writes a JSON object to stdin:

```json
{"method":"GET","uri":"https://api.example.com/items","headers":{},"body":""}
```

The command must write a JSON object to stdout with headers to inject:

```json
{"headers":{"X-Signature":["abc123"],"Authorization":["Bearer tok"]}}
```

**Bearer-token mode (`"output": "bearer-token"`):** the command is called once, receives no stdin, and must write a plain token to stdout. Atlas prepends `Bearer ` and injects the `Authorization` header. There is no token cache for this mode.

### Token management

```sh
# force re-authentication (clears cache, runs flow again)
atlas auth myapi

# clear cached token without re-authenticating
atlas auth myapi --logout

# for external-tool: print what headers the tool produces
atlas auth myapi
```

Tokens are stored in `~/.cache/atlas/tokens/<profile>.json` (mode 0600).

## mTLS

Add a `tls` block for mutual TLS. The schema is also fetched using the client certificate.

```json
{
  "tls": {
    "cert": "/path/to/client.pem",
    "key": "/path/to/client.key",
    "insecure": false
  }
}
```

| Key | Description |
|-----|-------------|
| `cert` | Path to PEM client certificate |
| `key` | Path to PEM private key |
| `insecure` | Set `true` to skip server certificate verification |

For a custom CA bundle or other luasec options, use `ssl` alongside or instead of `tls`:

```json
"ssl": { "cafile": "/etc/ssl/internal-ca.pem" }
```

`tls` and `ssl` are merged, with `tls` taking precedence for fields they share.

### Combined example (OAuth Authorization Code + mTLS)

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

## Schema caching

Schemas fetched from URLs are cached in `~/.cache/atlas/schemas/` with a 1-hour TTL.

```sh
# force re-fetch
atlas myapi --reload --list

# set TTL to 5 minutes for this invocation
atlas myapi --cache-ttl=300 get-pet-by-id 42
```

Set `cache-ttl` in the profile to persist a non-default TTL.

## Shell completion

```sh
# fish — install permanently
atlas completion fish > ~/.config/fish/completions/atlas.fish

# bash — add to ~/.bashrc
source <(atlas completion bash)

# zsh — add to ~/.zshrc (fpath must be set first)
atlas completion zsh > "${fpath[1]}/_atlas"
```

Completion provides:
- Profile names as the first argument (fetched from config)
- Operation names as the second argument (fetched live from the schema via `--complete-ops`)
- Subcommand names for `profile` and `auth`
- Shell names for `completion`

## Exit codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | HTTP 4xx/5xx response, network error, bad arguments, or authentication failure |
