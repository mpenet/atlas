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
    (file path, URL, or parsed table). No code generation required. Also ships
    a standalone CLI (atlas) similar to Restish, with profiles, OAuth 2.0,
    mTLS, schema caching, and shell completion.
  ]],
  license = "MPL-2.0",
  homepage = "https://github.com/mpenet/atlas",
}

dependencies = {
  "lua >= 5.4",
  "lunajson",
  "luasocket",
  "luasec",
}

build = {
  type = "builtin",
  modules = {
    ["atlas"]           = "atlas.lua",
    ["atlas.auth"]      = "atlas/auth.lua",
    ["atlas.cache"]     = "atlas/cache.lua",
    ["atlas.cli"]       = "atlas/cli.lua",
    ["atlas.doc"]       = "atlas/doc.lua",
    ["atlas.http"]      = "atlas/http.lua",
    ["atlas.negotiate"] = "atlas/negotiate.lua",
    ["atlas.pretty"]    = "atlas/pretty.lua",
    ["atlas.util"]      = "atlas/util.lua",
  },
  install = {
    bin = { "bin/atlas" },
  },
}
