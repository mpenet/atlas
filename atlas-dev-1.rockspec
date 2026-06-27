rockspec_format = "3.0"
package = "atlas"
version = "dev-1"

source = {
  url = "git+https://github.com/mpenet/atlas",
}

description = {
  summary = "Runtime OpenAPI client for Fennel",
  detailed = "Dynamically builds a client from any OpenAPI 3.x schema at runtime. No code generation.",
  license = "MIT",
  homepage = "https://github.com/mpenet/atlas",
}

dependencies = {
  "lua >= 5.1",
  "lunajson",
  "luasocket",
  "luasec",
}

build = {
  type = "builtin",
  modules = {
    ["atlas"]           = "atlas.lua",
    ["atlas.util"]      = "atlas/util.lua",
    ["atlas.negotiate"] = "atlas/negotiate.lua",
    ["atlas.doc"]       = "atlas/doc.lua",
    ["atlas.http"]      = "atlas/http.lua",
    ["atlas.pretty"]    = "atlas/pretty.lua",
    ["atlas.cli"]       = "atlas/cli.lua",
  },
  install = {
    bin = { "bin/atlas" },
  },
}
