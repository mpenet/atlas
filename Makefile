FENNEL ?= $(shell command -v fnl 2>/dev/null || command -v fennel 2>/dev/null || echo fnl)
FNLFMT ?= fnlfmt
FNL_DIR = fnl
LUA_DIR = lua

FNL_SOURCES = $(shell find $(FNL_DIR) -name "*.fnl" ! -name "atlas-bin.fnl")
LUA_TARGETS = $(FNL_SOURCES:$(FNL_DIR)/%.fnl=$(LUA_DIR)/%.lua)

# ---- OS detection ----
UNAME_S := $(shell uname -s)

# ---- binary build paths ----
NATIVE_BUILD     = build/native
SOCKET_SRC       = $(NATIVE_BUILD)/luasocket/src
CURL_PREFIX      = $(abspath $(NATIVE_BUILD)/curl)
LYAML_SRC        = $(NATIVE_BUILD)/lyaml/ext/yaml

# ---- auto-detected tool paths (override if needed) ----
_lua_cflags     := $(shell pkg-config --cflags lua5.4 2>/dev/null || \
                            pkg-config --cflags lua5.5 2>/dev/null || \
                            pkg-config --cflags lua 2>/dev/null)
LUA_INC         ?= $(patsubst -I%,%,$(firstword $(filter -I%,$(_lua_cflags))))
_LUA_LIBDIR     := $(shell pkg-config --variable=libdir lua5.4 2>/dev/null || \
                            pkg-config --variable=libdir lua5.5 2>/dev/null || \
                            pkg-config --variable=libdir lua 2>/dev/null)
LUA_LIB         ?= $(or $(wildcard $(_LUA_LIBDIR)/liblua5.4.a),\
                         $(wildcard $(_LUA_LIBDIR)/liblua5.5.a),\
                         $(wildcard $(_LUA_LIBDIR)/liblua.a),\
                         $(_LUA_LIBDIR)/liblua.a)
OPENSSL_PREFIX  ?= $(shell pkg-config --variable=prefix openssl 2>/dev/null)
LIBYAML_INC     ?= $(shell pkg-config --variable=includedir yaml-0.1 2>/dev/null)
_LIBYAML_LIBDIR := $(shell pkg-config --variable=libdir yaml-0.1 2>/dev/null)
_OPENSSL_LIBDIR := $(shell pkg-config --variable=libdir openssl 2>/dev/null)
_ZLIB_LIBDIR    := $(shell pkg-config --variable=libdir zlib 2>/dev/null)

# The binary links OpenSSL, libyaml and zlib statically, so it runs without
# them installed; only system libraries stay dynamic (check-binary enforces it).
ifeq ($(UNAME_S),Darwin)
  SYSTEM_LDFLAGS = -framework CoreFoundation -framework Security -framework SystemConfiguration
  # zlib ships with macOS
  ZLIB_LDFLAGS ?= -lz
  SOCKET_CFLAGS_EXTRA = -fno-common -DUNIX_HAS_SUN_LEN
  SHA256 = shasum -a 256
else
  SYSTEM_LDFLAGS = -ldl -lpthread
  ZLIB_LDFLAGS ?= $(or $(wildcard $(_ZLIB_LIBDIR)/libz.a),-lz)
  SOCKET_CFLAGS_EXTRA =
  SHA256 = sha256sum
endif
OPENSSL_LDFLAGS ?= -L$(_OPENSSL_LIBDIR) $(or $(wildcard $(_OPENSSL_LIBDIR)/libssl.a),-lssl) \
                   $(or $(wildcard $(_OPENSSL_LIBDIR)/libcrypto.a),-lcrypto)
LIBYAML_LDFLAGS ?= -L$(_LIBYAML_LIBDIR) $(or $(wildcard $(_LIBYAML_LIBDIR)/libyaml.a),-lyaml)

SOCKET_CFLAGS = -O2 $(SOCKET_CFLAGS_EXTRA) -DLUASOCKET_NODEBUG \
                -I$(LUA_INC) -I$(SOCKET_SRC)
LYAML_VERSION = 6.2.9
LYAML_CFLAGS  = -O2 -DVERSION=\"$(LYAML_VERSION)\" -I$(LUA_INC) -I$(LIBYAML_INC) -I$(LYAML_SRC)

