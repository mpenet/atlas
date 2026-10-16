# Authentication

[Documentation](README.md) › Authentication

A profile's `auth` names a method and its parameters. Any parameter written `env:NAME` is read from the environment variable `NAME` when needed.

Authentication runs only when a request is sent: never for `--help`, `--list`, `--servers`, `--dry-run` or completion, nor when the request's own headers already provide what it would add. A spec fetched from a URL is requested without credentials first, and with them only if the server answers 401 or 403; when the profile's `base-url` is on another origin than the spec, the spec gets neither credentials nor the profile's `headers`. Credentials are computed once per command, reused by retries and pagination, and a header given explicitly (with `--h.` or in the profile's `headers`) wins over the one authentication adds.

## `bearer`

```json
{"name": "bearer", "params": {"token": "env:API_TOKEN"}}
```

Sends `Authorization: Bearer <token>`.

## `basic`

```json
{"name": "basic", "params": {"username": "me", "password": "env:API_PASSWORD"}}
```

## `api-key`

```json
{"name": "api-key", "params": {"name": "X-API-Key", "in": "header", "value": "env:API_KEY"}}
```

With `"in": "query"`, the key is sent as a query parameter instead, and with `"in": "cookie"` as a cookie; `header` is the default.

## `oauth-authorization-code`

Opens the browser, receives the code on a local callback server, and exchanges it for a token, with PKCE (S256).

| Param | Description |
|-------|-------------|
| `authorize_url` | The provider's authorization endpoint |
| `token_url` | The provider's token endpoint |
| `client_id` | Client id |
| `client_secret` | Client secret; leave it out for a public client |
| `scope` | Scopes, space-separated |
| `redirect_host`, `redirect_port`, `redirect_path` | The callback address, which must match a redirect URI registered with the provider (default `127.0.0.1`, a random port, `/callback`) |

## `oauth-client-credentials`

For services and CI: `token_url`, `client_id`, `client_secret`, and optionally `scope` and `audience`.

## `oauth-device-authorization`

For machines without a browser: prints a code and a URL on stderr, then waits while you approve on another device. Params: `device_authorization_url`, `token_url`, `client_id`, and optionally `client_secret` and `scope`.

OAuth tokens are cached in `~/.cache/atlas/tokens/<profile>.json` (mode 0600; `$XDG_CACHE_HOME` replaces `~/.cache` when set) and refreshed when they expire. `atlas auth <profile>` signs in again; `atlas auth <profile> --logout` deletes the token.

## `external-tool`

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
