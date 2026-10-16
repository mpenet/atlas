FENNEL ?= $(shell command -v fnl 2>/dev/null || command -v fennel 2>/dev/null || echo fnl)
FNLFMT ?= fnlfmt
FNL_DIR = fnl
LUA_DIR = lua

FNL_SOURCES = $(shell find $(FNL_DIR) -name "*.fnl" ! -name "atlas-bin.fnl")
LUA_TARGETS = $(FNL_SOURCES:$(FNL_DIR)/%.fnl=$(LUA_DIR)/%.lua)

# ---- OS detection ----
UNAME_S := $(shell uname -s)

# ---- dependencies built from source (DEPS_FROM_SOURCE=1) ----
# For release binaries with a known minimum macOS version: Lua and libyaml
# are built from pinned, checksummed sources for
# MACOSX_DEPLOYMENT_TARGET, instead of using the system's or Homebrew's
# (which target the machine they were built on).
DEPS_FROM_SOURCE ?=
MACOSX_DEPLOYMENT_TARGET ?= 12.0
LUA_VERSION      = 5.4.9
LUA_SHA256       = 2335b6c582a52654f94612bf10d2f4672805d05329aa6568b1d8cd9e5c6fb8e6
LIBYAML_VERSION  = 0.2.5
LIBYAML_SHA256   = c642ae9b75fee120b2d96c712538bd2cf283228d2337df2cf2988e3c02678ef4
ifneq ($(DEPS_FROM_SOURCE),)
  NATIVE_BUILD   = build/native-src
  DEPS_PREFIX    = $(abspath $(NATIVE_BUILD)/deps)
  LUA_INC        := $(DEPS_PREFIX)/include
  LUA_LIB        := $(DEPS_PREFIX)/lib/liblua.a
  LIBYAML_INC    := $(DEPS_PREFIX)/include
  export MACOSX_DEPLOYMENT_TARGET
endif

# ---- binary build paths ----
NATIVE_BUILD     ?= build/native
SOCKET_SRC       = $(NATIVE_BUILD)/luasocket/src
CURL_PREFIX      = $(abspath $(NATIVE_BUILD)/curl)
MBEDTLS_PREFIX   = $(abspath $(NATIVE_BUILD)/mbedtls)
LYAML_SRC        = $(NATIVE_BUILD)/lyaml/ext/yaml

# ---- auto-detected tool paths (override if needed) ----
_lua_cflags     := $(shell pkg-config --cflags lua5.4 2>/dev/null || \
                            pkg-config --cflags lua5.5 2>/dev/null || \
                            pkg-config --cflags lua 2>/dev/null)
# pkg-config first, else luarocks (CI's Lua ships no .pc file)
LUA_INC         ?= $(or $(patsubst -I%,%,$(firstword $(filter -I%,$(_lua_cflags)))),\
                        $(shell luarocks config variables.LUA_INCDIR 2>/dev/null))
_LUA_LIBDIR     := $(shell pkg-config --variable=libdir lua5.4 2>/dev/null || \
                            pkg-config --variable=libdir lua5.5 2>/dev/null || \
                            pkg-config --variable=libdir lua 2>/dev/null)
LUA_LIB         ?= $(or $(wildcard $(_LUA_LIBDIR)/liblua5.4.a),\
                         $(wildcard $(_LUA_LIBDIR)/liblua5.5.a),\
                         $(wildcard $(_LUA_LIBDIR)/liblua.a),\
                         $(_LUA_LIBDIR)/liblua.a)
LIBYAML_INC     ?= $(shell pkg-config --variable=includedir yaml-0.1 2>/dev/null)
_LIBYAML_LIBDIR := $(if $(DEPS_FROM_SOURCE),$(DEPS_PREFIX)/lib,$(shell pkg-config --variable=libdir yaml-0.1 2>/dev/null))
_ZLIB_LIBDIR    := $(shell pkg-config --variable=libdir zlib 2>/dev/null)

# The binary links mbedTLS, libyaml and zlib statically, so it runs without
# them installed; only system libraries stay dynamic (check-binary enforces it).
# STATIC_LDFLAGS=-static links those too, for a fully static binary: right
# with musl (the Linux release build), wrong with glibc, whose resolver
# needs its shared libraries.
STATIC_LDFLAGS ?=
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
TLS_LDFLAGS = $(MBEDTLS_PREFIX)/lib/libmbedtls.a $(MBEDTLS_PREFIX)/lib/libmbedx509.a \
              $(MBEDTLS_PREFIX)/lib/libmbedcrypto.a
