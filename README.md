# Atlas

<img  width="225" height="225" src="https://github.com/user-attachments/assets/4e4d83d3-4546-4af7-b8c7-cafa9bc3593b" />

OpenAPI 3.x toolbox.

- **Standalone CLI** — similar to Restish, with profiles, OAuth 2.0 (authorization code, client credentials, device flow), mTLS, response selection, and shell completion.
- **Arazzo workflow execution** — run multi-step API sequences from [Arazzo 1.0](https://spec.openapis.org/arazzo/latest.html) documents: runtime expressions, the simple condition language, `goto`/`retry`/`end` actions, reusable components, sub-workflows, polling loops, and profile-based auth. Regex criteria use Lua patterns; JSONPath/XPath criteria are not supported.
- **Coming from Restish?** `atlas profile import-restish` turns your Restish APIs into atlas profiles.
- **Fennel/Lua library** — point it at any schema (local file, URL, or parsed table) and get back a callable client.


## Documentation

- [Library (Fennel/Lua)](doc/library.md)
- [CLI](doc/cli.md)
- [Changelog](CHANGELOG.md)

## Install

### CLI — option 1: standalone binary (recommended)

No Lua runtime required. Download the binary for your platform from the [releases page](https://github.com/mpenet/atlas/releases) (`atlas-macos-arm64`, `atlas-macos-x86_64`, `atlas-linux-x86_64` or `atlas-linux-arm64`), then:

```sh
install -m 755 atlas-macos-arm64 /usr/local/bin/atlas
```

Each release lists the files' SHA-256 sums in `SHA256SUMS` and carries a [build provenance attestation](https://docs.github.com/en/actions/security-for-github-actions/using-artifact-attestations) proving the binary was built by this repository's release workflow:

```sh
shasum -a 256 -c SHA256SUMS --ignore-missing
gh attestation verify atlas-macos-arm64 --repo mpenet/atlas
```

### CLI — option 2: build from source

```sh
make deps     # install luarocks dependencies
make install  # build the standalone binary and install it to /usr/local/bin (PREFIX=... to change)
```

### Lua library

```sh
luarocks install atlas-oai
```

## Quick examples

```sh
# CLI
atlas op https://petstore3.swagger.io/api/v3/openapi.json --list
atlas op https://petstore3.swagger.io/api/v3/openapi.json get-pet-by-id 42
atlas op myapi find-pets-by-status --q.status=available --select=.pets[].{id,name}

# Arazzo — multi-step workflow
atlas az myapi create-and-wait \
  --b.name=myresource \
  --b.size=10 \
  -v
```

```fennel
;; library
(local atlas (require :atlas))
(local c (atlas.client "https://petstore3.swagger.io/api/v3/openapi.json"))
(c.get-pet-by-id.invoke {:path {:petId 42}})
(c.add-pet.invoke {:body {:name "Rex" :status "available"}})
```



## Building from source

```sh
make deps     # lunajson, luasocket, lyaml, fennel, busted
make build    # compile Fennel → Lua
make test     # run test suite
make install  # build standalone binary and install to /usr/local/bin (PREFIX=... to change)
make binary   # build standalone binary → bin/atlas-bin
```

`make build` and `make test` also compile the libcurl binding, which needs the libcurl headers (`curl-config` on `PATH`). `make binary` requires `fennel`, `lua`, `openssl`, `libyaml`, `pkg-config` and `curl`; it downloads the libcurl sources (checked against a pinned checksum) and statically links Lua, luasocket, libcurl, lyaml, OpenSSL and libyaml — the resulting binary depends only on system libraries (glibc on Linux).

## Releasing

1. Set the version in `fnl/atlas.fnl` (`:version`).
2. Turn `unreleased` into today's date in that version's `CHANGELOG.md` section.
3. Commit, tag `vVERSION` and push the tag.

The release workflow refuses a tag that disagrees with either, builds and checks the four binaries (including TLS verification over the network), and publishes them with `SHA256SUMS`, provenance attestations and the changelog section as release notes. Versions with a `-` suffix are marked as prereleases.

## License

Copyright © 2026 Max Penet
Distributed under the Mozilla Public License Version 2.0
