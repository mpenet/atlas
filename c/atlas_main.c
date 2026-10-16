/* ABOUTME: Entry point of the standalone atlas binary: runs the bundled program
 * ABOUTME: (stripped Lua bytecode) with the native modules preloaded. */
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <zlib.h>
#include <lua.h>
#include <lauxlib.h>
#include <lualib.h>

/* written by c/embed.c */
extern const unsigned char atlas_program[];
extern const size_t atlas_program_size;
extern const unsigned char fennel_source[];
extern const size_t fennel_source_size;
extern const size_t fennel_source_length;

int luaopen_socket_core(lua_State *L);
int luaopen_atlas_curl(lua_State *L);
int luaopen_yaml(lua_State *L);

/* require "fennel": the Fennel compiler, kept deflated and inflated only
 * when something needs it (an auth plugin written in Fennel). */
static int load_fennel(lua_State *L) {
  uLongf length = fennel_source_length;
  char *text = malloc(length);
  int status;
  if (text == NULL ||
      uncompress((Bytef *)text, &length, fennel_source, fennel_source_size) != Z_OK) {
    free(text);
    return luaL_error(L, "the Fennel compiler in atlas is damaged");
  }
  status = luaL_loadbufferx(L, text, length, "=fennel", "t");
  free(text);
  if (status != LUA_OK) return lua_error(L);
  lua_call(L, 0, 1);
  return 1;
}

/* modules require finds in the binary itself */
static const luaL_Reg native_modules[] = {
  {"socket.core", luaopen_socket_core},
  {"atlas.curl", luaopen_atlas_curl},
  {"yaml", luaopen_yaml},
  {"fennel", load_fennel},
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
    fprintf(stderr, "atlas: not enough memory\n");
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
  status = luaL_loadbufferx(L, (const char *)atlas_program, atlas_program_size,
                            "=atlas", "b");
  if (status == LUA_OK)
    status = lua_pcall(L, 0, 0, 1);
  if (status != LUA_OK)
    fprintf(stderr, "%s\n", lua_tostring(L, -1));
  lua_close(L);
  return status == LUA_OK ? 0 : 1;
}