LIBYAML_LDFLAGS ?= -L$(_LIBYAML_LIBDIR) $(or $(wildcard $(_LIBYAML_LIBDIR)/libyaml.a),-lyaml)

SOCKET_CFLAGS = -O2 $(SOCKET_CFLAGS_EXTRA) -DLUASOCKET_NODEBUG \
                -I$(LUA_INC) -I$(SOCKET_SRC)
LYAML_VERSION = 6.2.9
LYAML_CFLAGS  = -O2 -DVERSION=\"$(LYAML_VERSION)\" -I$(LUA_INC) -I$(LIBYAML_INC) -I$(LYAML_SRC)

SOCKET_CORE_SRCS = luasocket.c timeout.c buffer.c io.c auxiliar.c compat.c \
                   options.c inet.c usocket.c except.c select.c tcp.c udp.c

# TLS for the binary's libcurl: mbedTLS (LTS branch), small and enough for
# HTTPS clients; built from its pinned, checksummed release
MBEDTLS_VERSION = 3.6.7
MBEDTLS_SHA256  = a7e8bcbec0e6f761b4af24f25677626b35f762f68eef79c08677a363212d11f6

# libcurl for the binary: HTTP(S) only, built against mbedTLS; CA
# certificates are located at runtime (atlas.tls), so none are compiled in
CURL_VERSION = 8.23.0
CURL_SHA256  = e3de77cfa6367083c776a26647fc9f633b538c06c3baa73d931a252ac8f72b49
CURL_CONFIGURE_FLAGS = --disable-shared --enable-static \
  --with-mbedtls=$(MBEDTLS_PREFIX) --without-openssl \
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

.PHONY: build binary check-binary check-binary-tls corpus unicode check-docs check-globals check-manifests clean deps fmt fmt-check install native-libs test
.DELETE_ON_ERROR:

deps:
	luarocks install lunajson
	luarocks install luasocket
	luarocks install lyaml
	luarocks install fennel
	luarocks install busted

build: $(LUA_TARGETS) $(CURL_MODULE)

$(CURL_MODULE): c/atlas_curl.c
	@test -f "$(LUA_INC)/lua.h" || { echo "lua.h not found in '$(LUA_INC)': set LUA_INC to Lua's include directory"; exit 1; }
	@mkdir -p $(dir $@)
	$(CC) -O2 -Wall -fPIC $(MODULE_LDFLAGS) -I$(LUA_INC) $(CURL_CFLAGS) $< $(CURL_LIBS) -o $@

$(LUA_TARGETS): $(LUA_DIR)/%.lua: $(FNL_DIR)/%.fnl
	@mkdir -p $(dir $@)
	$(FENNEL) --compile $< > $@

test: build check-globals check-manifests check-docs
	rm -rf build/test-home && mkdir -p build/test-home
	XDG_CACHE_HOME=$(CURDIR)/build/test-home/cache XDG_CONFIG_HOME=$(CURDIR)/build/test-home/config \
	LUA_PATH="./$(LUA_DIR)/?.lua;./$(LUA_DIR)/?/init.lua;$(shell luarocks path --lr-path 2>/dev/null)" \
	LUA_CPATH="./$(LUA_DIR)/?.so;$(shell luarocks path --lr-cpath 2>/dev/null);;" busted test/

PREFIX ?= /usr/local

install: binary
	install -d $(DESTDIR)$(PREFIX)/bin
	install -m 755 bin/atlas-bin $(DESTDIR)$(PREFIX)/bin/atlas

# ---- standalone binary ----

# the stamp names the libcurl and mbedTLS versions, so changing either
# rebuilds the libraries
NATIVE_STAMP = $(NATIVE_BUILD)/.stamp-curl-$(CURL_VERSION)-mbedtls-$(MBEDTLS_VERSION)

DEPS_STAMP = $(NATIVE_BUILD)/.deps-lua-$(LUA_VERSION)-yaml-$(LIBYAML_VERSION)

native-libs: $(NATIVE_STAMP) $(NATIVE_BUILD)/libatlas_curl.a

# fetch URL FILE SHA256: download and check against the pinned checksum
fetch = curl -fsSL -o $(2) $(1) && echo "$(3)  $(2)" | $(SHA256) -c -

