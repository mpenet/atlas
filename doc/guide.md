# Guide

[Documentation](README.md) › Guide

How to set atlas up for the APIs you use, and how to use it day to day. The [README](../README.md) has a quick tour; the [documentation index](README.md) lists the reference pages.

- [Adding an API](#adding-an-api)
- [Credentials](#credentials)
- [Several environments](#several-environments)
- [Scripting](#scripting)
- [Debugging a request](#debugging-a-request)
- [Corporate networks: proxies, CAs, client certificates](#corporate-networks)

## Adding an API

All atlas needs is the API's OpenAPI description, a URL or a file:

```sh
atlas op https://api.example.com/openapi.json --list
atlas op ./openapi.yaml --list
```

Once you use an API regularly, give it a name in `~/.config/atlas/config.json`:

```json
{
  "profiles": {
    "example": {
      "schema": "https://api.example.com/openapi.json"
    }
  }
}
```

```sh
atlas op example --list
```

**Where requests go.** atlas sends requests to the first server the spec lists. When it lists several (production and sandbox, regions…), `--servers` shows them:

```sh
atlas op example --servers
```

Pick one with `server-index`, set its variables with `server`, or ignore the spec's servers with `base-url`:

```json
"example": {
  "schema": "https://api.example.com/openapi.json",
  "server-index": 2,
  "server": {"region": "eu"}
}
```

A spec whose server URL is relative (`/api/v3`) resolves against the URL the spec was fetched from. A spec read from a file with a relative server needs `base-url`.

**Things every request needs.** `headers` and `query` are added to every request, like an API version:

```json
"example": {
  "schema": "https://api.example.com/openapi.json",
  "headers": {"Accept-Language": "en"},
  "query": {"api-version": "2024-10-01"}
}
```

The spec is cached for an hour after it's fetched; `--reload` fetches it again.

## Credentials

Credentials go in the profile's `auth`. Keep secrets out of the file with `env:NAME`, which reads the environment variable `NAME` when the credential is needed:

```json
"example": {
  "schema": "https://api.example.com/openapi.json",
  "auth": {"name": "bearer", "params": {"token": "env:EXAMPLE_TOKEN"}}
}
```

Check what will be sent with `atlas auth`:

```console
$ atlas auth example
authorization: Bearer s3cr3t
```

The methods:

- **A token** (`bearer`), **a username and password** (`basic`), or **an API key** in a header, the query string or a cookie (`api-key`).
- **OAuth 2.0, interactive** (`oauth-authorization-code`): the first request opens your browser to sign in, then the token is cached and refreshed. Register `http://127.0.0.1:PORT/callback` with the provider and set `redirect_port` to match.
- **OAuth 2.0, for services and CI** (`oauth-client-credentials`): a client id and secret, no browser.
- **OAuth 2.0, without a browser** (`oauth-device-authorization`): atlas prints a code and a URL; approve on any device.
- **Your own tool** (`external-tool`): a command that prints a token, or signs each request (AWS-style signatures, internal SSO helpers…).

The [reference](authentication.md) has each method's parameters.

Authentication happens only when a request goes out, so `--help`, `--list` and completion never open a browser. `atlas auth example` signs in again; `atlas auth example --logout` forgets the cached token.

## Several environments

`extends` derives a profile from another, overriding what differs. Headers are merged; everything else is replaced:

```json
{
  "profiles": {
    "example": {
      "schema": "https://api.example.com/openapi.json",
      "auth": {"name": "oauth-client-credentials", "params": {
        "token_url": "https://auth.example.com/token",
        "client_id": "env:EXAMPLE_CLIENT_ID",
        "client_secret": "env:EXAMPLE_CLIENT_SECRET"
      }}
    },
    "example-staging": {
      "extends": "example",
      "base-url": "https://staging.api.example.com"
    }
  }
}
```

`atlas profile show example-staging` shows the result. Tokens are cached per profile, so production and staging sessions don't mix.

## Scripting

atlas is built to sit in a pipeline:

- **Exit codes** tell outcomes apart: `0` success, `4` for a 4xx response, `5` for a 5xx, `1` for anything else (bad arguments, network errors, failed checks). Error bodies go to stderr, so stdout only ever holds a successful response.
- **`--select`** picks what you need, so you rarely need `jq`; `--output raw` prints a selected string without quotes.
- **No colours in pipes:** output is coloured only on a terminal, and never with `NO_COLOR` set.
- **Bodies from files or stdin** with `-d @file` and `-d @-`.
- **Retries** (2 by default, for idempotent requests) wait as long as the server's `Retry-After` asks; `--retry=0` turns them off, `--timeout` bounds each request.
- **Pagination** following `Link: rel="next"` headers is automatic for arrays; `--no-paginate` gets the first page only.
- **`--ignore-status`** prints error responses on stdout and exits 0, when you want to inspect them.

```sh
#!/bin/sh
set -e
name=$(atlas op petstore get-pet-by-id 7 --select .name --output raw)
echo "pet 7 is $name"

code=0
atlas op petstore get-pet-by-id 999999999 >/dev/null 2>&1 || code=$?
if [ "$code" -eq 4 ]; then
  echo "no such pet"
fi
```

## Debugging a request

- **`--help`** on an operation shows what it takes: path parameters, query parameters with their types and allowed values, the body's properties, the responses.
- **`--dry-run`** prints the request that would be sent, without sending it or authenticating.
- **`--curl`** prints the same request as a `curl` command, credentials included, to share or replay.
- **`-v`** logs the request and the response headers on stderr, credentials redacted.
- **`--no-validate`** sends a request atlas thinks is wrong: specs are sometimes stricter than the API they describe.

```console
$ atlas op petstore get-pet-by-id 7 -v --select .name
> GET https://petstore3.swagger.io/api/v3/pet/7
> accept: application/json, application/xml
> authorization: Bearer <redacted>
HTTP 200  0.475s
content-type: application/json
...

"Lion 1"
```

## Corporate networks

**Proxies.** atlas uses the proxy named by `https_proxy` or `HTTPS_PROXY` for HTTPS, `http_proxy` (lower case only) for HTTP, or `all_proxy`/`ALL_PROXY`, and goes direct for the hosts in `no_proxy`/`NO_PROXY`.

**An internal CA.** atlas trusts the system's CA certificates. Point it at another bundle for every program with `SSL_CERT_FILE`, or for one profile:

```json
"internal": {
  "schema": "https://api.internal.example.com/openapi.json",
  "tls": {"ca_cert": "/etc/pki/internal-ca.pem"}
}
```

**Client certificates** (mutual TLS) go in the same block:

```json
"tls": {"cert": "/home/me/.pki/client.pem", "key": "/home/me/.pki/client.key"}
```

`"insecure": true` turns certificate checks off, for a test server with a self-signed certificate; never use it for real credentials.
