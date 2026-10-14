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
    OAuth 2.0, mTLS, schema caching, and shell completion.
  ]],
  license = "MPL-2.0",
  homepage = "https://github.com/mpenet/atlas",
}

dependencies = {
  "lua >= 5.4",
  "lunajson",
  "luasocket",
  "luasec",
  "lyaml",
}

build = {
  type = "builtin",
  modules = {
    ["atlas"]           = "lua/atlas.lua",
    ["atlas.auth"]      = "lua/atlas/auth.lua",
    ["atlas.cache"]     = "lua/atlas/cache.lua",
    ["atlas.cli"]       = "lua/atlas/cli.lua",
    ["atlas.cli.args"]  = "lua/atlas/cli/args.lua",
    ["atlas.cli.complete"] = "lua/atlas/cli/complete.lua",
    ["atlas.cli.output"] = "lua/atlas/cli/output.lua",
    ["atlas.cli.request"] = "lua/atlas/cli/request.lua",
    ["atlas.cli.settings"] = "lua/atlas/cli/settings.lua",
    ["atlas.coerce"]    = "lua/atlas/coerce.lua",
    ["atlas.digest"]    = "lua/atlas/digest.lua",
    ["atlas.doc"]       = "lua/atlas/doc.lua",
    ["atlas.http"]      = "lua/atlas/http.lua",
    ["atlas.negotiate"] = "lua/atlas/negotiate.lua",
    ["atlas.paginate"]  = "lua/atlas/paginate.lua",
    ["atlas.pretty"]    = "lua/atlas/pretty.lua",
    ["atlas.retry"]     = "lua/atlas/retry.lua",
    ["atlas.util"]      = "lua/atlas/util.lua",
    ["atlas.validate"]  = "lua/atlas/validate.lua",
    ["atlas.arazzo"]    = "lua/atlas/arazzo.lua",
    ["atlas.arazzo.expr"] = "lua/atlas/arazzo/expr.lua",
    ["atlas.yaml"]      = "lua/atlas/yaml.lua",
  },
  install = {
    bin = { "bin/atlas" },
  },
}