SOCKET_CORE_SRCS = luasocket.c timeout.c buffer.c io.c auxiliar.c compat.c \
                   options.c inet.c usocket.c except.c select.c tcp.c udp.c

# libcurl for the binary: HTTP(S) only, built against the OpenSSL above;
# CA certificates are located at runtime (atlas.tls), so none are compiled in
CURL_VERSION = 8.23.0
CURL_SHA256  = e3de77cfa6367083c776a26647fc9f633b538c06c3baa73d931a252ac8f72b49
CURL_CONFIGURE_FLAGS = --disable-shared --enable-static --with-openssl=$(OPENSSL_PREFIX) \
  --with-zlib --without-ca-bundle --without-ca-path \
  --disable-ftp --disable-file --disable-ldap --disable-ldaps --disable-rtsp \
  --disable-dict --disable-telnet --disable-tftp --disable-pop3 --disable-imap \
  --disable-smb --disable-smtp --disable-gopher --disable-mqtt --disable-ipfs \
  --disable-websockets --disable-ntlm --disable-manual --disable-docs \
  --without-libpsl --without-brotli --without-zstd --without-libidn2 \
  --without-nghttp2 --without-libssh2 --without-librtmp
LYAML_SRCS       = yaml.c parser.c emitter.c scanner.c

# ---- libcurl binding (shared module for development and tests) ----
CURL_CFLAGS ?= $(shell curl-config --cflags 2>/dev/null)
CURL_LIBS   ?= $(shell curl-config --libs 2>/dev/null)
ifeq ($(UNAME_S),Darwin)
  MODULE_LDFLAGS = -bundle -undefined dynamic_lookup
else
  MODULE_LDFLAGS = -shared -fPIC
endif
CURL_MODULE = $(LUA_DIR)/atlas/curl.so

.PHONY: build binary check-binary check-binary-tls corpus check-globals check-manifests clean deps fmt fmt-check install native-libs test
.DELETE_ON_ERROR:

deps:
	luarocks install lunajson
	luarocks install luasocket
	luarocks install lyaml
	luarocks install fennel
	luarocks install busted

build: $(LUA_TARGETS) $(CURL_MODULE)

$(CURL_MODULE): c/atlas_curl.c
	@mkdir -p $(dir $@)
	$(CC) -O2 -Wall -fPIC $(MODULE_LDFLAGS) -I$(LUA_INC) $(CURL_CFLAGS) $< $(CURL_LIBS) -o $@

$(LUA_TARGETS): $(LUA_DIR)/%.lua: $(FNL_DIR)/%.fnl
	@mkdir -p $(dir $@)
	$(FENNEL) --compile $< > $@

test: build check-globals check-manifests
	rm -rf build/test-home && mkdir -p build/test-home
	XDG_CACHE_HOME=$(CURDIR)/build/test-home/cache XDG_CONFIG_HOME=$(CURDIR)/build/test-home/config \
	LUA_PATH="./$(LUA_DIR)/?.lua;./$(LUA_DIR)/?/init.lua;$(shell luarocks path --lr-path 2>/dev/null)" \
	LUA_CPATH="./$(LUA_DIR)/?.so;$(shell luarocks path --lr-cpath 2>/dev/null);;" busted test/

PREFIX ?= /usr/local

install: binary
	install -d $(DESTDIR)$(PREFIX)/bin
	install -m 755 bin/atlas-bin $(DESTDIR)$(PREFIX)/bin/atlas

# ---- standalone binary ----

native-libs: $(NATIVE_BUILD)/.stamp

