# Changelog

All notable changes to atlas. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions follow [Semantic Versioning](https://semver.org/).

## [1.0.0-beta1] - unreleased

### Security

- **TLS certificates are now verified.** Up to and including 1.0.0-alpha14, HTTPS requests did not verify the server's certificate or host name (luasec's default), so credentials sent by atlas — bearer tokens, API keys, Basic credentials, OAuth client secrets and refresh tokens — could be intercepted by anyone able to sit between atlas and the API. Upgrade, and consider rotating credentials used over untrusted networks. Verification uses the system CA bundle (`SSL_CERT_FILE`, the usual bundle locations, `SSL_CERT_DIR`) and fails closed when none is found; `--ssl.verify=none` or a profile's `"insecure": true` opt out.
- Redirects are followed by atlas itself: GET and HEAD only, at most 5, never from `https` to `http`, and credential headers are dropped when the origin changes.
- Header names and values containing CR, LF or NUL are rejected.
- `-v` and `--dry-run` redact secret query parameters; `az` sends credentials to source schemas only after a 401/403.
- external-tool signing and query api-key auth no longer modify the caller's request table.
- Same-origin checks for redirects and pagination parse URLs as libcurl does: a crafted `Location` or `Link` such as `https://evil.example?@api.example.com/` was taken for the API's own origin, so credentials followed it to another host.
- Documents named by a spec's external `$ref`s are fetched without the profile's headers or credentials unless they are on the spec's own origin.
- The bash completion script treats the candidates it gets (operation names, enum values from the spec…) as data: `compgen -W` expanded `$(...)` in them, so a spec could run commands when completing.
- On a redirect to another origin, the headers authentication added are dropped whatever their name, and logs and dry runs redact them and a query API key whatever their name; user info in URLs is redacted too.
- The schema cache directory is private to the user (0700).
- A URL whose host part holds a backslash matches no origin, so credentials never follow it (libcurl reads `http://a\@b/` as host `b`); retried schema fetches and next-page requests keep the marking of credential headers, so a later cross-origin redirect drops them; `$ref` errors redact the document's URL.

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
- `atlas.json` (`decode`, `encode`, `array`, `array?`): JSON that keeps empty arrays apart from empty objects; use `json.array` to send an empty array from a body built in Lua.
- `atlas.parse-schema` parses fetched schema text, rejecting documents that are not a mapping.
- Release binaries for macOS x86_64 and Linux arm64, a `SHA256SUMS` file and build provenance attestations.

### Changed

