FENNEL ?= fnl
FNL_DIR = fnl

FNL_SOURCES = $(shell find $(FNL_DIR) -name "*.fnl" ! -name "atlas-bin.fnl")
LUA_TARGETS = $(FNL_SOURCES:$(FNL_DIR)/%.fnl=%.lua)

# ---- OS detection ----
UNAME_S := $(shell uname -s)

# ---- binary build paths ----
NATIVE_BUILD     = build/native
SOCKET_SRC       = $(NATIVE_BUILD)/luasocket/src
LUASEC_SRC       = $(NATIVE_BUILD)/luasec/src

# ---- auto-detected tool paths (override if needed) ----
LUA_INC         ?= $(shell pkg-config --cflags lua5.4 2>/dev/null | tr ' ' '\n' | grep '^-I' | head -1 | cut -c3-)
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

.PHONY: build binary clean deps install native-libs test

deps:
	luarocks install lunajson
	luarocks install luasocket
	luarocks install luasec
	luarocks install fennel
	luarocks install busted

build: $(LUA_TARGETS)

$(LUA_TARGETS): %.lua: $(FNL_DIR)/%.fnl
	@mkdir -p $(dir $@)
	$(FENNEL) --compile $< > $@

test: build
	busted test/

install: build
	install -m 755 bin/atlas /usr/local/bin/atlas

# ---- standalone binary ----

native-libs: $(NATIVE_BUILD)/.stamp

$(NATIVE_BUILD)/.stamp:
	@mkdir -p $(NATIVE_BUILD)
	@# extract luasocket
	@if [ ! -d $(SOCKET_SRC) ]; then \
	  (cd $(NATIVE_BUILD) && luarocks download --source luasocket 3.1.0-1 >/dev/null 2>&1); \
	  unzip -o $(NATIVE_BUILD)/luasocket-3.1.0-1.src.rock -d $(NATIVE_BUILD)/luasocket_tmp >/dev/null 2>&1; \
	  mv $(NATIVE_BUILD)/luasocket_tmp/luasocket $(NATIVE_BUILD)/luasocket; \
	  rm -rf $(NATIVE_BUILD)/luasocket_tmp $(NATIVE_BUILD)/luasocket-3.1.0-1.src.rock; \
	fi
	@# extract luasec
	@if [ ! -d $(LUASEC_SRC) ]; then \
	  (cd $(NATIVE_BUILD) && luarocks download --source luasec 1.3.2-1 >/dev/null 2>&1); \
	  unzip -o $(NATIVE_BUILD)/luasec-1.3.2-1.src.rock -d $(NATIVE_BUILD)/luasec_tmp >/dev/null 2>&1; \
	  mv $(NATIVE_BUILD)/luasec_tmp/luasec $(NATIVE_BUILD)/luasec; \
	  rm -rf $(NATIVE_BUILD)/luasec_tmp $(NATIVE_BUILD)/luasec-1.3.2-1.src.rock; \
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
	$(FENNEL) --compile-binary fnl/atlas-bin.fnl \
	  bin/atlas-bin \
	  $(LUA_LIB) \
	  $(LUA_INC) \
	  --native-module $(NATIVE_BUILD)/libsocket_core.a \
	  --native-module $(NATIVE_BUILD)/libmime_core.a \
	  --native-module $(NATIVE_BUILD)/libssl_lua.a

clean:
	rm -f $(LUA_TARGETS)
	find atlas -name "*.lua" -delete 2>/dev/null; true
	rm -rf build bin/atlas-bin fnl/atlas-bin.fnl_binary.c
