# Development

[Documentation](README.md) › Development

## Building and testing

```sh
# lunajson, luasocket, lyaml, fennel, busted
make deps
# compile Fennel to Lua, and the libcurl binding
make build
# the specs, the global and manifest checks, and the documentation's links
make test
# the standalone binary, in bin/atlas-bin
make binary
# build the binary and install it to /usr/local/bin (PREFIX=... to change)
make install
```

`make build` and `make test` also compile the libcurl binding, which needs the libcurl headers (`curl-config` on `PATH`). `make fmt` formats the Fennel sources with fnlfmt, and `make fmt-check` checks them.

## The standalone binary

`make binary` requires a C compiler, `fennel`, `lua`, `luarocks`, `libyaml`, `pkg-config`, `unzip` and `curl`. It downloads the mbedTLS and libcurl sources (checked against pinned checksums) and statically links Lua, luasocket, libcurl, mbedTLS, lyaml and libyaml: the binary is less than 2 MB and depends only on system libraries. `make check-binary` runs it with Lua's module paths emptied and checks what it links.

`make binary STATIC_LDFLAGS=-static` links the system libraries too; the Linux release binaries are built that way against musl (see the `Dockerfile`), so they run on any distribution. `make binary DEPS_FROM_SOURCE=1` also builds Lua and libyaml from pinned sources for `MACOSX_DEPLOYMENT_TARGET` (default 12.0), which the macOS release binaries use.

## Real-world specs

```sh
make corpus
```

downloads the public specs listed in `test/corpus/specs.txt` (GitHub, Stripe, Cloudflare, Exoscale…) and checks that every operation builds, renders its help, passes the request checks and makes a valid MCP tool.

## Generated code

`fnl/atlas/cli/width.fnl`, the display width of text in a terminal, is generated from Unicode's data files by `tools/unicode-width.lua`:

```sh
make unicode-width UNICODE_VERSION=17.0.0
```

## Releasing

1. Set the version in `fnl/atlas.fnl` (`:version`).
2. Turn `unreleased` into today's date in that version's `CHANGELOG.md` section.
3. Commit, tag `vVERSION` and push the tag.

The release workflow refuses a tag that disagrees with either, builds and checks the four binaries (including TLS verification over the network), and publishes them with `SHA256SUMS`, provenance attestations and the changelog section as release notes, then updates the Homebrew formula in `mpenet/homebrew-tap`. Versions with a `-` suffix are marked as prereleases.
