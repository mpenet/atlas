FROM debian:bookworm-slim AS builder

RUN apt-get update -q && apt-get install -y --no-install-recommends \
    lua5.4 liblua5.4-dev libssl-dev pkg-config unzip wget \
    build-essential ca-certificates \
  && rm -rf /var/lib/apt/lists/*

# luarocks from apt targets Lua 5.1 — build from source for 5.4
RUN wget -q https://luarocks.org/releases/luarocks-3.11.1.tar.gz \
  && tar xzf luarocks-3.11.1.tar.gz \
  && cd luarocks-3.11.1 \
  && ./configure --with-lua-version=5.4 --with-lua-bin=/usr/bin --lua-suffix=5.4 \
  && make -j$(nproc) \
  && make install \
  && cd .. && rm -rf luarocks-3.11.1 luarocks-3.11.1.tar.gz

RUN luarocks install fennel \
  && luarocks install lunajson \
  && luarocks install luasocket \
  && luarocks install luasec

WORKDIR /src
COPY . .

RUN make binary FENNEL=fennel

# ---- export stage ----
FROM scratch
COPY --from=builder /src/bin/atlas-bin /atlas-linux-x86_64
