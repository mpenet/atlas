# Atlas

<img  width="225" height="225" src="https://github.com/user-attachments/assets/4e4d83d3-4546-4af7-b8c7-cafa9bc3593b" />

OpenAPI 3.x toolbox.

- **Standalone CLI** — similar to Restish, with profiles, OAuth 2.0 (authorization code, client credentials, device flow), mTLS, response selection, and shell completion.
- **Fennel/Lua library** — point it at any schema (local file, URL, or parsed table) and get back a callable client.


## Documentation

- [Library (Fennel/Lua)](doc/library.md)
- [CLI](doc/cli.md)

## Install

### CLI — option 1: standalone binary (recommended)

No Lua runtime required. Download the binary for your platform from the [releases page](https://github.com/mpenet/atlas/releases), then:

```sh
install -m 755 atlas-bin /usr/local/bin/atlas
```

### CLI — option 2: build from source

```sh
make deps     # install luarocks dependencies
make install  # compile Fennel → Lua and install bin/atlas to /usr/local/bin
```

### Lua library

```sh
luarocks install atlas-oai
```

## Quick examples

```sh
# CLI
atlas https://petstore3.swagger.io/api/v3/openapi.json --list
atlas https://petstore3.swagger.io/api/v3/openapi.json get-pet-by-id 42
atlas myapi find-pets-by-status --query.status=available --select=.pets[].{id,name}
```

```fennel
;; library
(local atlas (require :atlas))
(local c (atlas.client "https://petstore3.swagger.io/api/v3/openapi.json"))
(c.get-pet-by-id 42)
(c.add-pet {:name "Rex" :status "available"})
```



## Building from source

```sh
make deps     # lunajson, luasocket, luasec, fennel, busted
make build    # compile Fennel → Lua
make test     # run test suite
make install  # install bin/atlas to /usr/local/bin
make binary   # build standalone binary → bin/atlas-bin
```

`make binary` requires `fennel`, `lua`, `openssl`, and `pkg-config`. It statically links Lua, luasocket, luasec, and OpenSSL — the resulting binary has no runtime dependencies.

## License

Copyright © 2026 Max Penet
Distributed under the Mozilla Public License Version 2.0
