# Atlas CLI

A standalone OpenAPI 3.x CLI. Point it at a schema or named profile and call operations directly from the shell.

## Installation

Two options:

### Option 1 — Standalone binary (recommended)

No Lua runtime required. The binary embeds Lua, luasocket, luasec, and OpenSSL statically.

Download the binary for your platform from the [releases page](https://github.com/mpenet/atlas/releases), then install it:

```sh
install -m 755 atlas-bin /usr/local/bin/atlas
```

To build the binary from source instead:

```sh
make deps     # install luarocks dependencies (fennel, lunajson, luasocket, luasec)
make binary   # produces bin/atlas-bin
install -m 755 bin/atlas-bin /usr/local/bin/atlas
```

Requires `lua`, `fennel`, `openssl`, and `pkg-config` to build.

### Option 2 — Lua script (requires a Lua runtime)

Installs `atlas` as a Lua script that is run by the system Lua interpreter. Requires Lua 5.4+, luasocket, and luasec to be present at runtime.

```sh
luarocks install atlas-oai
```

Or build and install from source:

```sh
make deps     # install luarocks dependencies
make install  # builds standalone binary and installs to /usr/local/bin
```

## Synopsis

```
atlas op  <schema-or-profile> [operation] [path-params...] [options]
atlas az  <name-or-file> [workflow-id] [path-params...] [options]
atlas arazzo <name-or-file> [workflow-id] [path-params...] [options]   # alias for az
atlas profile <list|show> [name]
atlas auth <profile> [--logout]
atlas completion <fish|bash|zsh>
```

## Basic usage

```sh
# list all operations
atlas op https://petstore3.swagger.io/api/v3/openapi.json --list

# show documentation for an operation
atlas op https://petstore3.swagger.io/api/v3/openapi.json get-pet-by-id --help

# call an operation
atlas op https://petstore3.swagger.io/api/v3/openapi.json get-pet-by-id 42

# query parameters
atlas op https://petstore3.swagger.io/api/v3/openapi.json find-pets-by-status --query.status=available

# verbose — print status line and response headers
atlas op https://petstore3.swagger.io/api/v3/openapi.json get-pet-by-id 42 -v
```

## Options reference

| Flag | Description |
|------|-------------|
| `--list` | List all operations with summaries |
| `--help` | Show documentation for an operation (or list all if no operation given) |
| `--body=JSON\|@file\|@-` | Request body — inline JSON, file path, or stdin |
| `-d JSON\|@file\|@-` | Alias for `--body` |
| `--body.KEY=VAL` | Set individual body fields — supports deep dot paths: `--body.a.b.c=1` |
| `--query.KEY=VAL` | Query parameter (repeatable) |
| `--header.KEY=VAL` | Per-request header (repeatable) |
| `--timeout=N` | Timeout in seconds |
| `--base-url=URL` | Override the base URL from the schema |
| `--output=FORMAT` | Output format: `json` (default), `yaml`, `raw`, `status`, `headers` |
| `--select=PATH` | Extract a value from the response — see [Response selection](#response-selection) |
| `--no-color` | Disable colored JSON output |
| `-v`, `--verbose` | Print request details and response headers; for Arazzo, enables live step progress |
| `--reload` | Bypass the schema cache and re-fetch |
| `--cache-ttl=N` | Schema cache TTL in seconds (default: 3600) |

## Request body

Three ways to supply a body:

```sh
# inline JSON
atlas op myapi add-pet -d '{"name":"Rex","status":"available"}'

# from a file
atlas op myapi add-pet --body=@pet.json

# from stdin
cat pet.json | atlas op myapi add-pet -d @-

# individual fields (numbers coerced automatically)
atlas op myapi add-pet --body.name=Rex --body.status=available --body.age=3

# nested fields — dot-separated path, intermediate objects created and merged
atlas op myapi create-vm --body.instance-type.id=abc123 --body.disk-size=10
```

`--body.KEY=VAL` flags are deep-merged: `--body.a.b=1 --body.a.c=2` produces `{"a":{"b":1,"c":2}}`. `--body=…` and `--body.KEY=VAL` are mutually exclusive; `--body=…` wins if both are given.

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
atlas op myapi get-inventory --select=.available

# nested field
atlas op myapi get-pet-by-id 42 --select=.category.name

# first element of an array
atlas op myapi find-pets-by-status --select=.pets[0].name

# all names in an array
atlas op myapi find-pets-by-status --select=.pets[].name

# pick fields from each object in an array
atlas op myapi find-pets-by-status --select=.pets[].{id,name,status}

# chained
atlas op myapi find-pets-by-status --select=.pets[].category.name
```

When `--select` matches multiple values (via `[]`), all matches are printed one per line. If the path does not match, nothing is printed and exit status is 0.

## Output formats

| `--output` | Description |
|-----------|-------------|
| `json` | Pretty-printed JSON with color (default) |
| `yaml` | Pretty-printed YAML |
| `raw` | `tostring()` of the body — useful for plain-text responses |
| `status` | HTTP status code only |
| `headers` | Response headers only, one per line (`key: value`) |

HTTP 4xx/5xx responses are always printed to stderr and exit with status 1.

## Verbose mode

`-v` / `--verbose` enables full request and response detail across both regular calls and Arazzo workflows:

- **Regular calls**: logs `> METHOD URL`, request headers, and body to stderr before the response; then prints the status line and response headers.
- **Arazzo**: enables live step progress on stderr (see [Arazzo output modes](#output-modes-1)) and logs each HTTP request as it is made.

```
> GET https://api.example.com/pets/42
> accept: application/json
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
atlas op petstore --list
atlas op petstore get-pet-by-id 42
atlas op myapi add-pet -d '{"name":"Rex"}'
```

### Global config fields

Top-level fields in `config.json` apply to all invocations as defaults:

| Field | Type | Description |
|-------|------|-------------|
| `no-color` | bool | Disable colored output globally |
| `output` | string | Default output format (`json`, `yaml`, `raw`, `status`, `headers`) |
| `verbose` | bool | Always print status line and response headers |
| `timeout` | number | Default timeout in seconds |

```json
{
  "no-color": true,
  "output": "yaml",
  "verbose": false,
  "timeout": 30,
  "profiles": { ... }
}
```

### Profile fields

| Field | Type | Description |
|-------|------|-------------|
| `schema` | string | Schema URL or local path |
| `base-url` | string | Override the schema's server URL |
| `headers` | object | Default headers for every request |
| `timeout` | number | Default timeout in seconds |
| `cache-ttl` | number | Schema cache TTL override for this profile |
| `no-color` | bool | Disable colored output for this profile |
| `output` | string | Default output format for this profile |
| `verbose` | bool | Always print status line and response headers |
| `timeout` | number | Default timeout in seconds |
| `auth` | object | Authentication configuration — see [Authentication](#authentication) |
| `tls` | object | mTLS configuration — see [mTLS](#mtls) |
| `ssl` | object | Raw luasec options merged with `tls` |
| `extends` | string | Inherit from another profile |

Resolution order for `no-color`, `output`, `verbose`, and `timeout`: CLI flag → profile → global config.

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
atlas op myapi --reload --list

# set TTL to 5 minutes for this invocation
atlas op myapi --cache-ttl=300 get-pet-by-id 42
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
- Subcommand names (`op`, `az`, `profile`, `auth`, `completion`) as the first argument
- Profile names as the second argument after `op` or `auth`
- Operation names as the third argument after `op <profile>` (fetched live via `--complete-ops`)
- Subcommand names for `profile`
- Shell names for `completion`

## Arazzo workflow execution

Atlas executes [Arazzo 1.0](https://spec.openapis.org/arazzo/latest.html) workflow documents — multi-step API sequences with conditional branching, output passing between steps, polling loops, and criterion-based success checks. This is particularly useful for APIs where mutations are asynchronous: an Arazzo workflow can call the mutating operation and then poll a status endpoint until the operation completes, returning the final result — all in a single command.

### Usage

```sh
atlas az <name-or-file> [workflow-id] [path-params...] [options]
```

`atlas arazzo` is an alias for `atlas az`.

- `<name-or-file>` — a name from `~/.config/atlas/config.json` (see below), a local file path, or an `http(s)://` URL.
- If `workflow-id` is omitted, all available workflows are listed.
- The Arazzo document's `sourceDescriptions` of type `openapi` are loaded automatically as API clients.

### Configuration

Add an `"arazzo"` section to `~/.config/atlas/config.json` to name Arazzo files and attach defaults:

```json
{
  "arazzo": {
    "myapi": {
      "file": "./workflows/myapi.arazzo.json",
      "profile": "myapi-prod",
      "inputs": {
        "region": "eu-west-1"
      }
    }
  }
}
```

| Field | Description |
|-------|-------------|
| `file` | Path or URL of the Arazzo document |
| `profile` | Atlas profile to use for authentication and TLS (see [Profiles](#profiles)) |
| `inputs` | Default workflow inputs, overridden by CLI flags |

This composes directly with existing profiles: the named profile's auth (OAuth, mTLS, external-tool signing) and TLS settings are applied automatically to every API call made by the workflow. Override at runtime with `--profile=NAME`.

```sh
# use the profile configured in the arazzo entry
atlas az myapi create-resource --body.name=foo

# override the profile for this invocation
atlas az myapi create-resource --body.name=foo --profile=myapi-staging
```

### Path parameters

Path parameters declared in a workflow are passed as positional arguments after the workflow ID, in the order they appear in the workflow's step parameters:

```sh
# workflow with one path param (e.g. id)
atlas az myapi get-resource <uuid>

# multiple path params
atlas az myapi update-resource <resource-id> <version-id>
```

Named `-i` flags still work as an override:

```sh
atlas az myapi get-resource <uuid> -i id=override
```

### Request body

For operations with a request body, pass it with the same flags as regular CLI calls:

```sh
# inline JSON
atlas az myapi create-resource -d '{"name":"foo","size":10}'

# individual fields — supports deep dot-notation, fields are merged
atlas az myapi create-resource --body.name=foo --body.size=10

# nested fields (e.g. reference types with an id)
atlas az myapi create-vm \
  --body.instance-type.id=abc123 \
  --body.template.id=def456 \
  --body.disk-size=50
```

### Workflow inputs

Additional named inputs (not path params or body) use:

```sh
# short flag
atlas az myapi my-workflow -i timeout=30 -i region=eu

# long flag
atlas az myapi my-workflow --input.timeout=30

# JSON blob (all inputs at once)
atlas az myapi my-workflow --inputs='{"timeout":30,"region":"eu"}'
# or from a file
atlas az myapi my-workflow --inputs=@inputs.json
```

Merge priority (highest last): config `inputs` → `--inputs` blob → individual `-i`/`--input.*` flags.

### Output modes

| Mode | Description |
|------|-------------|
| `final` | Workflow outputs only (default) |
| `steps` | Each step's response body, then final outputs |
| `progress` | Live step tracking on stderr as steps execute, then final outputs |
| `full` | Like `steps` but also shows operation reference and request body per step |

```sh
atlas az myapi create-resource --body.name=foo --arazzo-output=progress
```

`-v` / `--verbose` is equivalent to `progress` mode and additionally logs every HTTP request (method, URL, headers, body) to stderr. Step outputs (declared in the Arazzo document) are printed after each step using the `--output` format.

Progress output uses color (suppressed by `--no-color`):
- `→ stepId` — step is running (dim)
- `✓ stepId  0.312s  HTTP 200  state=success` — step succeeded (green)
- `✗ workflow failed  1.024s` — workflow failed (red)

### Runtime expressions

| Expression | Resolves to |
|------------|-------------|
| `$inputs.KEY` | Workflow input |
| `$statusCode` | HTTP status of current response |
| `$response.body#/ptr` | JSON Pointer into response body |
| `$response.header.NAME` | Response header |
| `$request.body#/ptr` | JSON Pointer into request body |
| `$steps.ID.outputs.KEY` | Named output from a previous step |
| `$steps.ID.response.body#/ptr` | Response body from a previous step |
| `$url` | Request URL |
| `{$expr}` | Template string substitution |

### Success criteria

Steps use `successCriteria` to determine pass/fail. Supported criterion types:

- **Simple** — boolean expression: `$statusCode == 200`, `$response.body#/state == "success"`
- **Regex** — pattern match: `{"type":"regex","context":"$statusCode","condition":"^2"}`

On failure, `onFailure` actions run; on success, `onSuccess` actions. Supported action types: `end`, `goto` (by `stepId` or `workflowId`). `goto` targeting the same step sleeps 2 seconds before retrying (configurable via `retryAfter` on the action). Goto loops are detected and aborted after 50 iterations.

### Sub-workflows

A step with `workflowId` instead of `operationId`/`operationPath` runs another workflow as a nested step. Inputs are passed via the step's `parameters`.

### Examples

```sh
# list all workflows in a named file
atlas az myapi

# run a workflow, show progress
atlas az myapi create-resource \
  --body.name=foo \
  --body.size=10 \
  -v

# async operation — workflow polls until complete, returns result
atlas az myapi create-vm \
  --body.instance-type.id=abc123 \
  --body.template.id=def456 \
  --body.disk-size=50 \
  --output=yaml \
  -v

# load from URL, override profile
atlas az https://example.com/workflows.json deploy-service \
  --body.image=myapp:latest \
  --profile=prod
```

## Exit codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | HTTP 4xx/5xx response, network error, bad arguments, or authentication failure |
