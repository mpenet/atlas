# atlas documentation

atlas calls any HTTP API that publishes an [OpenAPI 3](https://spec.openapis.org/oas/latest.html) description: each operation becomes a command. The [README](../README.md) has a five-minute tour.

## Getting started

- [Installing atlas](install.md): Homebrew, release binaries (less than 2 MB, no runtime dependencies), from source, with luarocks; shell completion.
- [Guide](guide.md): adding an API, credentials, several environments, scripting, debugging a request, corporate networks.

## Reference

- [Commands](commands.md): `op`, `az`, `http`, `mcp`, `profile`, `auth` and `completion`, every option, operation names and exit codes.
- [Requests](requests.md): path and query parameters, headers, bodies, the checks made before sending, retries, pagination, dry runs.
- [Output](output.md): output formats, tables and CSV, `--select`, streamed responses, verbose output.
- [Configuration](configuration.md): the configuration file, profiles, servers, finding a spec from its API, the schema cache.
- [Authentication](authentication.md): bearer, basic, API keys, OAuth 2.0 flows, external tools and request signing.
- [TLS and proxies](tls.md): certificate verification, client certificates, CA bundles, proxies.

## Beyond requests

- [Arazzo workflows](arazzo.md): running and writing multi-step workflows.
- [MCP server](mcp.md): serving an API's operations, and workflows, to AI agents.
- [Moving from Restish](restish.md): importing a Restish configuration, and how the two compare.
- [Library](library.md): using atlas from Fennel or Lua.

## Project

- [Development](development.md): building, testing, the spec corpus, releasing.
- [Changelog](../CHANGELOG.md).
