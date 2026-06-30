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
local function make_operation(client_opts, path, method, op_spec)
  local param_names = util["extract-path-params"](path)
  local n_path = #param_names
  local has_body_3f = (nil ~= op_spec.requestBody)
  local fixed_headers
  do
    local tbl_21_ = {}
    for k, v in pairs({["content-type"] = negotiate["pick-content-type"](op_spec), accept = negotiate["pick-accept"](op_spec)}) do
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
  local function _21_(_, ...)
    return f(...)
  end
  return setmetatable({["fnl/docstring"] = doc.build(path, method, op_spec), ["cli/help"] = doc["build-cli"](path, method, op_spec), ["has-body?"] = has_body_3f, ["n-path"] = n_path}, {__call = _21_})
end
local function client(schema, _3fopts)
  local source_url
  local _22_
  if (type(schema) == "string") then
    _22_ = schema
  else
    _22_ = nil
  end
  local or_24_ = _22_
  if not or_24_ then
    local t_25_ = _3fopts
    if (nil ~= t_25_) then
      t_25_ = t_25_["source-url"]
    else
    end
    or_24_ = t_25_
  end
  source_url = or_24_
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
  local _30_
  do
    local t_29_ = _3fopts
    if (nil ~= t_29_) then
      t_29_ = t_29_["base-url"]
    else
    end
    _30_ = t_29_
  end
  local or_32_ = _30_
  if not or_32_ then
    if (server_url and server_url:match("^https?://")) then
      or_32_ = server_url
    else
      or_32_ = nil
    end
  end
  if not or_32_ then
    if (source_url and server_url and server_url:match("^/")) then
      local origin = source_url:match("^(https?://[^/]+)")
      or_32_ = (origin .. server_url)
    else
      or_32_ = nil
    end
  end
  base_url = (or_32_ or error("no base-url: schema servers URL is missing or unresolvable, pass :base-url in opts"))
  local client_opts
  local _37_
  do
    local t_36_ = _3fopts
    if (nil ~= t_36_) then
      t_36_ = t_36_["http-fn"]
    else
    end
    _37_ = t_36_
  end
  local _40_
  do
    local t_39_ = _3fopts
    if (nil ~= t_39_) then
      t_39_ = t_39_.headers
    else
    end
    _40_ = t_39_
  end
  local _43_
  do
    local t_42_ = _3fopts
    if (nil ~= t_42_) then
      t_42_ = t_42_.timeout
    else
    end
    _43_ = t_42_
  end
  local _46_
  do
    local t_45_ = _3fopts
    if (nil ~= t_45_) then
      t_45_ = t_45_.ssl
    else
    end
    _46_ = t_45_
  end
  client_opts = {["base-url"] = base_url, ["http-fn"] = (_37_ or http.request), headers = (_40_ or {}), timeout = _43_, ssl = _46_}
  local client0 = {}
  for path, methods in pairs((schema0.paths or {})) do
    for method, op_spec in pairs(methods) do
      if ((type(op_spec) == "table") and op_spec.operationId) then
        client0[util["camel->kebab"](op_spec.operationId)] = make_operation(client_opts, path, method, op_spec)
      else
      end
    end
  end
  return client0
end
return {client = client, ["load-schema"] = load_schema}
