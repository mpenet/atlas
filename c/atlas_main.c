/* ABOUTME: Entry point of the standalone atlas binary: runs the bundled program
 * ABOUTME: (stripped Lua bytecode) with the native modules preloaded. */
#include <stddef.h>
#include <stdio.h>
#include <lua.h>
#include <lauxlib.h>
#include <lualib.h>

/* written by c/embed.c */
extern const unsigned char atlas_program[];
extern const size_t atlas_program_size;

int luaopen_socket_core(lua_State *L);
int luaopen_atlas_curl(lua_State *L);
int luaopen_yaml(lua_State *L);

static const luaL_Reg native_modules[] = {
  {"socket.core", luaopen_socket_core},
  {"atlas.curl", luaopen_atlas_curl},
  {"yaml", luaopen_yaml},
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
