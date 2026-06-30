local util = require("atlas.util")
local negotiate = require("atlas.negotiate")
local doc = require("atlas.doc")
local json = require("lunajson")
local http = require("atlas.http")
local ltn12 = require("ltn12")
local socket_http = require("socket.http")
local https = require("ssl.https")
local function load_schema(path, _3fssl, _3fheaders)
  local content
  if path:match("^https?://") then
    local requester
    if path:match("^https://") then
      requester = https
    else
      requester = socket_http
    end
    local body_out = {}
    local req
    if (_3fssl and path:match("^https://")) then
      local tbl_21_ = {}
      for k, v in pairs(_3fssl) do
        local k_22_, v_23_ = k, v
        if ((k_22_ ~= nil) and (v_23_ ~= nil)) then
          tbl_21_[k_22_] = v_23_
        else
        end
      end
      req = tbl_21_
    else
      req = {}
    end
    req["url"] = path
    req["method"] = "GET"
    req["headers"] = (_3fheaders or {})
    req["sink"] = ltn12.sink.table(body_out)
    local ok, code = requester.request(req)
    assert(ok, string.format("failed to fetch schema from %s: %s", path, tostring(code)))
    assert(((code >= 200) and (code < 300)), string.format("HTTP %s fetching schema from %s", code, path))
    content = table.concat(body_out)
  else
    local f, err = io.open(path, "r")
    assert(f, string.format("failed to open schema file '%s': %s", path, tostring(err)))
    local c = f:read("*a")
    f:close()
    content = c
  end
  local ok, parsed = pcall(json.decode, content)
  assert(ok, string.format("failed to parse schema JSON from '%s': %s", path, tostring(parsed)))
  return parsed
end
local function make_operation(client_opts, root_schema, path, method, op_spec)
  local op_spec0 = util["deref-deep"](root_schema, op_spec)
  local param_names = util["extract-path-params"](path)
  local n_path = #param_names
  local has_body_3f = (nil ~= op_spec0.requestBody)
  local fixed_headers
  do
    local tbl_21_ = {}
    for k, v in pairs({["content-type"] = negotiate["pick-content-type"](op_spec0), accept = negotiate["pick-accept"](op_spec0)}) do
      local k_22_, v_23_
      if v then
        k_22_, v_23_ = k, v
      else
        k_22_, v_23_ = nil
      end
      if ((k_22_ ~= nil) and (v_23_ ~= nil)) then
        tbl_21_[k_22_] = v_23_
      else
      end
    end
    fixed_headers = tbl_21_
  end
  local n_opts
  local _7_
  if has_body_3f then
    _7_ = 2
  else
    _7_ = 1
  end
  n_opts = (n_path + _7_)
  local f
  local function _9_(...)
    local args = {...}
    local url = (client_opts["base-url"] .. util["resolve-path"](path, args))
    local body
    if has_body_3f then
      body = args[(n_path + 1)]
    else
      body = nil
    end
    local opts = args[n_opts]
    local headers
    do
      local tbl_21_ = {}
      for k, v in pairs((client_opts.headers or {})) do
        local k_22_, v_23_ = k, v
        if ((k_22_ ~= nil) and (v_23_ ~= nil)) then
          tbl_21_[k_22_] = v_23_
        else
        end
      end
      headers = tbl_21_
    end
    local _13_
    do
      local t_12_ = opts
      if (nil ~= t_12_) then
        t_12_ = t_12_.headers
      else
      end
      _13_ = t_12_
    end
    for k, v in pairs((_13_ or {})) do
      headers[k] = v
    end
    for k, v in pairs(fixed_headers) do
      headers[k] = v
    end
    local _16_
    do
      local t_15_ = opts
      if (nil ~= t_15_) then
        t_15_ = t_15_.query
      else
      end
      _16_ = t_15_
    end
    local _19_
    do
      local t_18_ = opts
      if (nil ~= t_18_) then
        t_18_ = t_18_.timeout
      else
      end
      _19_ = t_18_
    end
    return client_opts["http-fn"]({method = method:upper(), url = url, query = _16_, body = body, headers = headers, timeout = (_19_ or client_opts.timeout), ssl = client_opts.ssl})
  end
  f = _9_
  local _21_
  do
    local s = op_spec0.summary
    local d = op_spec0.description
    if (s and (s ~= "")) then
      _21_ = s
    elseif (d and (d ~= "")) then
      _21_ = d
    else
      _21_ = nil
    end
  end
  local function _23_(_, ...)
    return f(...)
  end
  return setmetatable({["fnl/docstring"] = doc.build(path, method, op_spec0), ["cli/help"] = doc["build-cli"](path, method, op_spec0), summary = _21_, ["has-body?"] = has_body_3f, ["n-path"] = n_path}, {__call = _23_})
end
local function client(schema, _3fopts)
  local source_url
  local _24_
  if (type(schema) == "string") then
    _24_ = schema
  else
    _24_ = nil
  end
  local or_26_ = _24_
  if not or_26_ then
    local t_27_ = _3fopts
    if (nil ~= t_27_) then
      t_27_ = t_27_["source-url"]
    else
    end
    or_26_ = t_27_
  end
  source_url = or_26_
  local schema0
  if (type(schema) == "string") then
    schema0 = load_schema(schema)
  else
    schema0 = schema
  end
  local server = (schema0.servers and schema0.servers[1])
  local server_url
  if server then
    local u = server.url
    for k, v in pairs((server.variables or {})) do
      u = u:gsub(("{" .. k .. "}"), v.default)
    end
    server_url = u
  else
    server_url = nil
  end
  local base_url
  local _32_
  do
    local t_31_ = _3fopts
    if (nil ~= t_31_) then
      t_31_ = t_31_["base-url"]
    else
    end
    _32_ = t_31_
  end
  local or_34_ = _32_
  if not or_34_ then
    if (server_url and server_url:match("^https?://")) then
      or_34_ = server_url
    else
      or_34_ = nil
    end
  end
  if not or_34_ then
    if (source_url and server_url and server_url:match("^/")) then
      local origin = source_url:match("^(https?://[^/]+)")
      or_34_ = (origin .. server_url)
    else
      or_34_ = nil
    end
  end
  base_url = (or_34_ or error("no base-url: schema servers URL is missing or unresolvable, pass :base-url in opts"))
  local client_opts
  local _39_
  do
    local t_38_ = _3fopts
    if (nil ~= t_38_) then
      t_38_ = t_38_["http-fn"]
    else
    end
    _39_ = t_38_
  end
  local _42_
  do
    local t_41_ = _3fopts
    if (nil ~= t_41_) then
      t_41_ = t_41_.headers
    else
    end
    _42_ = t_41_
  end
  local _45_
  do
    local t_44_ = _3fopts
    if (nil ~= t_44_) then
      t_44_ = t_44_.timeout
    else
    end
    _45_ = t_44_
  end
  local _48_
  do
    local t_47_ = _3fopts
    if (nil ~= t_47_) then
      t_47_ = t_47_.ssl
    else
    end
    _48_ = t_47_
  end
  client_opts = {["base-url"] = base_url, ["http-fn"] = (_39_ or http.request), headers = (_42_ or {}), timeout = _45_, ssl = _48_}
  local client0 = {}
  for path, methods in pairs((schema0.paths or {})) do
    for method, op_spec in pairs(methods) do
      if ((type(op_spec) == "table") and op_spec.operationId) then
        client0[util["camel->kebab"](op_spec.operationId)] = make_operation(client_opts, schema0, path, method, op_spec)
      else
      end
    end
  end
  return client0
end
return {client = client, ["load-schema"] = load_schema}
