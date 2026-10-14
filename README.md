# Atlas

<img  width="225" height="225" src="https://github.com/user-attachments/assets/4e4d83d3-4546-4af7-b8c7-cafa9bc3593b" />

A command line for any HTTP API that publishes an [OpenAPI 3](https://spec.openapis.org/oas/latest.html) description.

Point `atlas` at a spec and every operation becomes a command, with its own help, shell completion, and checks that catch mistakes before anything is sent. No code generation: the spec is read when you run the command.

- **Every operation, at your fingertips.** Path parameters as arguments, `--q.` / `--h.` / `--b.` for query, headers and body fields, typed from the spec.
- **Output you can use.** Pretty JSON or YAML, `--select` to pick what you need, exit codes that tell 4xx from 5xx.
- **Profiles and authentication.** Bearer, Basic, API keys, OAuth 2.0 (authorization code with PKCE, client credentials, device flow), external signing tools, mutual TLS.
- **Workflows.** Run multi-step [Arazzo](https://spec.openapis.org/arazzo/latest.html) workflows: chain calls, poll until a job finishes, branch on results.
- **Safe by default.** Verified TLS, credentials never follow a redirect to another host, secrets redacted from logs and `--dry-run`.
- **One static binary** for macOS and Linux. Also a [Fennel/Lua library](doc/library.md).

## Install

Download the binary for your platform from the [releases page](https://github.com/mpenet/atlas/releases) (`atlas-macos-arm64`, `atlas-macos-x86_64`, `atlas-linux-x86_64` or `atlas-linux-arm64`), then:

```sh
install -m 755 atlas-macos-arm64 /usr/local/bin/atlas
atlas --version
```

Every release carries `SHA256SUMS` and a [build provenance attestation](https://docs.github.com/en/actions/security-for-github-actions/using-artifact-attestations):

```sh
shasum -a 256 -c SHA256SUMS --ignore-missing
gh attestation verify atlas-macos-arm64 --repo mpenet/atlas
```

Other ways to install (from source, with luarocks) are in the [CLI reference](doc/cli.md#installation).

## A five-minute tour

The tour uses the public [Swagger Petstore](https://petstore3.swagger.io). It is a shared demo, so the pets you see will differ.

```sh
export PETSTORE=https://petstore3.swagger.io/api/v3/openapi.json
```

**List what the API can do:**

```console
$ atlas op $PETSTORE --list
add-pet                       Add a new pet to the store.
create-user                   Create user.
delete-pet                    Deletes a pet.
find-pets-by-status           Finds Pets by status.
get-pet-by-id                 Find pet by ID.
...
```

Operation names come from the spec's `operationId`s (`getPetById` → `get-pet-by-id`).

**Read an operation's help:**

```console
$ atlas op $PETSTORE get-pet-by-id --help
GET /pet/{petId}

Find pet by ID.
Returns a single pet.

Usage: atlas op <profile-or-schema> get-pet-by-id <petId>

Path params:
  petId            integer [required] — ID of pet to return

Responses:
  200    successful operation
  400    Invalid ID supplied
  404    Pet not found
  default Unexpected error
```

**Call it.** Path parameters are positional:

```console
$ atlas op $PETSTORE get-pet-by-id 7
{
  "category": {
    "id": 4,
    "name": "Lions"
  },
  "id": 7,
  "name": "Lion 1",
  "photoUrls": [
    "url1",
    "url2"
  ],
  "status": "available",
  "tags": [ ... ]
}
```

**Query parameters, selection and formats:**

```console
$ atlas op $PETSTORE find-pets-by-status --q.status=sold --select '[].{id,name}' --output yaml
- id: 100001
  name: doggie-updated
- id: 54
  name: Roki
...
```

`--select` takes `.field`, `[N]`, `[]` (every element) and `{a,b}` (pick fields). `--output` is `json` (the default), `yaml`, `raw`, `status` or `headers`. Colours are used on a terminal only.

**Send a body.** Fields are typed from the request schema; `-d` takes JSON or YAML, inline, from a file (`@pet.json`) or from stdin (`@-`). Check what would be sent with `--dry-run`, or get a `curl` command with `--curl`:

```console
$ atlas op $PETSTORE add-pet --b.name=Rex --b.status=available --b.photoUrls='["rex.jpg"]' --dry-run
POST https://petstore3.swagger.io/api/v3/pet
accept: application/json, application/xml
content-type: application/json

{"name":"Rex","photoUrls":["rex.jpg"],"status":"available"}
```

atlas checks the request against the spec first, and sends nothing when something is missing:

```console
$ atlas op $PETSTORE add-pet --b.name=Rex
body.photoUrls: required
(use --no-validate to send anyway)
```

**Errors** go to stderr, and the exit code tells them apart: `4` for a 4xx response, `5` for a 5xx, `1` for anything else that went wrong.

```console
$ atlas op $PETSTORE get-pet-by-id 999999999
HTTP 404  0.495s
Pet not found
$ echo $?
4
```

`-v` shows the request and the response headers on stderr, with credentials redacted.

## Profiles and authentication

Name your APIs in `~/.config/atlas/config.json`, with their settings and credentials:

```json
{
  "profiles": {
    "petstore": {
      "schema": "https://petstore3.swagger.io/api/v3/openapi.json",
      "auth": {"name": "bearer", "params": {"token": "env:PETSTORE_TOKEN"}}
    },
    "petstore-yaml": {
      "extends": "petstore",
      "output": "yaml"
    }
  }
}
```

Then use the profile's name instead of the spec's URL:

```console
$ atlas op petstore-yaml get-pet-by-id 7 --select '{name,status}'
name: Lion 1
status: available
```

`env:NAME` reads a secret from the environment. Authentication runs only when a request is actually sent, never for `--help`, `--list` or completion. OAuth tokens are cached and refreshed. See the [guide](doc/guide.md) for every auth method, environments, TLS client certificates and proxies.

## Workflows

An [Arazzo](https://spec.openapis.org/arazzo/latest.html) document describes a sequence of calls. [`doc/examples/petstore.arazzo.yaml`](doc/examples/petstore.arazzo.yaml) finds a pet by status, then fetches it:

```console
$ atlas az doc/examples/petstore.arazzo.yaml
first-pet  Find the first pet with a given status and fetch its details.

$ atlas az doc/examples/petstore.arazzo.yaml first-pet -i status=sold --output yaml
name: doggie-updated
status: sold
```

`--arazzo-output progress` shows each step as it runs. Workflows can poll with `goto` and `retry`, branch on success criteria and call other workflows; they use your profiles for authentication. See [Arazzo workflows](doc/arazzo.md).

## Shell completion

```sh
# fish
atlas completion fish > ~/.config/fish/completions/atlas.fish

# bash, in ~/.bashrc
eval "$(atlas completion bash)"

# zsh, in ~/.zshrc after compinit
eval "$(atlas completion zsh)"
```

Completion knows profiles, operations, their parameters and body fields, allowed values, server variables, workflows and their inputs.

## Coming from Restish

`atlas profile import-restish` turns your Restish configuration into atlas profiles. `--dry-run` shows what it would add. See [Moving from Restish](doc/guide.md#moving-from-restish).

## Documentation

- [Guide](doc/guide.md): profiles, authentication, environments, scripting, debugging.
- [CLI reference](doc/cli.md): every command, option and configuration key.
- [Arazzo workflows](doc/arazzo.md): running and writing workflows.
- [Library](doc/library.md): using atlas from Fennel or Lua.
- [Changelog](CHANGELOG.md).

## Using atlas as a library

The same engine is a Fennel/Lua library: point it at a spec and call operations as functions.

```fennel
(local atlas (require :atlas))
(local petstore (atlas.client "https://petstore3.swagger.io/api/v3/openapi.json"))

(petstore.get-pet-by-id.invoke {:path {:petId 7}})
;; => {:status 200 :headers {...} :body {:id 7 :name "Lion 1" ...}}
```

Install it with `luarocks install atlas-oai`. See the [library documentation](doc/library.md).

## Building from source

```sh
# lunajson, luasocket, lyaml, fennel, busted
make deps
# compile Fennel to Lua, and the libcurl binding
make build
make test
# the standalone binary, in bin/atlas-bin
make binary
# build the binary and install it to /usr/local/bin (PREFIX=... to change)
make install
# check real-world specs (downloads them)
make corpus
```

`make build` and `make test` also compile the libcurl binding, which needs the libcurl headers (`curl-config` on `PATH`). `make binary` requires a C compiler, `fennel`, `lua`, `luarocks`, `openssl`, `libyaml`, `pkg-config`, `unzip` and `curl`; it downloads the libcurl sources (checked against a pinned checksum) and statically links Lua, luasocket, libcurl, lyaml, OpenSSL and libyaml — the resulting binary depends only on system libraries. `make binary STATIC_LDFLAGS=-static` links those too; the Linux release binaries are built that way against musl (see the `Dockerfile`), so they run on any distribution. `make binary DEPS_FROM_SOURCE=1` builds Lua, OpenSSL and libyaml from pinned sources for `MACOSX_DEPLOYMENT_TARGET` (default 12.0), which the macOS release binaries use.

## Releasing

1. Set the version in `fnl/atlas.fnl` (`:version`).
2. Turn `unreleased` into today's date in that version's `CHANGELOG.md` section.
3. Commit, tag `vVERSION` and push the tag.

The release workflow refuses a tag that disagrees with either, builds and checks the four binaries (including TLS verification over the network), and publishes them with `SHA256SUMS`, provenance attestations and the changelog section as release notes. Versions with a `-` suffix are marked as prereleases.

## License

Copyright © 2026 Max Penet
Distributed under the Mozilla Public License Version 2.0