$(DEPS_STAMP):
	@echo "Building Lua $(LUA_VERSION) and libyaml $(LIBYAML_VERSION) for macOS $(MACOSX_DEPLOYMENT_TARGET)..."
	rm -rf $(NATIVE_BUILD)/deps-src && mkdir -p $(NATIVE_BUILD)/deps-src
	cd $(NATIVE_BUILD)/deps-src && $(call fetch,https://www.lua.org/ftp/lua-$(LUA_VERSION).tar.gz,lua.tar.gz,$(LUA_SHA256)) && tar xzf lua.tar.gz
	$(MAKE) -C $(NATIVE_BUILD)/deps-src/lua-$(LUA_VERSION) $(if $(filter Darwin,$(UNAME_S)),macosx,linux) > /dev/null
	$(MAKE) -C $(NATIVE_BUILD)/deps-src/lua-$(LUA_VERSION) install INSTALL_TOP=$(DEPS_PREFIX) > /dev/null
	cd $(NATIVE_BUILD)/deps-src && $(call fetch,https://pyyaml.org/download/libyaml/yaml-$(LIBYAML_VERSION).tar.gz,yaml.tar.gz,$(LIBYAML_SHA256)) && tar xzf yaml.tar.gz
	cd $(NATIVE_BUILD)/deps-src/yaml-$(LIBYAML_VERSION) && CFLAGS="-O2 -fPIC" ./configure --prefix=$(DEPS_PREFIX) --disable-shared --enable-static > configure.log 2>&1 || { tail -30 configure.log; exit 1; }
	$(MAKE) -C $(NATIVE_BUILD)/deps-src/yaml-$(LIBYAML_VERSION) install > /dev/null
	@touch $@

$(NATIVE_STAMP): $(if $(DEPS_FROM_SOURCE),$(DEPS_STAMP))
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
	@# build mbedTLS, verified against its published checksum
	@echo "Building mbedTLS $(MBEDTLS_VERSION)..."
	rm -rf $(NATIVE_BUILD)/mbedtls-src $(MBEDTLS_PREFIX) && mkdir -p $(NATIVE_BUILD)/mbedtls-src $(MBEDTLS_PREFIX)/lib
	cd $(NATIVE_BUILD) && $(call fetch,https://github.com/Mbed-TLS/mbedtls/releases/download/mbedtls-$(MBEDTLS_VERSION)/mbedtls-$(MBEDTLS_VERSION).tar.bz2,mbedtls.tar.bz2,$(MBEDTLS_SHA256))
	tar xjf $(NATIVE_BUILD)/mbedtls.tar.bz2 -C $(NATIVE_BUILD)/mbedtls-src --strip-components 1
	$(MAKE) -C $(NATIVE_BUILD)/mbedtls-src lib CFLAGS="-O2 -fPIC" > /dev/null
	cp -R $(NATIVE_BUILD)/mbedtls-src/include $(MBEDTLS_PREFIX)/
	cp $(NATIVE_BUILD)/mbedtls-src/library/libmbedtls.a $(NATIVE_BUILD)/mbedtls-src/library/libmbedx509.a $(NATIVE_BUILD)/mbedtls-src/library/libmbedcrypto.a $(MBEDTLS_PREFIX)/lib/
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
	@touch $@

# the atlas.curl binding, against that libcurl
$(NATIVE_BUILD)/libatlas_curl.a: c/atlas_curl.c $(NATIVE_STAMP)
	$(CC) -O2 -Wall -DCURL_STATICLIB -I$(LUA_INC) -I$(CURL_PREFIX)/include -c c/atlas_curl.c -o $(NATIVE_BUILD)/atlas_curl.o
	ar rcs $@ $(NATIVE_BUILD)/atlas_curl.o

binary: $(LUA_TARGETS) native-libs
	LUA_PATH="./$(LUA_DIR)/?.lua;./$(LUA_DIR)/?/init.lua;$(shell luarocks path --lr-path 2>/dev/null)" \
	CC_OPTS="$(CURL_PREFIX)/lib/libcurl.a $(TLS_LDFLAGS) $(ZLIB_LDFLAGS) $(LIBYAML_LDFLAGS) $(SYSTEM_LDFLAGS) $(STATIC_LDFLAGS)" \
	$(FENNEL) --compile-binary fnl/atlas-bin.fnl \
	  bin/atlas-bin \
	  $(LUA_LIB) \
	  $(LUA_INC) \
	  --native-module $(NATIVE_BUILD)/libsocket_core.a \
	  --native-module $(NATIVE_BUILD)/libatlas_curl.a \
	  --native-module $(NATIVE_BUILD)/liblyaml_ext.a
	strip bin/atlas-bin

# Every module must be installed by the rockspec and bundled in the binary,
# after the Fennel modules it requires; both lists are maintained by hand.
check-manifests:
	@missing=0; for f in $(FNL_SOURCES); do \
	  m=$$(echo $$f | sed -e 's|^$(FNL_DIR)/||' -e 's|\.fnl$$||' -e 's|/|.|g'); \
	  grep -q "\[\"$$m\"\]" atlas-oai-dev-1.rockspec || { echo "missing from rockspec: $$m"; missing=1; }; \
	  at=$$(grep -n "^(require :$$m)" fnl/atlas-bin.fnl | cut -d: -f1); \
	  [ -n "$$at" ] || { echo "missing from atlas-bin.fnl: $$m"; missing=1; continue; }; \
	  for d in $$(grep -o "(require :atlas[a-z.-]*)" $$f | sed -e 's|(require :||' -e 's|)||'); do \
	    [ -f $(FNL_DIR)/$$(echo $$d | tr . /).fnl ] || continue; \
	    dat=$$(grep -n "^(require :$$d)" fnl/atlas-bin.fnl | cut -d: -f1); \
	    [ -n "$$dat" ] && [ "$$dat" -lt "$$at" ] || { echo "atlas-bin.fnl requires $$m before $$d, which it requires"; missing=1; }; \
	  done; \
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
ifneq ($(DEPS_FROM_SOURCE),)
	@# and runs on the macOS it was built for
	@otool -l bin/atlas-bin | grep -A4 LC_BUILD_VERSION | grep -q "minos $(MACOSX_DEPLOYMENT_TARGET)" || (otool -l bin/atlas-bin | grep -A4 LC_BUILD_VERSION; echo "expected minos $(MACOSX_DEPLOYMENT_TARGET)" && false)
endif
else ifneq ($(STATIC_LDFLAGS),)
	@# no loader and no shared library: static, or static PIE (newer toolchains)
	@! readelf -lW bin/atlas-bin | grep -q INTERP || (echo "expected a fully static binary: it names a loader" && false)
	@! readelf -dW bin/atlas-bin | grep -q NEEDED || (readelf -dW bin/atlas-bin | grep NEEDED; echo "expected a fully static binary" && false)
else
	@! ldd bin/atlas-bin | grep -vE 'linux-vdso|ld-linux|/lib(c|m|dl|pthread|rt)\.so' || (echo "non-system libraries linked above" && false)
endif

# Every relative link of the documentation names an existing page and heading.
check-docs:
	lua tools/check-doc-links.lua README.md CHANGELOG.md doc/*.md doc/library/*.md

# Regenerates the tables made from Unicode's data files:
# fnl/atlas/cli/width.fnl (display width of text in a terminal) and
# fnl/atlas/unicode-categories.fnl (general categories, for regexes).
UNICODE_VERSION = 17.0.0
UNICODE_DIR = build/unicode
unicode:
	mkdir -p $(UNICODE_DIR)
	curl -fsSL -o $(UNICODE_DIR)/EastAsianWidth.txt https://www.unicode.org/Public/$(UNICODE_VERSION)/ucd/EastAsianWidth.txt
	curl -fsSL -o $(UNICODE_DIR)/DerivedGeneralCategory.txt https://www.unicode.org/Public/$(UNICODE_VERSION)/ucd/extracted/DerivedGeneralCategory.txt
	lua tools/unicode-width.lua $(UNICODE_VERSION) $(UNICODE_DIR)/EastAsianWidth.txt $(UNICODE_DIR)/DerivedGeneralCategory.txt > $(UNICODE_DIR)/width.fnl
	mv $(UNICODE_DIR)/width.fnl fnl/atlas/cli/width.fnl
	lua tools/unicode-categories.lua $(UNICODE_VERSION) $(UNICODE_DIR)/DerivedGeneralCategory.txt > $(UNICODE_DIR)/categories.fnl
	mv $(UNICODE_DIR)/categories.fnl fnl/atlas/unicode-categories.fnl

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
