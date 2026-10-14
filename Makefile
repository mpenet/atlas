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
LUASEC_SRC       = $(NATIVE_BUILD)/luasec/src
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
OPENSSL_INC     ?= $(shell pkg-config --variable=includedir openssl 2>/dev/null)
LIBYAML_INC     ?= $(shell pkg-config --variable=includedir yaml-0.1 2>/dev/null)
_LIBYAML_LIBDIR := $(shell pkg-config --variable=libdir yaml-0.1 2>/dev/null)
ifeq ($(UNAME_S),Darwin)
  _LIBYAML_STATIC := $(wildcard $(_LIBYAML_LIBDIR)/libyaml.a)
  ifneq ($(_LIBYAML_STATIC),)
    LIBYAML_LDFLAGS ?= $(_LIBYAML_STATIC)
  else
    LIBYAML_LDFLAGS ?= $(shell pkg-config --libs yaml-0.1 2>/dev/null)
  endif
else
  LIBYAML_LDFLAGS ?= $(shell pkg-config --static --libs yaml-0.1 2>/dev/null)
endif
_OPENSSL_LIBDIR := $(shell pkg-config --variable=libdir openssl 2>/dev/null)
# Prefer static OpenSSL so the binary has no runtime dependency on Homebrew.
# Fall back to dynamic if .a files are absent (e.g. some Linux distros).
ifeq ($(UNAME_S),Darwin)
  _OPENSSL_STATIC := $(wildcard $(_OPENSSL_LIBDIR)/libssl.a)
  ifneq ($(_OPENSSL_STATIC),)
    OPENSSL_LDFLAGS ?= -L$(_OPENSSL_LIBDIR) $(_OPENSSL_LIBDIR)/libssl.a $(_OPENSSL_LIBDIR)/libcrypto.a -framework CoreFoundation -framework Security
  else
    OPENSSL_LDFLAGS ?= $(shell pkg-config --static --libs openssl 2>/dev/null)
  endif
else
  OPENSSL_LDFLAGS ?= $(shell pkg-config --static --libs openssl 2>/dev/null)
endif

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
LYAML_VERSION = 6.2.9
LYAML_CFLAGS  = -O2 -DVERSION=\"$(LYAML_VERSION)\" -I$(LUA_INC) -I$(LIBYAML_INC) -I$(LYAML_SRC)

SOCKET_CORE_SRCS = luasocket.c timeout.c buffer.c io.c auxiliar.c compat.c \
                   options.c inet.c usocket.c except.c select.c tcp.c udp.c
LUASEC_SRCS      = ssl.c context.c config.c options.c x509.c ec.c
LYAML_SRCS       = yaml.c parser.c emitter.c scanner.c

.PHONY: build binary check-binary clean deps fmt fmt-check install native-libs test
.DELETE_ON_ERROR:

deps:
	luarocks install lunajson
	luarocks install luasocket
	luarocks install luasec
	luarocks install lyaml
	luarocks install fennel
	luarocks install busted

build: $(LUA_TARGETS)

$(LUA_TARGETS): $(LUA_DIR)/%.lua: $(FNL_DIR)/%.fnl
	@mkdir -p $(dir $@)
	$(FENNEL) --compile $< > $@

test: build
	rm -rf build/test-home && mkdir -p build/test-home
	XDG_CACHE_HOME=$(CURDIR)/build/test-home/cache XDG_CONFIG_HOME=$(CURDIR)/build/test-home/config \
	LUA_PATH="./$(LUA_DIR)/?.lua;./$(LUA_DIR)/?/init.lua;$(shell luarocks path --lr-path 2>/dev/null)" busted test/

install: binary
	install -m 755 bin/atlas-bin /usr/local/bin/atlas

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
	@# extract lyaml
	@if [ ! -d $(LYAML_SRC) ]; then \
	  (cd $(NATIVE_BUILD) && luarocks download --source lyaml 6.2.9-2 >/dev/null 2>&1); \
	  unzip -o $(NATIVE_BUILD)/lyaml-6.2.9-2.src.rock -d $(NATIVE_BUILD)/lyaml_tmp >/dev/null 2>&1; \
	  unzip -o $(NATIVE_BUILD)/lyaml_tmp/v6.2.9.zip -d $(NATIVE_BUILD)/lyaml_tmp2 >/dev/null 2>&1; \
	  mv $(NATIVE_BUILD)/lyaml_tmp2/lyaml-6.2.9 $(NATIVE_BUILD)/lyaml; \
	  rm -rf $(NATIVE_BUILD)/lyaml_tmp $(NATIVE_BUILD)/lyaml_tmp2 $(NATIVE_BUILD)/lyaml-6.2.9-2.src.rock; \
	fi
	@# build lyaml_ext.a
	@echo "Building liblyaml_ext.a..."
	@for f in $(LYAML_SRCS); do \
	  $(CC) $(LYAML_CFLAGS) -c $(LYAML_SRC)/$$f -o $(LYAML_SRC)/$${f%.c}.o; \
	done
	@ar rcs $(NATIVE_BUILD)/liblyaml_ext.a $(foreach f,$(LYAML_SRCS),$(LYAML_SRC)/$(f:.c=.o))
	@touch $@

binary: build native-libs
	LUA_PATH="./$(LUA_DIR)/?.lua;./$(LUA_DIR)/?/init.lua;$(shell luarocks path --lr-path 2>/dev/null)" \
	CC_OPTS="$(OPENSSL_LDFLAGS) $(LIBYAML_LDFLAGS)" \
	$(FENNEL) --compile-binary fnl/atlas-bin.fnl \
	  bin/atlas-bin \
	  $(LUA_LIB) \
	  $(LUA_INC) \
	  --native-module $(NATIVE_BUILD)/libsocket_core.a \
	  --native-module $(NATIVE_BUILD)/libmime_core.a \
	  --native-module $(NATIVE_BUILD)/libssl_lua.a \
	  --native-module $(NATIVE_BUILD)/liblyaml_ext.a
	strip bin/atlas-bin

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

clean:
	rm -f $(LUA_TARGETS)
	rm -rf build bin/atlas-bin fnl/atlas-bin.fnl_binary.c
