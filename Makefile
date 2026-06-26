FENNEL ?= fnl
FNL_DIR = fnl

FNL_SOURCES = $(shell find $(FNL_DIR) -name "*.fnl")
LUA_TARGETS = $(FNL_SOURCES:$(FNL_DIR)/%.fnl=%.lua)

.PHONY: build clean deps

deps:
	luarocks install lunajson
	luarocks install luasocket
	luarocks install luasec

build: $(LUA_TARGETS)

$(LUA_TARGETS): %.lua: $(FNL_DIR)/%.fnl
	@mkdir -p $(dir $@)
	$(FENNEL) --compile $< > $@

clean:
	rm -f $(LUA_TARGETS)
	find anis -name "*.lua" -delete 2>/dev/null; true
