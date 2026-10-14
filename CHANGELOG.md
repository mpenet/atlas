# Changelog

All notable changes to atlas. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions follow [Semantic Versioning](https://semver.org/).

## [1.0.0-beta1] - unreleased

### Security

- **TLS certificates are now verified.** Up to and including 1.0.0-alpha14, HTTPS requests did not verify the server's certificate or host name (luasec's default), so credentials sent by atlas — bearer tokens, API keys, Basic credentials, OAuth client secrets and refresh tokens — could be intercepted by anyone able to sit between atlas and the API. Upgrade, and consider rotating credentials used over untrusted networks. Verification uses the system CA bundle (`SSL_CERT_FILE`, the usual bundle locations, `SSL_CERT_DIR`) and fails closed when none is found; `--ssl.verify=none` or a profile's `"insecure": true` opt out.
- Redirects are followed by atlas itself: GET and HEAD only, at most 5, never from `https` to `http`, and credential headers are dropped when the origin changes.
- Header names and values containing CR, LF or NUL are rejected.
- `-v` and `--dry-run` redact secret query parameters; `az` sends credentials to source schemas only after a 401/403.
- external-tool signing and query api-key auth no longer modify the caller's request table.

### Added

- HTTP goes through libcurl: proxies from `https_proxy`/`http_proxy`/`all_proxy`/`no_proxy`, connection reuse, transparent gzip, per-request timeouts.
- `atlas --version`, also reporting the libcurl/OpenSSL build; `atlas.version` in the library.
- `atlas profile import-restish [FILE] [--dry-run]` imports Restish configs (v1 `apis.json`, v2 `restish.json`) as profiles.
- Profiles take `query` (parameters on every request) and `tls.ca_cert`.
- `az WORKFLOW --help` documents a workflow's inputs and steps.
- `--servers`, `--server-index` and `--server.NAME=VAL` to list and choose servers; `atlas.servers` in the library.
- Short field prefixes `--q.`, `--h.`, `--b.`, `--i.`.
- Request checks before sending: missing required parameters and invalid JSON bodies are errors, undeclared query names warn; `--no-validate` sends anyway.
- Shell completion of operations, parameters, body fields, enum values, server variables, Arazzo contexts, workflows and inputs.
- Operations without `operationId` are available under a name made of their method and path (`GET /pets/{petId}` → `get-pets-pet-id`); every operation exposes `:name`.
- `atlas.parse-schema` parses fetched schema text, rejecting documents that are not a mapping.
- Release binaries for macOS x86_64 and Linux arm64, a `SHA256SUMS` file and build provenance attestations.

### Changed

- **Breaking (library):** operations take a request table, `op.invoke {:path :query :headers :body :timeout}`; positional calls remain a shorthand.
- **Breaking (library):** `atlas.load-schema` and the `:load-schema` client option take `{:ssl :headers}` instead of positional arguments.
- **Breaking (library):** the operation field `:has-body?` is now `:has-body`; `:n-path` is gone (use `(length op.path-params)`).
- **Breaking:** Arazzo runs fail when a source description cannot be loaded, and a plain `operationId` defined by several sources is an error; qualify it as `$sourceDescriptions.NAME.ID`.
- The `ssl` options are `cafile`, `capath`, `certificate`, `key` and `verify`; other luasec options are no longer used.
- The binaries link OpenSSL, libyaml, zlib and libcurl statically; the Linux binary no longer needs libssl or libyaml installed.
- YAML is read with YAML 1.2 core schema semantics; mapping keys keep their source text.
- `$ref` resolution handles JSON Pointer escapes, references into other files and URLs, and path items; an unresolved reference is an error.
- Authentication happens only when a request is sent, never for `--help`, `--list`, `--servers` or `--dry-run`.

### Fixed

- Base URLs ending in `/` no longer produce `//` in request paths.
- A schema URL answering with an HTML page is reported as such instead of being read as a file path.
- Arazzo sub-workflow steps honour success criteria, actions and outputs; `dependsOn` runs first; cycles are detected.
- Many more; see the commit history.

## [1.0.0-alpha14] - 2026-07-06

Earlier releases are described on the [releases page](https://github.com/mpenet/atlas/releases).

[1.0.0-beta1]: https://github.com/mpenet/atlas/compare/v1.0.0-alpha14...v1.0.0-beta1
[1.0.0-alpha14]: https://github.com/mpenet/atlas/releases/tag/v1.0.0-alpha14
