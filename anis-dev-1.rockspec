rockspec_format = "3.0"
package = "anis"
version = "dev-1"

source = {
  url = "git+https://github.com/mpenet/anis",
}

description = {
  summary = "Runtime OpenAPI client for Fennel",
  detailed = "Dynamically builds a client from any OpenAPI 3.x schema at runtime. No code generation.",
  license = "MIT",
  homepage = "https://github.com/mpenet/anis",
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
    ["anis"]          = "anis.lua",
    ["anis.util"]     = "anis/util.lua",
    ["anis.negotiate"] = "anis/negotiate.lua",
    ["anis.doc"]      = "anis/doc.lua",
    ["anis.http"]     = "anis/http.lua",
  },
}
