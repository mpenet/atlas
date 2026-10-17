# Linux release build: musl on Alpine, linked fully statically, so the binary
# runs on any Linux distribution, whatever its C library version.
FROM alpine:3.24 AS builder

RUN apk add --no-cache \
    lua5.4 lua5.4-dev build-base pkgconf unzip bzip2 wget curl ca-certificates bash \
    yaml-dev yaml-static zlib-dev zlib-static \
    curl-dev \
  && ln -s /usr/bin/lua5.4 /usr/local/bin/lua

# Alpine's luarocks targets other Lua versions: build it for 5.4
RUN wget -q https://luarocks.org/releases/luarocks-3.13.0.tar.gz \
  && tar xzf luarocks-3.13.0.tar.gz \
  && cd luarocks-3.13.0 \
  && ./configure --with-lua-version=5.4 --with-lua-bin=/usr/bin --lua-suffix=5.4 \
       --with-lua-include=/usr/include/lua5.4 \
  && make -j$(nproc) \
  && make install \
  && cd .. && rm -rf luarocks-3.13.0 luarocks-3.13.0.tar.gz

# the versions of the Makefile's deps, which THIRD-PARTY.md names
RUN luarocks install fennel 1.6.1 \
  && luarocks install lunajson 1.2.3 \
  && luarocks install luasocket 3.1.0 \
  && luarocks install lyaml 6.2.9 \
  && luarocks install busted

WORKDIR /src
COPY . .

RUN make test FENNEL=fennel LUA_INC=/usr/include/lua5.4

RUN LUA_PATH_EXTRA=$(luarocks path --lr-path 2>/dev/null) && \
    make binary FENNEL=fennel LUA_INC=/usr/include/lua5.4 STATIC_LDFLAGS=-static \
      "LUA_PATH=./?.lua;./?/init.lua;${LUA_PATH_EXTRA}"

RUN make check-binary STATIC_LDFLAGS=-static

# ---- export stage ----
FROM scratch
COPY --from=builder /src/bin/atlas-bin /atlas
