FENNEL ?= fnl
FNL_DIR = fnl

FNL_SOURCES = $(shell find $(FNL_DIR) -name "*.fnl" ! -name "anis-bin.fnl")
LUA_TARGETS = $(FNL_SOURCES:$(FNL_DIR)/%.fnl=%.lua)

# ---- OS detection ----
UNAME_S := $(shell uname -s)

# ---- binary build paths ----
NATIVE_BUILD     = build/native
LUAROCKS_CACHE  ?= $(or $(wildcard $(HOME)/.cache/luarocks/https___luarocks.org),\
                        $(HOME)/.luarocks/cache/https___luarocks.org,\
                        $(HOME)/.cache/luarocks/https___luarocks.org)
SOCKET_SRC       = $(NATIVE_BUILD)/luasocket/src
LUASEC_SRC       = $(NATIVE_BUILD)/luasec/src

# ---- auto-detected tool paths (override if needed) ----
LUA_INC         ?= $(shell pkg-config --variable=includedir lua5.4 2>/dev/null)
_LUA_LIBDIR     := $(shell pkg-config --variable=libdir lua5.4 2>/dev/null)
LUA_LIB         ?= $(or $(wildcard $(_LUA_LIBDIR)/liblua5.4.a),\
                         $(wildcard $(_LUA_LIBDIR)/liblua.a),\
                         $(_LUA_LIBDIR)/liblua.a)
OPENSSL_INC     ?= $(shell pkg-config --variable=includedir openssl 2>/dev/null)
OPENSSL_LDFLAGS ?= $(shell pkg-config --static --libs openssl 2>/dev/null)

# macOS requires -DUNIX_HAS_SUN_LEN and -fno-common; Linux needs neither
ifeq ($(UNAME_S),Darwin)
  SOCKET_CFLAGS_EXTRA = -fno-common -DUNIX_HAS_SUN_LEN
  LUASEC_CFLAGS_EXTRA = -fno-common
else
  SOCKET_CFLAGS_EXTRA =
  LUASEC_CFLAGS_EXTRA =
endif

SOCKET_CFLAGS = -O2 $(SOCKET_CFLAGS_EXTRA) -DLUASOCKET_NODEBUG \
                -I$(LUA_INC) -I$(SOCKET_SRC)
LUASEC_CFLAGS = -O2 $(LUASEC_CFLAGS_EXTRA) -Wno-deprecated-declarations \
                -I$(LUA_INC) -I$(OPENSSL_INC) -I$(LUASEC_SRC)

SOCKET_CORE_SRCS = luasocket.c timeout.c buffer.c io.c auxiliar.c compat.c \
                   options.c inet.c usocket.c except.c select.c tcp.c udp.c
LUASEC_SRCS      = ssl.c context.c config.c options.c x509.c ec.c

.PHONY: build binary clean deps install native-libs

deps:
	luarocks install lunajson
	luarocks install luasocket
	luarocks install luasec

build: $(LUA_TARGETS)

$(LUA_TARGETS): %.lua: $(FNL_DIR)/%.fnl
	@mkdir -p $(dir $@)
	$(FENNEL) --compile $< > $@

install: build
	install -m 755 bin/anis /usr/local/bin/anis

# ---- standalone binary ----

native-libs: $(NATIVE_BUILD)/.stamp

$(NATIVE_BUILD)/.stamp:
	@mkdir -p $(NATIVE_BUILD)
	@# extract luasocket
	@if [ ! -d $(SOCKET_SRC) ]; then \
	  cp $(LUAROCKS_CACHE)/luasocket-3.1.0-1.src.rock /tmp/_lsock.zip; \
	  unzip -o /tmp/_lsock.zip -d $(NATIVE_BUILD)/luasocket_tmp >/dev/null 2>&1; \
	  mv $(NATIVE_BUILD)/luasocket_tmp/luasocket $(NATIVE_BUILD)/luasocket; \
	  rm -rf $(NATIVE_BUILD)/luasocket_tmp /tmp/_lsock.zip; \
	fi
	@# extract luasec
	@if [ ! -d $(LUASEC_SRC) ]; then \
	  cp $(LUAROCKS_CACHE)/luasec-1.3.2-1.src.rock /tmp/_lsec.zip; \
	  unzip -o /tmp/_lsec.zip -d $(NATIVE_BUILD)/luasec_tmp >/dev/null 2>&1; \
	  mv $(NATIVE_BUILD)/luasec_tmp/luasec $(NATIVE_BUILD)/luasec; \
	  rm -rf $(NATIVE_BUILD)/luasec_tmp /tmp/_lsec.zip; \
	fi
	@# build socket_core.a
	@echo "Building libsocket_core.a..."
	@for f in $(SOCKET_CORE_SRCS); do \
	  $(CC) $(SOCKET_CFLAGS) -c $(SOCKET_SRC)/$$f -o $(SOCKET_SRC)/$${f%.c}.o; \
	done
	@ar rcs $(NATIVE_BUILD)/libsocket_core.a $(foreach f,$(SOCKET_CORE_SRCS),$(SOCKET_SRC)/$(f:.c=.o))
	@# build mime_core.a (compat.o needs different name to avoid clash)
	@echo "Building libmime_core.a..."
	@$(CC) $(SOCKET_CFLAGS) -c $(SOCKET_SRC)/mime.c  -o $(SOCKET_SRC)/mime.o
	@$(CC) $(SOCKET_CFLAGS) -c $(SOCKET_SRC)/compat.c -o $(SOCKET_SRC)/compat_mime.o
	@ar rcs $(NATIVE_BUILD)/libmime_core.a $(SOCKET_SRC)/mime.o $(SOCKET_SRC)/compat_mime.o
	@# build ssl_lua.a
	@echo "Building libssl_lua.a..."
	@for f in $(LUASEC_SRCS); do \
	  $(CC) $(LUASEC_CFLAGS) -c $(LUASEC_SRC)/$$f -o $(LUASEC_SRC)/$${f%.c}.o; \
	done
	@ar rcs $(NATIVE_BUILD)/libssl_lua.a $(foreach f,$(LUASEC_SRCS),$(LUASEC_SRC)/$(f:.c=.o))
	@touch $@

binary: build native-libs
	CC_OPTS="$(OPENSSL_LDFLAGS)" \
	$(FENNEL) --compile-binary fnl/anis-bin.fnl \
	  bin/anis-bin \
	  $(LUA_LIB) \
	  $(LUA_INC) \
	  --native-module $(NATIVE_BUILD)/libsocket_core.a \
	  --native-module $(NATIVE_BUILD)/libmime_core.a \
	  --native-module $(NATIVE_BUILD)/libssl_lua.a

clean:
	rm -f $(LUA_TARGETS)
	find anis -name "*.lua" -delete 2>/dev/null; true
	rm -rf build bin/anis-bin fnl/anis-bin.fnl_binary.c
