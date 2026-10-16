rockspec_format = "3.0"
package = "atlas-oai"
version = "dev-1"

source = {
  url = "git+https://github.com/mpenet/atlas",
}

description = {
  summary = "OpenAPI 3.x client and CLI toolbox for Fennel/Lua",
  detailed = [[
    Dynamically builds a callable client from any OpenAPI 3.x schema at runtime
    (file path, URL, or parsed table; JSON or YAML). No code generation required.
    Also ships a standalone CLI (atlas) similar to Restish, with profiles,
    OAuth 2.0, mTLS, schema caching, and shell completion. HTTP goes through
    libcurl.
  ]],
  license = "MPL-2.0",
  homepage = "https://github.com/mpenet/atlas",
}

dependencies = {
  "lua >= 5.4",
  "lunajson",
  "luasocket",
  "lyaml",
}

build_dependencies = {
  "fennel",
}

external_dependencies = {
  CURL = { header = "curl/curl.h" },
}

build = {
  -- sources are Fennel; compile them, then install the generated Lua
  type = "command",
  -- needs the fennel executable on PATH (the build dependency's tree bin dir)
  build_command = "make build LUA_INC=$(LUA_INCDIR) CURL_CFLAGS=-I$(CURL_INCDIR) 'CURL_LIBS=-L$(CURL_LIBDIR) -lcurl'",
  install = {
    lua = {
      ["atlas"]           = "lua/atlas.lua",
      ["atlas.auth"]      = "lua/atlas/auth.lua",
      ["atlas.cache"]     = "lua/atlas/cache.lua",
      ["atlas.cli"]       = "lua/atlas/cli.lua",
      ["atlas.cli.args"]  = "lua/atlas/cli/args.lua",
      ["atlas.cli.complete"] = "lua/atlas/cli/complete.lua",
      ["atlas.cli.help"]  = "lua/atlas/cli/help.lua",
      ["atlas.cli.mcp"] = "lua/atlas/cli/mcp.lua",
      ["atlas.cli.output"] = "lua/atlas/cli/output.lua",
      ["atlas.cli.width"] = "lua/atlas/cli/width.lua",
      ["atlas.cli.progress"] = "lua/atlas/cli/progress.lua",
      ["atlas.cli.plugins"] = "lua/atlas/cli/plugins.lua",
      ["atlas.arazzo.check"] = "lua/atlas/arazzo/check.lua",
      ["atlas.unicode-categories"] = "lua/atlas/unicode-categories.lua",
      ["atlas.iregexp"] = "lua/atlas/iregexp.lua",
      ["atlas.jsonpath"] = "lua/atlas/jsonpath.lua",
      ["atlas.cli.request"] = "lua/atlas/cli/request.lua",
      ["atlas.cli.restish"] = "lua/atlas/cli/restish.lua",
      ["atlas.cli.settings"] = "lua/atlas/cli/settings.lua",
      ["atlas.coerce"]    = "lua/atlas/coerce.lua",
      ["atlas.digest"]    = "lua/atlas/digest.lua",
      ["atlas.doc"]       = "lua/atlas/doc.lua",
      ["atlas.http"]      = "lua/atlas/http.lua",
      ["atlas.json"] = "lua/atlas/json.lua",
      ["atlas.negotiate"] = "lua/atlas/negotiate.lua",
      ["atlas.paginate"]  = "lua/atlas/paginate.lua",
      ["atlas.pretty"]    = "lua/atlas/pretty.lua",
      ["atlas.refs"]      = "lua/atlas/refs.lua",
      ["atlas.retry"]     = "lua/atlas/retry.lua",
      ["atlas.tls"] = "lua/atlas/tls.lua",
      ["atlas.util"]      = "lua/atlas/util.lua",
      ["atlas.validate"]  = "lua/atlas/validate.lua",
      ["atlas.arazzo"]    = "lua/atlas/arazzo.lua",
      ["atlas.arazzo.expr"] = "lua/atlas/arazzo/expr.lua",
      ["atlas.yaml"]      = "lua/atlas/yaml.lua",
    },
    lib = { ["atlas.curl"] = "lua/atlas/curl.so" },
    bin = { atlas = "bin/atlas" },
  },
}
