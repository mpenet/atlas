/* ABOUTME: Entry point of the standalone ezu binary: runs the bundled program
 * ABOUTME: (stripped Lua bytecode) with the native modules preloaded. */
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <zlib.h>
#include <lua.h>
#include <lauxlib.h>
#include <lualib.h>

/* written by c/embed.c */
extern const unsigned char ezu_program[];
extern const size_t ezu_program_size;
extern const unsigned char fennel_source[];
extern const size_t fennel_source_size;
extern const size_t fennel_source_length;
extern const unsigned char third_party[];
extern const size_t third_party_size;
extern const size_t third_party_length;

int luaopen_socket_core(lua_State *L);
int luaopen_ezu_curl(lua_State *L);
int luaopen_yaml(lua_State *L);

/* Push the text of a file c/embed.c deflated; 0 when it can't be inflated. */
static int push_inflated(lua_State *L, const unsigned char *data, size_t size,
                         size_t length) {
  uLongf n = length;
  char *text = malloc(length > 0 ? length : 1);
  if (text == NULL || uncompress((Bytef *)text, &n, data, size) != Z_OK) {
    free(text);
    return 0;
  }
  lua_pushlstring(L, text, n);
  free(text);
  return 1;
}

/* require "fennel": the Fennel compiler, kept deflated and inflated only
 * when something needs it (an auth plugin written in Fennel). */
static int load_fennel(lua_State *L) {
  size_t length;
  const char *text;
  if (!push_inflated(L, fennel_source, fennel_source_size, fennel_source_length))
    return luaL_error(L, "the Fennel compiler in ezu is damaged");
  text = lua_tolstring(L, -1, &length);
  if (luaL_loadbufferx(L, text, length, "=fennel", "t") != LUA_OK)
    return lua_error(L);
  lua_call(L, 0, 1);
  return 1;
}

/* require "ezu.third-party": the licenses of the software in the binary
 * (THIRD-PARTY.md), for ezu --licenses. */
static int load_third_party(lua_State *L) {
  if (!push_inflated(L, third_party, third_party_size, third_party_length))
    return luaL_error(L, "the licenses in ezu are damaged");
  return 1;
}

/* modules require finds in the binary itself */
static const luaL_Reg native_modules[] = {
  {"socket.core", luaopen_socket_core},
  {"ezu.curl", luaopen_ezu_curl},
  {"yaml", luaopen_yaml},
  {"fennel", load_fennel},
  {"ezu.third-party", load_third_party},
  {NULL, NULL}
};

/* An error's message with a traceback, as lua.c prints it. */
static int msghandler(lua_State *L) {
  const char *msg = lua_tostring(L, 1);
  if (msg == NULL) {
    if (luaL_callmeta(L, 1, "__tostring") && lua_type(L, -1) == LUA_TSTRING)
      return 1;
    msg = lua_pushfstring(L, "(error object is a %s value)", luaL_typename(L, 1));
  }
  luaL_traceback(L, L, msg, 1);
  return 1;
}

int main(int argc, char **argv) {
  lua_State *L = luaL_newstate();
  int status;
  if (L == NULL) {
    fprintf(stderr, "ezu: not enough memory\n");
    return 1;
  }
  luaL_openlibs(L);

  luaL_getsubtable(L, LUA_REGISTRYINDEX, LUA_PRELOAD_TABLE);
  for (const luaL_Reg *m = native_modules; m->name != NULL; m++) {
    lua_pushcfunction(L, m->func);
    lua_setfield(L, -2, m->name);
  }
  lua_pop(L, 1);

  /* arg[0] is the program, arg[1..] its arguments */
  lua_createtable(L, argc, 1);
  for (int i = 0; i < argc; i++) {
    lua_pushstring(L, argv[i]);
    lua_rawseti(L, -2, i);
  }
  lua_setglobal(L, "arg");

  lua_pushcfunction(L, msghandler);
  status = luaL_loadbufferx(L, (const char *)ezu_program, ezu_program_size,
                            "=ezu", "b");
  if (status == LUA_OK)
    status = lua_pcall(L, 0, 0, 1);
  if (status != LUA_OK)
    fprintf(stderr, "%s\n", lua_tostring(L, -1));
  lua_close(L);
  return status == LUA_OK ? 0 : 1;
}