$(NATIVE_BUILD)/.stamp:
	@mkdir -p $(NATIVE_BUILD)
	@# extract luasocket
	@if [ ! -d $(SOCKET_SRC) ]; then \
	  (cd $(NATIVE_BUILD) && luarocks download --source luasocket 3.1.0-1 >/dev/null) || exit 1; \
	  unzip -o $(NATIVE_BUILD)/luasocket-3.1.0-1.src.rock -d $(NATIVE_BUILD)/luasocket_tmp >/dev/null || exit 1; \
	  mv $(NATIVE_BUILD)/luasocket_tmp/luasocket $(NATIVE_BUILD)/luasocket; \
	  rm -rf $(NATIVE_BUILD)/luasocket_tmp $(NATIVE_BUILD)/luasocket-3.1.0-1.src.rock; \
	fi
	@# build socket_core.a
	@echo "Building libsocket_core.a..."
	@for f in $(SOCKET_CORE_SRCS); do \
	  $(CC) $(SOCKET_CFLAGS) -c $(SOCKET_SRC)/$$f -o $(SOCKET_SRC)/$${f%.c}.o; \
	done
	@ar rcs $(NATIVE_BUILD)/libsocket_core.a $(foreach f,$(SOCKET_CORE_SRCS),$(SOCKET_SRC)/$(f:.c=.o))
	@# extract lyaml
	@if [ ! -d $(LYAML_SRC) ]; then \
	  (cd $(NATIVE_BUILD) && luarocks download --source lyaml 6.2.9-2 >/dev/null) || exit 1; \
	  unzip -o $(NATIVE_BUILD)/lyaml-6.2.9-2.src.rock -d $(NATIVE_BUILD)/lyaml_tmp >/dev/null || exit 1; \
	  unzip -o $(NATIVE_BUILD)/lyaml_tmp/v6.2.9.zip -d $(NATIVE_BUILD)/lyaml_tmp2 >/dev/null || exit 1; \
	  mv $(NATIVE_BUILD)/lyaml_tmp2/lyaml-6.2.9 $(NATIVE_BUILD)/lyaml; \
	  rm -rf $(NATIVE_BUILD)/lyaml_tmp $(NATIVE_BUILD)/lyaml_tmp2 $(NATIVE_BUILD)/lyaml-6.2.9-2.src.rock; \
	fi
	@# build lyaml_ext.a
	@echo "Building liblyaml_ext.a..."
	@for f in $(LYAML_SRCS); do \
	  $(CC) $(LYAML_CFLAGS) -c $(LYAML_SRC)/$$f -o $(LYAML_SRC)/$${f%.c}.o; \
	done
	@ar rcs $(NATIVE_BUILD)/liblyaml_ext.a $(foreach f,$(LYAML_SRCS),$(LYAML_SRC)/$(f:.c=.o))
	@# build libcurl, verified against its published checksum
	@echo "Building libcurl $(CURL_VERSION)..."
	curl -fsSL -o $(NATIVE_BUILD)/curl.tar.gz https://curl.se/download/curl-$(CURL_VERSION).tar.gz
	echo "$(CURL_SHA256)  $(NATIVE_BUILD)/curl.tar.gz" | $(SHA256) -c -
	rm -rf $(NATIVE_BUILD)/curl-src && mkdir -p $(NATIVE_BUILD)/curl-src
	tar xzf $(NATIVE_BUILD)/curl.tar.gz -C $(NATIVE_BUILD)/curl-src --strip-components 1
	cd $(NATIVE_BUILD)/curl-src && CFLAGS="-O2 -fPIC" ./configure --prefix=$(CURL_PREFIX) $(CURL_CONFIGURE_FLAGS) > configure.log 2>&1 || { tail -30 configure.log; exit 1; }
	$(MAKE) -C $(NATIVE_BUILD)/curl-src/lib > /dev/null
	$(MAKE) -C $(NATIVE_BUILD)/curl-src/lib install > /dev/null
	$(MAKE) -C $(NATIVE_BUILD)/curl-src/include install > /dev/null
	@# build the atlas.curl binding against it
	$(CC) -O2 -Wall -DCURL_STATICLIB -I$(LUA_INC) -I$(CURL_PREFIX)/include -c c/atlas_curl.c -o $(NATIVE_BUILD)/atlas_curl.o
	@ar rcs $(NATIVE_BUILD)/libatlas_curl.a $(NATIVE_BUILD)/atlas_curl.o
	@touch $@

binary: build native-libs
	LUA_PATH="./$(LUA_DIR)/?.lua;./$(LUA_DIR)/?/init.lua;$(shell luarocks path --lr-path 2>/dev/null)" \
	CC_OPTS="$(CURL_PREFIX)/lib/libcurl.a $(OPENSSL_LDFLAGS) $(ZLIB_LDFLAGS) $(LIBYAML_LDFLAGS) $(SYSTEM_LDFLAGS)" \
	$(FENNEL) --compile-binary fnl/atlas-bin.fnl \
	  bin/atlas-bin \
	  $(LUA_LIB) \
	  $(LUA_INC) \
	  --native-module $(NATIVE_BUILD)/libsocket_core.a \
	  --native-module $(NATIVE_BUILD)/libatlas_curl.a \
	  --native-module $(NATIVE_BUILD)/liblyaml_ext.a
	strip bin/atlas-bin

