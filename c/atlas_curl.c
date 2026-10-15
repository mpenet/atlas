/* ABOUTME: Lua binding to libcurl's easy API: performs one HTTP exchange and
 * ABOUTME: returns the status, the final response's header block and the body. */
#include <limits.h>
#include <stdlib.h>
#include <string.h>
#include <curl/curl.h>
#include <lua.h>
#include <lauxlib.h>

/* One handle for the process, so connections are reused between requests. */
static CURL *handle = NULL;

typedef struct {
  char *data;
  size_t len;
  size_t cap;
} buffer;

static int buffer_append(buffer *b, const char *src, size_t n) {
  if (b->len + n + 1 > b->cap) {
    size_t cap = b->cap ? b->cap : 4096;
    while (cap < b->len + n + 1) cap *= 2;
    char *data = realloc(b->data, cap);
    if (!data) return 0;
    b->data = data;
    b->cap = cap;
  }
  memcpy(b->data + b->len, src, n);
  b->len += n;
  b->data[b->len] = '\0';
  return 1;
}

static size_t on_body(char *ptr, size_t size, size_t nmemb, void *userdata) {
  size_t n = size * nmemb;
  return buffer_append((buffer *)userdata, ptr, n) ? n : 0;
}

/* Interim responses (100 Continue, proxy CONNECT) each start a new header
 * block; keep only the last one. */
static size_t on_header(char *ptr, size_t size, size_t nmemb, void *userdata) {
  buffer *b = (buffer *)userdata;
  size_t n = size * nmemb;
  if (n >= 5 && memcmp(ptr, "HTTP/", 5) == 0) b->len = 0;
  return buffer_append(b, ptr, n) ? n : 0;
}

static const char *opt_string(lua_State *L, int t, const char *key) {
  lua_getfield(L, t, key);
  if (lua_isnil(L, -1)) {
    lua_pop(L, 1);
    return NULL;
  }
  if (lua_type(L, -1) != LUA_TSTRING)
    luaL_error(L, "%s must be a string", key);
  size_t len;
  const char *s = lua_tolstring(L, -1, &len);
  /* libcurl reads C strings: a NUL would silently cut the rest off */
  if (strlen(s) != len && strcmp(key, "body") != 0)
    luaL_error(L, "%s must not contain NUL bytes", key);
  lua_pop(L, 1); /* the string stays alive: t still references it */
  return s;
}

/* perform{method, url, headers = {"Name: value", ...}, body, timeout,
 *         verify, cafile, capath, cert, key}
 * -> status, header_text, body | nil, message */
