# Installing atlas

[Documentation](README.md) › Installing atlas

atlas is one static binary of less than 2 MB for macOS and Linux, with no runtime dependencies. Install it with Homebrew, download it, or build it; the [library](library.md) installs with luarocks.

## Homebrew

```sh
brew install mpenet/tap/atlas
```

On macOS or Linux. The full name is needed: Homebrew's own `atlas` is another tool. The formula installs the release binary below, plus bash, zsh and fish completion; `brew upgrade` follows new releases.

## Standalone binary

Download the binary for your platform from the [releases page](https://github.com/mpenet/atlas/releases) (`atlas-macos-arm64`, `atlas-macos-x86_64`, `atlas-linux-x86_64` or `atlas-linux-arm64`), then install it:

```sh
install -m 755 atlas-macos-arm64 /usr/local/bin/atlas
```

Each release lists the files' SHA-256 sums in `SHA256SUMS` and carries a [build provenance attestation](https://docs.github.com/en/actions/security-for-github-actions/using-artifact-attestations) proving the binary was built by this repository's release workflow:

```sh
shasum -a 256 -c SHA256SUMS --ignore-missing
gh attestation verify atlas-macos-arm64 --repo mpenet/atlas
```

The binary embeds Lua, luasocket, libcurl, mbedTLS and libyaml. The macOS binaries run on macOS 12 or later; the Linux binaries are fully static (built against musl), so they run on any distribution, old or new. HTTPS needs the system's CA certificates (the `ca-certificates` package on minimal Linux images); see [TLS and proxies](tls.md).

## From source

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

## With luarocks

Installs `atlas` as a Lua script, together with the [library](library.md):

```sh
luarocks install atlas-oai
```

luarocks installs the Lua dependencies (lunajson, luasocket, lyaml) and compiles the libcurl binding, which needs the libcurl headers (`libcurl4-openssl-dev` on Debian and Ubuntu, `libcurl-devel` on Fedora; macOS ships them) and the libyaml headers. From a checkout: `luarocks make atlas-oai-dev-1.rockspec`.

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