- **Breaking (library):** operations take a request table, `op.invoke {:path :query :headers :body :timeout}`; positional calls remain a shorthand.
- **Breaking (library):** `atlas.load-schema` and the `:load-schema` client option take `{:ssl :headers}` instead of positional arguments.
- **Breaking (library):** the operation field `:has-body?` is now `:has-body`; `:n-path` is gone (use `(length op.path-params)`).
- **Breaking (library):** every `$ref` to the same place resolves to the same table, so recursive schemas are cyclic tables (`node.properties.next` is `node`) instead of being cut to `{}`. Code that walks `op.spec` or `op.body-schema` must not assume a tree, and should not serialise them as is. This makes resolution linear for any spec (it was exponential on heavily recursive ones such as Stripe's) and lets validation check recursive data at every depth.
- **Breaking (library):** JSON `null` is `json.null` (from `atlas.json`) in decoded response bodies, both in arrays and as object members, so a body shows and re-encodes as received; it used to drop members and corrupt arrays (`[1,null,3]` came out as `{"1":1,"3":3}`). Code testing `(= nil body.x)` for a null `x` must test `(= json.null body.x)`.
- **Breaking:** an option that doesn't apply to the command is an error: `op --profile p` used to send the request without the profile, `az --select` was ignored.
- **Breaking:** Arazzo runs fail when a source description cannot be loaded, and a plain `operationId` defined by several sources is an error; qualify it as `$sourceDescriptions.NAME.ID`.
- Operation names are lowercase words joined by dashes whatever the operationId's style: `projects/list-cards`, `get_folders_id#get_shared_link` and `bookmarks-(-deprecated)` become `projects-list-cards`, `get-folders-id-get-shared-link` and `bookmarks-deprecated`. When two operationIds yield the same name, the first by path keeps it and the others are named after their method and path, the same way on every run.
- Query parameters are serialized in their declared `style` and `explode` (`form`, `spaceDelimited`, `pipeDelimited`, `deepObject`); array path parameters use the `simple` style.
- Arazzo: string comparisons in conditions are case-insensitive and `''` escapes a quote, as the spec says; a backslash is now an ordinary character. A misspelled expression (`$statuscode`) is an error rather than `null`, and payload text that merely starts with `$` is kept as is.
- Arazzo: a request that fails in transport is a step failure, so `onFailure` and `retry` handle it; `retry` runs the step named by `stepId` first; a response's `Retry-After` overrules `retryAfter`; `requestBody.contentType` and `replacements` are supported; `$request.query.NAME` and `$request.path.NAME` work.
- `--output` and `--arazzo-output` reject unknown values.
- Building a client is linear in the size of the spec: Stripe's went from not finishing to 0.07 s, Kubernetes' from 1 s to 0.01 s.
- The `ssl` options are `cafile`, `capath`, `certificate`, `key` and `verify`; other luasec options are no longer used.
- The macOS binaries run on macOS 12 or later: Lua, OpenSSL (3.5 LTS) and libyaml are built from pinned sources for that target, where the previous ones only started on the macOS version of the machine that built them.
- The binaries link OpenSSL, libyaml, zlib and libcurl statically. The Linux binaries are fully static, built against musl: they run on any distribution (the previous ones needed glibc 2.34 or later, libssl 3 and libyaml).
- YAML is read with YAML 1.2 core schema semantics; mapping keys keep their source text.
- `$ref` resolution handles JSON Pointer escapes, references into other files and URLs, and path items; an unresolved reference is an error.
- Authentication happens only when a request is sent, never for `--help`, `--list`, `--servers` or `--dry-run`.

### Fixed

- Base URLs ending in `/` no longer produce `//` in request paths.
- A schema URL answering with an HTML page is reported as such instead of being read as a file path.
- Empty JSON arrays came out as `{}`: printed that way, and re-sent that way, so `-d '{"tags":[]}'` sent `{"tags":{}}`. Arrays now stay arrays, empty or not, through decoding, printing, YAML, validation and encoding; validation also stopped treating an empty object as an array.
- JSON request bodies are encoded exactly and the same way every time: integers above 2^53 (IDs) are no longer rounded, floats are written in their shortest exact form (`0.1`, not `0.10000000000000001`), and object keys are sorted, so `--dry-run` and `--curl` output is reproducible.
- Arazzo: workflow inputs take the `default` their schema declares when not given (help already showed it).
- Arazzo: `$steps.ID.outputs.pet.name` (and the same for `$inputs` and `$workflows`) silently meant `outputs.pet`; names may contain dots, so it now names the output `pet.name`, and when there is none but there is a `pet`, the error points to the JSON pointer form `$steps.ID.outputs.pet#/name`.
- `atlas profile list` shows the schema a profile inherits through `extends`, and keeps listing past a profile whose `extends` is broken.
- Completion resolves `extends`; a child profile's header overrides its parent's whatever the case; `false` in a profile overrides `true` in the configuration.
- Arrays inside Arazzo payloads and `--select` results stay arrays when empty.
- A `$ref`'d path item whose schemas are recursive no longer overflows the stack.
- Validation accepts OpenAPI 3.1 boolean schemas, applies `nullable` only with a `type`, and tells empty arrays from empty objects.
- The request content type is chosen the same way on every run (JSON first), and no `Content-Type` is sent without a body.
- Help shows 3.1 type arrays (`string | null`); YAML output quotes control characters and writes infinities as `.inf`.
- Number fields accept only JSON numbers (no hex), and an integer too large for 64 bits stays text instead of being rounded.
- `--server-index=0`, `--b.=1` and similar mistakes give clear errors instead of crashing; error responses with a text body are printed as they are.
- Colours are only used when stdout is a terminal, and never when `NO_COLOR` is set: piping `atlas` into `jq` or a file gave escape codes.
- YAML documents could be misread or rejected at random ("control characters are not allowed") when the garbage collector freed the text while libyaml was still reading it.
- An operationId defined twice (Cloudflare has one) no longer hides one of the two operations.
- `--output yaml` quotes a key named `<<` instead of writing a merge key.
- `--select` no longer crashes when picking fields (`{a,b}`) from a scalar or from an array mixing objects and scalars.
- Help lists body properties and responses in a stable order.
- Arazzo sub-workflow steps honour success criteria, actions and outputs; `dependsOn` runs first; cycles are detected.
- Many more; see the commit history.

## [1.0.0-alpha14] - 2026-07-06

Earlier releases are described on the [releases page](https://github.com/mpenet/atlas/releases).

[1.0.0-beta1]: https://github.com/mpenet/atlas/compare/v1.0.0-alpha14...v1.0.0-beta1
[1.0.0-alpha14]: https://github.com/mpenet/atlas/releases/tag/v1.0.0-alpha14