static int perform(lua_State *L) {
  luaL_checktype(L, 1, LUA_TTABLE);
  const char *method = opt_string(L, 1, "method");
  const char *url = opt_string(L, 1, "url");
  luaL_argcheck(L, method && url, 1, "method and url are required");

  size_t body_len = 0;
  const char *body = opt_string(L, 1, "body");
  if (body) {
    lua_getfield(L, 1, "body");
    body_len = lua_rawlen(L, -1);
    lua_pop(L, 1);
  }

  lua_getfield(L, 1, "timeout");
  lua_Number timeout = lua_isnil(L, -1) ? 0 : luaL_checknumber(L, -1);
  lua_pop(L, 1);

  lua_getfield(L, 1, "verify");
  int verify = lua_isnil(L, -1) ? 1 : lua_toboolean(L, -1);
  lua_pop(L, 1);

  const char *cafile = opt_string(L, 1, "cafile");
  const char *capath = opt_string(L, 1, "capath");
  const char *cert = opt_string(L, 1, "cert");
  const char *key = opt_string(L, 1, "key");

  struct curl_slist *headers = NULL;
  lua_getfield(L, 1, "headers");
  if (!lua_isnil(L, -1)) {
    luaL_checktype(L, -1, LUA_TTABLE);
    lua_Integer n = luaL_len(L, -1);
    for (lua_Integer i = 1; i <= n; i++) {
      lua_rawgeti(L, -1, i);
      if (lua_type(L, -1) != LUA_TSTRING) {
        curl_slist_free_all(headers);
        return luaL_error(L, "headers must be strings");
      }
      size_t len;
      const char *line = lua_tolstring(L, -1, &len);
      if (strlen(line) != len) {
        curl_slist_free_all(headers);
        return luaL_error(L, "header must not contain NUL bytes");
      }
      struct curl_slist *next = curl_slist_append(headers, line);
      lua_pop(L, 1);
      if (!next) {
        curl_slist_free_all(headers);
        return luaL_error(L, "out of memory");
      }
      headers = next;
    }
  }
  lua_pop(L, 1);

  if (!handle) handle = curl_easy_init();
  if (!handle) {
    curl_slist_free_all(headers);
    return luaL_error(L, "could not initialise libcurl");
  }
  curl_easy_reset(handle);

  buffer head = {0}, out = {0};
  char errbuf[CURL_ERROR_SIZE] = "";

  curl_easy_setopt(handle, CURLOPT_URL, url);
  curl_easy_setopt(handle, CURLOPT_PROTOCOLS_STR, "http,https");
  curl_easy_setopt(handle, CURLOPT_NOSIGNAL, 1L);
  curl_easy_setopt(handle, CURLOPT_ERRORBUFFER, errbuf);
  curl_easy_setopt(handle, CURLOPT_USERAGENT, "atlas");
  /* every encoding libcurl was built with, decoded transparently */
  curl_easy_setopt(handle, CURLOPT_ACCEPT_ENCODING, "");
  curl_easy_setopt(handle, CURLOPT_HTTPHEADER, headers);
  curl_easy_setopt(handle, CURLOPT_HEADERFUNCTION, on_header);
  curl_easy_setopt(handle, CURLOPT_HEADERDATA, &head);
  curl_easy_setopt(handle, CURLOPT_WRITEFUNCTION, on_body);
  curl_easy_setopt(handle, CURLOPT_WRITEDATA, &out);

  if (strcmp(method, "HEAD") == 0) {
    curl_easy_setopt(handle, CURLOPT_NOBODY, 1L);
  } else {
    curl_easy_setopt(handle, CURLOPT_CUSTOMREQUEST, method);
    if (body || strcmp(method, "POST") == 0 || strcmp(method, "PUT") == 0 ||
        strcmp(method, "PATCH") == 0) {
      curl_easy_setopt(handle, CURLOPT_POSTFIELDSIZE_LARGE, (curl_off_t)body_len);
      curl_easy_setopt(handle, CURLOPT_POSTFIELDS, body ? body : "");
    }
  }

  if (timeout > 0) {
    /* 0 ms would mean no limit: at least 1, and huge values kept in range */
    double ms = timeout * 1000;
    long limit = ms >= (double)LONG_MAX ? LONG_MAX : (long)ms;
    curl_easy_setopt(handle, CURLOPT_TIMEOUT_MS, limit < 1 ? 1L : limit);
  } else {
    /* no overall limit, but give up on a peer that stops answering */
    curl_easy_setopt(handle, CURLOPT_CONNECTTIMEOUT, 60L);
    curl_easy_setopt(handle, CURLOPT_LOW_SPEED_LIMIT, 1L);
    curl_easy_setopt(handle, CURLOPT_LOW_SPEED_TIME, 60L);
  }

  curl_easy_setopt(handle, CURLOPT_SSL_VERIFYPEER, verify ? 1L : 0L);
  curl_easy_setopt(handle, CURLOPT_SSL_VERIFYHOST, verify ? 2L : 0L);
  if (cafile) curl_easy_setopt(handle, CURLOPT_CAINFO, cafile);
  if (capath) curl_easy_setopt(handle, CURLOPT_CAPATH, capath);
  if (cert) curl_easy_setopt(handle, CURLOPT_SSLCERT, cert);
  if (key) curl_easy_setopt(handle, CURLOPT_SSLKEY, key);

  CURLcode rc = curl_easy_perform(handle);
  curl_slist_free_all(headers);
  /* the handle must not keep pointers to this call's stack */
  curl_easy_setopt(handle, CURLOPT_ERRORBUFFER, NULL);
  curl_easy_setopt(handle, CURLOPT_HTTPHEADER, NULL);

  if (rc != CURLE_OK) {
    lua_pushnil(L);
    lua_pushstring(L, errbuf[0] ? errbuf : curl_easy_strerror(rc));
    free(head.data);
    free(out.data);
    return 2;
  }

  long status = 0;
  curl_easy_getinfo(handle, CURLINFO_RESPONSE_CODE, &status);
  lua_pushinteger(L, status);
  lua_pushlstring(L, head.data ? head.data : "", head.len);
  lua_pushlstring(L, out.data ? out.data : "", out.len);
  free(head.data);
  free(out.data);
  return 3;
}

static int version(lua_State *L) {
  lua_pushstring(L, curl_version());
  return 1;
}

int luaopen_atlas_curl(lua_State *L) {
  curl_global_init(CURL_GLOBAL_DEFAULT);
  luaL_Reg fns[] = {{"perform", perform}, {"version", version}, {NULL, NULL}};
  luaL_newlib(L, fns);
  return 1;
}
