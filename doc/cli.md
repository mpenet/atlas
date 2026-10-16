# CLI reference

Every command, option and configuration key of `atlas`. For a walkthrough, start with the [README](../README.md) and the [guide](guide.md); workflows have [their own page](arazzo.md).

- [Installation](#installation)
- [Commands](#commands)
- [Options](#options)
- [Requests](#requests)
- [Responses](#responses)
- [Configuration](#configuration)
- [Authentication](#authentication)
- [TLS and proxies](#tls-and-proxies)
- [Servers](#servers)
- [Schema cache](#schema-cache)
- [Shell completion](#shell-completion)
- [Exit codes](#exit-codes)

## Installation

### Homebrew

```sh
brew install mpenet/tap/atlas
```

On macOS or Linux. The full name is needed: Homebrew's own `atlas` is another tool. The formula installs the release binary below, plus bash, zsh and fish completion; `brew upgrade` follows new releases.

### Standalone binary

Download the binary for your platform from the [releases page](https://github.com/mpenet/atlas/releases) (`atlas-macos-arm64`, `atlas-macos-x86_64`, `atlas-linux-x86_64` or `atlas-linux-arm64`), then install it:

```sh
install -m 755 atlas-macos-arm64 /usr/local/bin/atlas
```

Each release lists the files' SHA-256 sums in `SHA256SUMS` and carries a [build provenance attestation](https://docs.github.com/en/actions/security-for-github-actions/using-artifact-attestations) proving the binary was built by this repository's release workflow:

```sh
shasum -a 256 -c SHA256SUMS --ignore-missing
gh attestation verify atlas-macos-arm64 --repo mpenet/atlas
```

The binary embeds Lua, luasocket, libcurl, mbedTLS and libyaml. The macOS binaries run on macOS 12 or later; the Linux binaries are fully static (built against musl), so they run on any distribution, old or new. HTTPS needs the system's CA certificates (the `ca-certificates` package on minimal Linux images); see [TLS and proxies](#tls-and-proxies).

### From source

```sh
# fennel, lunajson, luasocket, lyaml, busted
make deps
# produces bin/atlas-bin
make binary
# runs it with Lua's module paths emptied, and checks it links only system libraries
make check-binary
# installs bin/atlas-bin as /usr/local/bin/atlas (PREFIX=... and DESTDIR=... to change)
make install
```

Building needs a C compiler, `lua` (5.4 or later) and `luarocks`, `fennel`, `libyaml`, `pkg-config`, `unzip` and `curl`: the build downloads the mbedTLS and libcurl sources, checks them against pinned checksums and links them in statically.

### With luarocks

Installs `atlas` as a Lua script, together with the [library](library.md):

```sh
luarocks install atlas-oai
```

luarocks installs the Lua dependencies (lunajson, luasocket, lyaml) and compiles the libcurl binding, which needs the libcurl headers (`libcurl4-openssl-dev` on Debian and Ubuntu, `libcurl-devel` on Fedora; macOS ships them) and the libyaml headers. From a checkout: `luarocks make atlas-oai-dev-1.rockspec`.

## Commands

```
atlas op <profile-or-schema> [operation] [path-params...] [options]
atlas az <name-or-file> [workflow-id] [path-params...] [options]
atlas http [METHOD] <url-or-path> [options]
atlas mcp <profile-or-schema> [--allow-writes] [--arazzo NAME] [options]
atlas profile list
atlas profile show <name>
atlas profile import-restish [file] [--dry-run]
atlas auth <profile> [--logout]
atlas completion <fish|bash|zsh>
atlas --version
```

| Command | Description |
|---------|-------------|
| `op` | Call an operation. The first argument is a profile name, or a spec's URL or file path (JSON or YAML). Without an operation, lists the operations. |
| `az` | Run an [Arazzo workflow](arazzo.md) (`arazzo` is an alias). Without a workflow id, lists the workflows. |
| `http` | Sends a request to any URL, without a spec; see [Requests without a spec](#requests-without-a-spec-http). |
| `mcp` | Serves the API's operations, and Arazzo workflows, as tools to AI agents (MCP over stdio); see [MCP server](#mcp-server). |
| `profile list` | Profiles with the schema each one uses, inherited ones included. |
| `profile show` | A profile as atlas uses it, `extends` resolved. |
| `profile import-restish` | Adds the APIs of a Restish configuration as profiles; see [Moving from Restish](guide.md#moving-from-restish). |
| `auth` | Authenticates a profile now: for static credentials and external tools, prints the headers that would be sent (and a query API key, or the signing command); for OAuth, runs the flow again. `--logout` deletes the cached token. |
| `completion` | Prints the completion script for a shell; see [Shell completion](#shell-completion). |
| `--version` | Prints atlas's version and the libcurl and TLS library builds it uses. |

Operation names are the spec's `operationId`s in lowercase, dash-separated words: `getPetById` → `get-pet-by-id`, `projects/list_cards` → `projects-list-cards`. An operation without `operationId` is named after its method and path: `GET /pets/{petId}` → `get-pets-pet-id`. When two operationIds would get the same name, the first by path keeps it and the other is named after its method and path.

## Options

Options go anywhere after the command. `--name=value` and `--name value` are equivalent, except for the field options (`--q.`, `--h.`, `--b.`, `--i.`, `--server.`, `--ssl.`), which take `NAME=VALUE` as one argument. `--` ends the options: everything after it is positional (for a path parameter starting with `-`). An unknown option, or one that doesn't apply to the command (`--profile` on `op`, `--select` on `az`), is an error.

### Operations (`op`)

| Option | Description |
|--------|-------------|
| `--list` | List the operations with their summaries |
| `--help` | Show an operation's documentation (or list the operations) |
| `-d VALUE`, `--body=VALUE` | Request body: JSON or YAML inline, `@file`, or `@-` for stdin; see [Body](#body) |
| `--b.KEY=VAL`, `--body.KEY=VAL` | One body field; dotted keys build nested objects (`--b.disk.size=10`) |
| `--q.KEY=VAL`, `--query.KEY=VAL` | Query parameter; repeating a key sends a list (`--q.tag=a --q.tag=b`) |
| `--h.KEY=VAL`, `--header.KEY=VAL` | Request header; repeating a name joins the values with `, ` |
| `--select=PATH` | Print only part of the response; see [Selecting](#selecting) |
| `--output=FORMAT` | `json` (default), `yaml`, `raw`, `table`, `csv`, `tsv`, `status` or `headers` (anything else is an error); see [Output formats](#output-formats) |
| `--no-color` | Never colour the output (colours are only used on a terminal anyway) |
| `-v`, `--verbose` | Log the request and the response status and headers on stderr |
| `--dry-run` | Print the request instead of sending it; credentials redacted |
| `--curl` | Print an equivalent `curl` command instead of sending (credentials included) |
| `--no-validate` | Send even when the request doesn't match the spec; see [Checks](#checks-before-sending) |
| `--ignore-status` | Treat 4xx and 5xx responses as successes: print the body on stdout, exit 0 |
| `--timeout=N` | Give up on a request after N seconds |
| `--retry=N` | Retries for 408, 429, 500, 502, 503 and 504 responses and network errors (default 2); see [Retries](#retries) |
| `--retry-unsafe` | Also retry POST, PUT, PATCH and DELETE |
| `--retry-max-wait=N` | Longest wait between retries, in seconds (default 300) |
| `--max-pages=N` | Most pages to follow; see [Pagination](#pagination) (default 25) |
| `--no-paginate` | Return the first page only |
| `--base-url=URL` | Send requests to URL instead of the spec's server |
| `--servers` | List the spec's servers and their variables; see [Servers](#servers) |
| `--server-index=N` | Use the spec's Nth server (default 1) |
| `--server.NAME=VAL` | Set a server URL variable |
| `--ssl.KEY=VAL` | TLS option: `cafile`, `capath`, `certificate`, `key`, `verify` (`--ssl.verify=none` skips verification) |
| `--reload` | Fetch the spec again instead of using the cache |
| `--cache-ttl=N` | How long a fetched spec stays cached, in seconds (default 3600) |

### Workflows (`az`)

`az` takes `--help`, `--output`, `--no-color`, `-v`, `--no-validate`, `--timeout`, the retry options, `--base-url`, `--server-index`, `--server.` and `--ssl.` as above; `-d` and `--b.` set workflow inputs. And:

| Option | Description |
|--------|-------------|
| `-i KEY=VAL`, `--i.KEY=VAL`, `--input.KEY=VAL` | Workflow input |
| `--inputs=VALUE` | All inputs as a JSON or YAML object, inline or `@file` |
| `--profile=NAME` | Profile to authenticate with |
| `--arazzo-output=MODE` | `final` (default), `steps`, `progress` or `full`; see [Output modes](arazzo.md#output-modes) |
| `--max-gotos=N` | Most jumps to a single step before the workflow aborts (default 50) |

`--dry-run` and `--curl` are refused: later steps depend on real responses. Use `-v` to log every request.

### Requests without a spec (`http`)

```sh
atlas http https://api.example.com/health
atlas http GET /zones --profile exo
atlas http POST /instances --profile exo --b.name=web1 --b.disk.size=10
atlas http DELETE https://api.example.com/items/7 --profile ex -v
```

The method defaults to `GET`. A path (`/zones`) is appended to the API's URL: `--base-url`, else the profile's `base-url`, else its spec's server (with `--server-index` and `--server.`). A full URL is sent as is; with `--profile`, it must be on the profile's API origin. atlas refuses to send the profile's credentials anywhere else.

`http` goes through the same profile headers and query, authentication, retries, pagination, redirects, output and exit codes as `op`. It skips the spec-driven parts: operation names, parameter and body checks, and `--help` per operation. Its body is sent as given: `-d` with JSON is sent as JSON, with `Content-Type: application/json`; anything else goes as is, with the content type you set with `--h.Content-Type=…`. `--b.` fields build a JSON object, on top of `-d`'s JSON or YAML object if one is given.

`http` takes `--profile=NAME` and the `op` options above except `--list`, `--servers`, `--no-validate`, `--reload` and `--cache-ttl`.

### MCP server (`mcp`)

| Option | Description |
|--------|-------------|
| `--allow-writes` | Offer every operation, not only GET, HEAD and OPTIONS |
| `--arazzo=NAME` | Also offer the workflows of an Arazzo context or file |

`mcp` also takes `-v`, `--timeout`, the retry options, `--max-pages`, `--no-paginate`, `--base-url`, `--server-index`, `--server.`, `--ssl.`, `--reload` and `--cache-ttl` as above.

### Others

| Option | Commands | Description |
|--------|----------|-------------|
| `--logout` | `auth` | Delete the profile's cached token |
| `--timeout`, `--ssl.KEY=VAL` | `auth` | Also apply to `auth`'s requests to the token endpoint |
| `--dry-run` | `profile import-restish` | Show the profiles that would be added |

## Requests

### Path parameters

Path parameters are positional, in the order they appear in the path, and sent exactly as typed (percent-encoded). `--help` shows them.

```sh
atlas op petstore get-pet-by-id 7
```

### Query parameters and headers

```sh
atlas op petstore find-pets-by-status --q.status=available
atlas op myapi list-items --q.tag=a --q.tag=b --h.X-Request-Id=42
```

A profile's `query` and `headers` are added to every request; values given on the command line win.

### Body

```sh
# inline JSON (or YAML)
atlas op myapi add-pet -d '{"name": "Rex", "status": "available"}'

# from a file
atlas op myapi add-pet -d @pet.json

# from stdin
cat pet.json | atlas op myapi add-pet -d @-

# field by field
atlas op myapi add-pet --b.name=Rex --b.status=available --b.age=3

# nested fields
atlas op myapi create-vm --b.instance-type.id=abc123 --b.disk.size=10
```

`--b.` fields are merged: `--b.a.b=1 --b.a.c=2` gives `{"a": {"b": 1, "c": 2}}`. With `-d` as well, the fields are merged over its object.

Field values take their type from the request schema: a `string` property keeps `007` as `"007"`, `integer` and `number` properties become numbers, `boolean` takes `true` or `false`, and `array` and `object` properties take JSON (`--b.tags='["a","b"]'`). A field the schema doesn't describe follows JSON's rules: `42`, `-1.5`, `true` and `false` become numbers and booleans, anything else stays a string.

How `-d` is read depends on the operation's request content type:

- JSON, form (`application/x-www-form-urlencoded`) and `multipart/form-data` operations take JSON or YAML.
- Any other type (`application/octet-stream`, `text/plain`, XML, images…) is sent byte for byte: `atlas op myapi upload-image -d @photo.png`.

For `multipart/form-data`, a field whose value starts with `@` becomes a file part, named after the file: `--b.file=@photo.png`. Write `@@` for a value that starts with a literal `@`.

JSON bodies are encoded with object keys in sorted order, integers exactly and decimals in their shortest exact form, so the same command always sends the same bytes.

### Checks before sending

Before sending, atlas compares the request with the operation's description:

- A required query parameter or header that is missing is an error naming the option to add (`--q.status=…`). Headers count wherever they come from: `--h.`, the profile, or authentication.
- A query parameter the operation doesn't declare (often a typo) prints a warning listing the declared ones; the request is still sent.
- A JSON body is checked against the request schema: required properties, types, `enum`, nested objects and arrays, `additionalProperties: false`, lengths, ranges and item counts, `allOf`, `anyOf` and `oneOf`. Errors name the exact place, such as `body.disks[0].size: expected integer, got string`. `pattern` and `format` are not checked.

All problems are reported together and nothing is sent. `--no-validate` sends anyway, for specs stricter or looser than the API they describe.

### Retries

Responses with status 408, 429, 500, 502, 503 or 504, and network errors, are retried up to `--retry` times (default 2), for GET, HEAD and OPTIONS requests only unless `--retry-unsafe` is given. atlas waits as long as the response's `Retry-After` header asks, at most `--retry-max-wait` seconds, and otherwise 1, 2, 4… seconds. An authentication failure is never retried.

### Pagination

When a GET response is a JSON array and has a `Link: <…>; rel="next"` header, atlas follows the links and prints all items as one array. Every page is requested with the same headers and credentials; a link to another origin (scheme, host or port) is not followed. atlas stops after `--max-pages` pages (default 25). If a later page fails, the items collected so far are printed with a warning naming the failing status. `--no-paginate` prints the first page as it is.

## Responses

JSON, JSON Lines and YAML responses are decoded, so `--select` and every `--output` format work on them; a JSON Lines response is an array of its lines' values. Other content (text, HTML, XML, …) is printed as received.

### Output formats

| `--output` | Prints |
|------------|--------|
| `json` | The body as indented JSON with sorted keys (the default) |
| `yaml` | The body as YAML |
| `raw` | The body exactly as received; with `--select`, the selected value: strings as they are, an array of strings, numbers or booleans one per line, objects and other arrays as JSON |
| `table` | An array of objects (or one object) as aligned columns under a header; an array of other values one per line |
| `csv` | The same rows as CSV (RFC 4180 quoting), with a header |
| `tsv` | The same rows as tab-separated values, with a header; tabs, newlines and backslashes in values written `\t`, `\n`, `\\` |
| `status` | The status code |
| `headers` | The response headers, one `name: value` per line, sorted |

Table columns are the fields a selection ending in `{a,b}` picks, in that order, else every field of the rows, sorted, aligned by the columns text takes on a terminal (two for wide East Asian characters and most emoji, none for combining marks). Objects and arrays inside a cell are written as compact JSON, and null or missing fields as empty cells. Control characters in values are shown escaped (`\x1B`) on a terminal; in a file or a pipe, csv and tsv write them as they are. For workflows, `table`, `csv` and `tsv` print the outputs as one row.

Output is coloured only when stdout is a terminal, and never when the `NO_COLOR` environment variable is set or `--no-color` is given. When a successful response has no body, `HTTP <status>` is printed on stderr instead.

A 4xx or 5xx response is printed on stderr, after an `HTTP <status>` line, and atlas exits with `4` or `5`; `--ignore-status` prints it like a success instead.

### Selecting

`--select` prints part of a JSON response:

| Syntax | Selects |
|--------|---------|
| `.key` | A field of an object |
| `[N]` | Element N of an array, from 0; `[-1]` is the last |
| `[]` | Every element of an array; the rest of the path applies to each |
| `..key` | Every field `key`, at any depth, as an array; the rest of the path applies to each |
| `{a,b}` | Fields `a` and `b` of an object, or of each object of an array |
| `[?PATH OP VALUE]` | The elements of an array whose PATH compares to VALUE; the rest of the path applies to each |
| `[?PATH]` | The elements of an array where PATH is present and not null or false |

In a filter, OP is `==`, `!=`, `<`, `<=`, `>` or `>=`. PATH is a field or a dotted path into the element (`tags.env`). VALUE is a JSON string, number, `true`, `false` or `null`, or else a bare word, taken as a string. A missing field equals `null`. `<`, `<=`, `>` and `>=` compare two numbers or two strings and never match anything else. Filters in a row (`[?a==1][?b==2]`) narrow the same array. A malformed filter is an error.

```sh
atlas op petstore get-pet-by-id 7 --select .category.name
atlas op petstore find-pets-by-status --q.status=sold --select '[0].name'
atlas op petstore find-pets-by-status --q.status=sold --select '[].name'
atlas op petstore find-pets-by-status --q.status=sold --select '[].{id,name}'
atlas op exo list-instances --select '.instances[?state==running].{name,id}' --output=table
atlas op exo list-instances --select '..ip-address' --output=raw
```

For anything `--select` doesn't do, pipe the JSON to [jq](https://jqlang.org): output piped to another program has no colours, so `atlas op exo list-instances | jq …` works as is.

The selection is printed in the chosen `--output` format; `[]` gives an array. A path that matches nothing prints nothing (and `HTTP <status>` on stderr), and atlas exits 0.

### Verbose output

`-v` logs, on stderr, each request (`> METHOD URL` with the query, then its headers and body) and, once the response arrives, its status, timing and headers:

```
> GET https://petstore3.swagger.io/api/v3/pet/7
> accept: application/json, application/xml
> authorization: Bearer <redacted>
HTTP 200  0.475s
content-type: application/json
...
```

Credentials are redacted: every header and query parameter whose name contains `auth`, `cookie`, `key`, `token`, `secret`, `sig` or `passw` (so `Authorization`, `X-API-Key`, `api_key`, `X-Signature`…). The scheme of an `Authorization` header stays visible (`Bearer <redacted>`).

### Dry runs

`--dry-run` prints the request that would be sent, without sending it or authenticating: the header authentication would add shows as `<redacted>`. `--curl` prints a runnable `curl` command instead; it does authenticate, and its output contains the credentials.

## Configuration

The configuration is `~/.config/atlas/config.json` (`$XDG_CONFIG_HOME/atlas/config.json` when `XDG_CONFIG_HOME` is set):

```json
{
  "output": "yaml",
  "profiles": {
    "petstore": {
      "schema": "https://petstore3.swagger.io/api/v3/openapi.json",
      "timeout": 30
    }
  },
  "arazzo": {
    "pets": {"file": "/home/me/workflows/petstore.arazzo.yaml", "profile": "petstore"}
  }
}
```

Settings apply in this order, first found wins: command-line option, profile, top level of the configuration, default. File paths in the configuration are used as written: `~` is not expanded, and relative paths are relative to the current directory.

### Top level

| Key | Type | Description |
|-----|------|-------------|
| `profiles` | object | Profiles by name; see below |
| `arazzo` | object | Named workflow documents; see [Arazzo](arazzo.md#named-workflow-documents) |
| `output` | string | Default output format |
| `no-color` | boolean | Never colour the output |
| `verbose` | boolean | Always log requests and responses |
| `timeout` | number | Default timeout, in seconds |
| `max-pages` | number | Default page limit |
| `retry` | object | Retry defaults: `{"attempts": 2, "unsafe": false, "max-wait": 300}` |

### Profiles

| Key | Type | Description |
|-----|------|-------------|
| `schema` | string | The spec's URL or file path |
| `extends` | string | Profile to inherit from |
| `base-url` | string | Send requests here instead of the spec's server |
| `server-index` | number | Which of the spec's servers to use, from 1 |
| `server` | object | Server URL variables, e.g. `{"region": "eu"}` |
| `headers` | object | Headers sent with every request |
| `query` | object | Query parameters sent with every request |
| `auth` | object | Authentication; see [Authentication](#authentication) |
| `tls` | object | `cert`, `key`, `ca_cert`, `insecure`; see [TLS and proxies](#tls-and-proxies) |
| `ssl` | object | `cafile`, `capath`, `certificate`, `key`, `verify`; merged with `tls`, which wins |
| `timeout` | number | Timeout, in seconds |
| `retry` | object | Retry settings, like the top-level `retry` |
| `max-pages` | number | Page limit |
| `cache-ttl` | number | How long the fetched spec stays cached, in seconds |
| `output` | string | Output format |
| `no-color` | boolean | Never colour the output |
| `verbose` | boolean | Always log requests and responses |
| `mcp` | object | `{"operations": [...]}`: the operations `atlas mcp` offers, names or `*` patterns; see [MCP server](#mcp-server) |

A profile with `extends` takes every key of the profile it names and overrides them with its own, except `headers`, which are merged key by key. Chains (`a` extends `b` extends `c`) work; a cycle is an error. `atlas profile show NAME` prints the result.

## MCP server

`atlas mcp` makes an API usable by AI agents (Claude, Cursor, …) through the [Model Context Protocol](https://modelcontextprotocol.io): each operation becomes a tool the agent can call, authenticated with the profile. The credentials stay with atlas; the agent sees the tools and the responses.

```sh
# Claude Code
claude mcp add exo -- atlas mcp exo
```

```json
{"mcpServers": {"exo": {"command": "atlas", "args": ["mcp", "exo"]}}}
```

The second form is the configuration file of Claude Desktop and most other clients. Give the full path of `atlas` if the client doesn't search your `PATH`.

**Which operations.** By default, the read-only ones: GET, HEAD and OPTIONS. `--allow-writes` offers them all. A profile's `mcp.operations` lists exactly the operations to offer, writes included, by name or with `*` for any text:

```json
{"profiles": {"exo": {"schema": "https://api.example.com/openapi.json",
                      "mcp": {"operations": ["list-*", "get-instance", "start-instance"]}}}}
```

An unknown name, or a pattern that matches no operation, stops `atlas mcp` with an error.

Offer as few as the task needs: every tool's description and schema goes into the agent's context, and above 100 tools atlas warns. A large API (GitHub's read-only operations alone take about 900 KB) needs a list.

**Tools.** A tool is named like the operation in `atlas op` (`list-instances`). Its arguments are the path, query and header parameters, by name, and the request body as `body`; a name that two parameters share takes their location as prefix (`query.id`). Headers and query parameters the profile or its authentication adds are not arguments. The input schema is the spec's, in JSON Schema 2020-12 (OpenAPI 3.0's `nullable` and boolean `exclusiveMinimum`/`exclusiveMaximum` converted; recursive schemas as `$defs`), without the body's read-only properties. Annotations say which tools only read (`readOnlyHint`), and which may destroy (DELETE, PUT, PATCH) or are idempotent.

**Calls.** atlas checks the arguments before sending anything: required ones, parameter values and the body against their schemas. A JSON body that isn't an object or array (a string, a number) is sent as JSON. The result is the response body: JSON, or text. A 4xx or 5xx response, a network error or wrong arguments come back as a tool error with the status and body, so the agent can correct itself. Profile headers, retries, pagination and `-v` (on stderr) apply as for `atlas op`.

**Workflows.** `--arazzo=NAME` adds the workflows of an Arazzo context or file as tools named `workflow.WORKFLOW-ID`, with the workflow's inputs as arguments. They run with the context's profile, else the profile `atlas mcp` names, and return the workflow's outputs. `atlas mcp --arazzo=NAME` without a profile offers the workflows alone. They are offered whatever they do: list them in the context only if the agent may run them.

**Protocol.** atlas speaks MCP 2026-07-28, without sessions, and the earlier versions that open with `initialize` (2025-11-25, 2025-06-18, 2025-03-26, 2024-11-05), over stdio. It reads one JSON-RPC message (or batch) per line on stdin and writes the answers on stdout; logs go to stderr. It stops when stdin closes. External auth tools and the browser of OAuth flows never share its stdin or stdout.

## Authentication

A profile's `auth` names a method and its parameters. Any parameter written `env:NAME` is read from the environment variable `NAME` when needed.

Authentication runs only when a request is sent: never for `--help`, `--list`, `--servers`, `--dry-run` or completion, nor when the request's own headers already provide what it would add. A spec fetched from a URL is requested without credentials first, and with them only if the server answers 401 or 403; when the profile's `base-url` is on another origin than the spec, the spec gets neither credentials nor the profile's `headers`. Credentials are computed once per command, reused by retries and pagination, and a header given explicitly (with `--h.` or in the profile's `headers`) wins over the one authentication adds.

### `bearer`

```json
{"name": "bearer", "params": {"token": "env:API_TOKEN"}}
```

Sends `Authorization: Bearer <token>`.

### `basic`

```json
{"name": "basic", "params": {"username": "me", "password": "env:API_PASSWORD"}}
```

### `api-key`

```json
{"name": "api-key", "params": {"name": "X-API-Key", "in": "header", "value": "env:API_KEY"}}
```

With `"in": "query"`, the key is sent as a query parameter instead, and with `"in": "cookie"` as a cookie; `header` is the default.

### `oauth-authorization-code`

Opens the browser, receives the code on a local callback server, and exchanges it for a token, with PKCE (S256).

| Param | Description |
|-------|-------------|
| `authorize_url` | The provider's authorization endpoint |
| `token_url` | The provider's token endpoint |
| `client_id` | Client id |
| `client_secret` | Client secret; leave it out for a public client |
| `scope` | Scopes, space-separated |
| `redirect_host`, `redirect_port`, `redirect_path` | The callback address, which must match a redirect URI registered with the provider (default `127.0.0.1`, a random port, `/callback`) |

### `oauth-client-credentials`

For services and CI: `token_url`, `client_id`, `client_secret`, and optionally `scope` and `audience`.

### `oauth-device-authorization`

For machines without a browser: prints a code and a URL on stderr, then waits while you approve on another device. Params: `device_authorization_url`, `token_url`, `client_id`, and optionally `client_secret` and `scope`.

OAuth tokens are cached in `~/.cache/atlas/tokens/<profile>.json` (mode 0600; `$XDG_CACHE_HOME` replaces `~/.cache` when set) and refreshed when they expire. `atlas auth <profile>` signs in again; `atlas auth <profile> --logout` deletes the token.

### `external-tool`

Runs a command (through `/bin/sh -c`) that provides the credentials.

| Param | Description |
|-------|-------------|
| `commandline` | The command |
| `output` | `bearer-token` to read a token, see below; leave out to sign each request |
| `omitbody` | `true` to leave the body out of what the command receives |

To sign requests, the command runs for every request. It receives the request on stdin:

```json
{"method": "GET", "uri": "https://api.example.com/items?a=1", "headers": {}, "body": ""}
```

and prints the headers to add on stdout:

```json
{"headers": {"X-Signature": ["abc123"]}}
```

With `"output": "bearer-token"`, the command runs once per atlas invocation, receives nothing, and prints a token; atlas sends `Authorization: Bearer <token>`.

## TLS and proxies

Server certificates are verified, both the chain and the host name, against the system's CA certificates: the file named by `SSL_CERT_FILE` when set, else the usual bundle of macOS and of the major Linux distributions, else the directory named by `SSL_CERT_DIR`. Without any of them, HTTPS requests fail rather than go unverified.

A profile's `tls` sets a client certificate for mutual TLS (also used to fetch the spec), or a CA bundle to trust instead of the system's:

```json
"tls": {"cert": "/path/to/client.pem", "key": "/path/to/client.key", "ca_cert": "/path/to/ca.pem"}
```

`"insecure": true`, or `--ssl.verify=none` for one command, turns verification off. Don't use it outside of testing.

`ssl` takes the same settings under other names (`certificate`, `key`, `cafile`), plus `capath`, a directory of CA certificates; `tls` wins when both set the same thing.

Requests go through the proxy named by `https_proxy` or `HTTPS_PROXY` (HTTPS requests), `http_proxy` (HTTP requests; libcurl ignores the upper-case form, which CGI environments can set from a request header) or `all_proxy`/`ALL_PROXY`, except for the hosts listed in `no_proxy`/`NO_PROXY`. The proxy URL can carry credentials (`http://user:secret@proxy:3128`).

## Servers

Requests go to the first server the spec lists. `--servers` shows them all, with their variables:

```console
$ atlas op myapi --servers
* 1. https://api-{region}.example.com — Production
       region = eu  (default: eu; one of: eu, us)
  2. https://staging.example.com — Staging
```

`*` marks the server in use. `--server-index=2` (or `server-index` in a profile) picks another one, `--server.region=us` (or `server` in a profile) sets a variable, and `--base-url` (or `base-url`) replaces the server altogether. Values outside a variable's allowed values are an error.

## Schema cache

Specs fetched from a URL are cached in `~/.cache/atlas/schemas/` (`$XDG_CACHE_HOME/atlas/schemas/` when set) for an hour. `--reload` fetches the spec again, and `--cache-ttl` or a profile's `cache-ttl` change how long it stays cached.

## Shell completion

```sh
# fish
atlas completion fish > ~/.config/fish/completions/atlas.fish

# bash, in ~/.bashrc (works with the bash 3.2 of macOS)
eval "$(atlas completion bash)"

# zsh, in ~/.zshrc after compinit
eval "$(atlas completion zsh)"
```

Completion offers commands, profile names, operations (fish also shows their summaries), the declared query parameters and headers after `--q.` and `--h.`, the body's properties after `--b.`, server variables after `--server.`, allowed values after `NAME=`, workflow documents, workflows and their inputs after `--i.`, and the options of the current command. Specs come from the schema cache, so completion doesn't wait for the network once a spec has been used.

## Exit codes

| Code | Meaning |
|------|---------|
| 0 | Success, including any response with `--ignore-status` |
| 1 | Anything else that went wrong: bad arguments, a request that fails the checks, a network or TLS error, an authentication failure, a failed workflow |
| 4 | The API answered with a 4xx status |
| 5 | The API answered with a 5xx status |
