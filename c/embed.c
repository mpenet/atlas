/* ABOUTME: Build tool: compiles a Lua file to stripped bytecode, with the Lua the
 * ABOUTME: binary links, and writes it as the C array atlas_main.c runs. */
#include <stdio.h>
#include <lua.h>
#include <lauxlib.h>

struct output {
  FILE *file;
  size_t size;
};

static int write_bytes(lua_State *L, const void *p, size_t n, void *ud) {
  struct output *out = ud;
  const unsigned char *bytes = p;
  (void)L;
  for (size_t i = 0; i < n; i++, out->size++)
    fprintf(out->file, "%s0x%02x",
            out->size == 0 ? "" : out->size % 16 ? "," : ",\n", bytes[i]);
  return ferror(out->file);
}

int main(int argc, char **argv) {
  lua_State *L;
  struct output out = {NULL, 0};
  if (argc != 3) {
    fprintf(stderr, "usage: %s PROGRAM.lua OUTPUT.c\n", argv[0]);
    return 2;
  }
  L = luaL_newstate();
  if (L == NULL || luaL_loadfile(L, argv[1]) != LUA_OK) {
    fprintf(stderr, "%s\n", L ? lua_tostring(L, -1) : "not enough memory");
    return 1;
  }
  out.file = fopen(argv[2], "w");
  if (out.file == NULL) {
    perror(argv[2]);
    return 1;
  }
  fprintf(out.file, "#include <stddef.h>\nconst unsigned char atlas_program[] = {\n");
  if (lua_dump(L, write_bytes, &out, 1) != 0) {
    fprintf(stderr, "cannot write %s\n", argv[2]);
    return 1;
  }
  fprintf(out.file, "\n};\nconst size_t atlas_program_size = %zu;\n", out.size);
  lua_close(L);
  return fclose(out.file) == 0 ? 0 : 1;
}
