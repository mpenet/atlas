# Configuration

[Documentation](README.md) › Configuration

The configuration is `~/.config/ezu/config.json` (`$XDG_CONFIG_HOME/ezu/config.json` when `XDG_CONFIG_HOME` is set):

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

Settings apply in this order, first found wins: command-line option, profile, top level of the configuration, default. File paths in the configuration are used as written: `~` is not expanded, and relative paths are relative to the current directory. [Plugins](authentication.md#plugins) are the exception: their paths start with `/` or `~/`.

## Top level

| Key | Type | Description |
|-----|------|-------------|
| `profiles` | object | Profiles by name; see below |
| `arazzo` | object | Named workflow documents; see [Arazzo](arazzo.md#named-workflow-documents) |
| `plugins` | array | Lua or Fennel files providing authentication methods; see [Plugins](authentication.md#plugins) |
| `output` | string | Default output format |
| `no-color` | boolean | Never colour the output |
| `verbose` | boolean | Always log requests and responses |
| `timeout` | number | Default timeout, in seconds |
| `max-pages` | number | Default page limit |
| `retry` | object | Retry defaults: `{"attempts": 2, "unsafe": false, "max-wait": 300}` |

## Profiles

| Key | Type | Description |
|-----|------|-------------|
| `schema` | string | The spec's URL or file path; without it, ezu finds the spec from `base-url` (see [Finding the spec](#finding-the-spec)) |
| `extends` | string | Profile to inherit from |
| `base-url` | string | Send requests here instead of the spec's server |
| `server-index` | number | Which of the spec's servers to use, from 1 |
| `server` | object | Server URL variables, e.g. `{"region": "eu"}` |
| `headers` | object | Headers sent with every request |
| `query` | object | Query parameters sent with every request |
| `auth` | object | Authentication; see [Authentication](authentication.md) |
| `tls` | object | `cert`, `key`, `ca_cert`, `insecure`; see [TLS and proxies](tls.md) |
| `ssl` | object | `cafile`, `capath`, `certificate`, `key`, `verify`; merged with `tls`, which wins |
| `timeout` | number | Timeout, in seconds |
| `retry` | object | Retry settings, like the top-level `retry` |
| `max-pages` | number | Page limit |
| `cache-ttl` | number | How long the fetched spec stays cached, in seconds |
| `output` | string | Output format |
| `no-color` | boolean | Never colour the output |
| `verbose` | boolean | Always log requests and responses |
| `mcp` | object | `{"operations": [...]}`: the operations `ezu mcp` offers, names or `*` patterns; see [MCP server](mcp.md) |

A profile with `extends` takes every key of the profile it names and overrides them with its own, except `headers`, which are merged key by key. Chains (`a` extends `b` extends `c`) work; a cycle is an error. `ezu profile show NAME` prints the result.

## Servers

Requests go to the first server the spec lists. `--servers` shows them all, with their variables:

```console
$ ezu op myapi --servers
* 1. https://api-{region}.example.com — Production
       region = eu  (default: eu; one of: eu, us)
  2. https://staging.example.com — Staging
```

`*` marks the server in use. `--server-index=2` (or `server-index` in a profile) picks another one, `--server.region=us` (or `server` in a profile) sets a variable, and `--base-url` (or `base-url`) replaces the server altogether. Values outside a variable's allowed values are an error.

## Finding the spec

A profile with `base-url` and no `schema` lets ezu find the spec, the way Restish does. It looks, in order, at:

1. the links of the base URL's `Link` header with `rel="service-desc"`, `"service-doc"` or `"describedby"` ([RFC 8631](https://www.rfc-editor.org/rfc/rfc8631)), on the base URL's origin only;
2. `openapi.json` and `openapi.yaml` under the base URL (before its query string, if any);
3. the base URL itself;
4. `openapi.json` and `openapi.yaml` at the root of the base URL's origin, when the base URL has a path.

The first that is an OpenAPI document is used, and where it was found is cached like the spec (`--reload` looks again, and so does ezu when the spec it remembered is gone). Credentials follow the spec's rules: sent only once a URL answers 401 or 403. When nothing is found, ezu says what each place answered; set `schema` then.

## Schema cache

Specs fetched from a URL are cached in `~/.cache/ezu/schemas/` (`$XDG_CACHE_HOME/ezu/schemas/` when set) for an hour. `--reload` fetches the spec again, and `--cache-ttl` or a profile's `cache-ttl` change how long it stays cached.