# Every module must be installed by the rockspec and bundled in the binary;
# both lists are maintained by hand.
check-manifests:
	@missing=0; for f in $(FNL_SOURCES); do \
	  m=$$(echo $$f | sed -e 's|^$(FNL_DIR)/||' -e 's|\.fnl$$||' -e 's|/|.|g'); \
	  grep -q "\[\"$$m\"\]" atlas-oai-dev-1.rockspec || { echo "missing from rockspec: $$m"; missing=1; }; \
	  grep -q "(require :$$m)" fnl/atlas-bin.fnl || { echo "missing from atlas-bin.fnl: $$m"; missing=1; }; \
	done; exit $$missing

# A name used before its definition compiles to a global lookup that is
# nil at runtime; fail the build instead.
check-globals: build
	@! grep -n "__fnl_global__" $(LUA_TARGETS) || (echo "unresolved names above (used before definition?)" && false)

FMT_SOURCES = $(shell find $(FNL_DIR) test -name "*.fnl")

# fnlfmt may need two passes to settle nested forms.
fmt:
	$(FNLFMT) --fix $(FMT_SOURCES)
	$(FNLFMT) --fix $(FMT_SOURCES)

fmt-check:
	$(FNLFMT) --check $(FMT_SOURCES)

# Run the binary with module search paths emptied, so it only passes when
# every module is bundled.
check-binary:
	env -i PATH=/usr/bin:/bin LUA_PATH=";" LUA_CPATH=";" ./bin/atlas-bin op test/fixtures/petstore.yaml --list
	@# and links nothing but system libraries
ifeq ($(UNAME_S),Darwin)
	@! otool -L bin/atlas-bin | tail -n +2 | grep -vE '^\s+(/usr/lib/|/System/Library/)' || (echo "non-system libraries linked above" && false)
else
	@! ldd bin/atlas-bin | grep -vE 'linux-vdso|ld-linux|/lib(c|m|dl|pthread|rt)\.so' || (echo "non-system libraries linked above" && false)
endif

# Over the network: real-world specs (test/corpus/specs.txt) must load and
# every operation must build, render help and pass the request checks.
CORPUS_DIR = build/corpus
corpus: build
	@mkdir -p $(CORPUS_DIR)
	@grep -v '^#' test/corpus/specs.txt | while read -r name url; do \
	  [ -s $(CORPUS_DIR)/$$name ] || curl -fsSL --max-time 300 -o $(CORPUS_DIR)/$$name "$$url" || { echo "cannot download $$name"; exit 1; }; \
	done
	cd $(CORPUS_DIR) && \
	LUA_PATH="$(CURDIR)/$(LUA_DIR)/?.lua;$(CURDIR)/$(LUA_DIR)/?/init.lua;$(shell luarocks path --lr-path 2>/dev/null)" \
	LUA_CPATH="$(CURDIR)/$(LUA_DIR)/?.so;$(shell luarocks path --lr-cpath 2>/dev/null);;" \
	lua $(CURDIR)/test/corpus/check.lua $$(grep -v '^#' $(CURDIR)/test/corpus/specs.txt | cut -d' ' -f1)

# Over the network: the binary must fetch a schema over verified HTTPS and
# refuse a server whose certificate does not verify.
check-binary-tls:
	home=$$(mktemp -d) && \
	env -i PATH=/usr/bin:/bin HOME=$$home ./bin/atlas-bin op https://petstore3.swagger.io/api/v3/openapi.json --list > /dev/null && \
	! env -i PATH=/usr/bin:/bin HOME=$$home ./bin/atlas-bin op https://self-signed.badssl.com/ --list 2> /dev/null && \
	rm -rf $$home && echo "TLS checks passed"

clean:
	rm -f $(LUA_TARGETS)
	rm -rf build bin/atlas-bin fnl/atlas-bin.fnl_binary.c
