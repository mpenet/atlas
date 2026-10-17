/* ABOUTME: Build tool: writes the C arrays the binary carries: the program as
 * ABOUTME: stripped bytecode of the Lua it links, or a file deflated. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <lua.h>
#include <lauxlib.h>
#include <zlib.h>

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

/* PROGRAM.lua as the stripped bytecode ezu_program. */
static int embed_program(const char *source, const char *target) {
  struct output out = {NULL, 0};
  lua_State *L = luaL_newstate();
  if (L == NULL || luaL_loadfile(L, source) != LUA_OK) {
    fprintf(stderr, "%s\n", L ? lua_tostring(L, -1) : "not enough memory");
    return 1;
  }
  out.file = fopen(target, "w");
  if (out.file == NULL) {
    perror(target);
    return 1;
  }
  fprintf(out.file, "#include <stddef.h>\nconst unsigned char ezu_program[] = {\n");
  if (lua_dump(L, write_bytes, &out, 1) != 0) {
    fprintf(stderr, "cannot write %s\n", target);
    return 1;
  }
  fprintf(out.file, "\n};\nconst size_t ezu_program_size = %zu;\n", out.size);
  lua_close(L);
  return fclose(out.file) == 0 ? 0 : 1;
}

/* FILE deflated as NAME, with NAME_size (deflated) and NAME_length (the
 * file's). */
static int embed_deflated(const char *name, const char *source,
                          const char *target) {
  FILE *in = fopen(source, "rb");
  if (in == NULL) {
    perror(source);
    return 1;
  }
  fseek(in, 0, SEEK_END);
  long length = ftell(in);
  rewind(in);
  unsigned char *text = malloc(length > 0 ? length : 1);
  uLongf size = compressBound(length);
  unsigned char *deflated = malloc(size);
  if (text == NULL || deflated == NULL ||
      fread(text, 1, length, in) != (size_t)length ||
      compress2(deflated, &size, text, length, Z_BEST_COMPRESSION) != Z_OK) {
    fprintf(stderr, "cannot deflate %s\n", source);
    return 1;
  }
  fclose(in);
  struct output out = {fopen(target, "w"), 0};
  if (out.file == NULL) {
    perror(target);
    return 1;
  }
  fprintf(out.file, "#include <stddef.h>\nconst unsigned char %s[] = {\n", name);
  write_bytes(NULL, deflated, size, &out);
  fprintf(out.file, "\n};\nconst size_t %s_size = %lu;\nconst size_t %s_length = %ld;\n",
          name, (unsigned long)size, name, length);
  free(text);
  free(deflated);
  return fclose(out.file) == 0 ? 0 : 1;
}

int main(int argc, char **argv) {
  if (argc == 3) return embed_program(argv[1], argv[2]);
  if (argc == 5 && strcmp(argv[1], "--deflated") == 0)
    return embed_deflated(argv[2], argv[3], argv[4]);
  fprintf(stderr, "usage: %s PROGRAM.lua OUTPUT.c\n"
                  "       %s --deflated NAME FILE OUTPUT.c\n", argv[0], argv[0]);
  return 2;
}
