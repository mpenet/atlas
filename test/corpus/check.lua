-- ABOUTME: Corpus check: loads real-world OpenAPI specs, builds clients and
-- ABOUTME: exercises every operation offline (names, help, URLs, invoke, checks).
local atlas = require("atlas")
local help = require("atlas.cli.help")
local request = require("atlas.cli.request")
local socket = require("socket")

local function stub(req) return {status = 200, headers = {}, body = {}, raw = "{}"} end

local files = {...}
local failed = false
for _, file in ipairs(files) do
  local t0 = socket.gettime()
  local ok, schema = pcall(atlas["load-schema"], file)
  local t_load = socket.gettime() - t0
  if not ok then
    failed = true
    print(string.format("%-18s LOAD FAILED: %s", file, tostring(schema)))
  else
    local t1 = socket.gettime()
    local cok, client = pcall(atlas.client, schema, {["base-url"] = "https://example.test", ["http-fn"] = stub, ["source-url"] = file})
    local t_client = socket.gettime() - t1
    if not cok then
      failed = true
      print(string.format("%-18s CLIENT FAILED: %s", file, tostring(client)))
    else
      local n, errors, names, t2 = 0, {}, {}, socket.gettime()
      for name, op in pairs(client) do
        n = n + 1
        local function check(what, f)
          local fok, err = pcall(f)
          if not fok then
            errors[what] = errors[what] or {count = 0, first = name .. ": " .. tostring(err)}
            errors[what].count = errors[what].count + 1
          end
        end
        check("name", function() assert(op.name == name and name:match("^[a-z0-9]+[a-z0-9%-]*$"), "bad name " .. name) end)
        check("docstring", function() assert(type(op["fnl/docstring"]) == "string") end)
        check("cli-help", function() assert(type(help["build-cli"](op.path, op.method, op.spec)) == "string") end)
        local path = {}
        for _, p in ipairs(op["path-params"]) do path[p] = "x y/1" end
        check("url-for", function() assert(op["url-for"]({path = path, query = {a = "1"}}):match("^https://example%.test/")) end)
        check("invoke", function() op.invoke({path = path, body = op["has-body"] and {} or nil}) end)
        check("check-params", function() request["check-params"](op, {query = {}, headers = {}}) end)
        check("check-body", function() if op["has-body"] then request["check-body"](op, "{}") end end)
      end
      local t_ops = socket.gettime() - t2
      print(string.format("%-18s ops=%-5d load=%.2fs client=%.2fs ops=%.2fs", file, n, t_load, t_client, t_ops))
      for what, e in pairs(errors) do
        failed = true
        print(string.format("    %s x%d  first: %s", what, e.count, e.first:sub(1, 300)))
      end
    end
  end
end

os.exit(failed and 1 or 0)
