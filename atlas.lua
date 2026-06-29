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
    local req = {url = path, method = "GET", headers = (_3fheaders or {}), sink = ltn12.sink.table(body_out)}
    if (_3fssl and path:match("^https://")) then
      for k, v in pairs(_3fssl) do
        req[k] = v
      end
    else
    end
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
local function make_operation(client, path, method, op_spec)
  local param_names = util["extract-path-params"](path)
  local n_path = #param_names
  local has_body_3f = (nil ~= op_spec.requestBody)
  local ct = negotiate["pick-content-type"](op_spec)
  local accept = negotiate["pick-accept"](op_spec)
  local n_opts
  local _4_
  if has_body_3f then
    _4_ = 2
  else
    _4_ = 1
  end
  n_opts = (n_path + _4_)
  local f
  local function _6_(...)
    local args = {...}
    local url = (client["base-url"] .. util["resolve-path"](path, args))
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
      for k, v in pairs((client.headers or {})) do
        local k_22_, v_23_ = k, v
        if ((k_22_ ~= nil) and (v_23_ ~= nil)) then
          tbl_21_[k_22_] = v_23_
        else
        end
      end
      headers = tbl_21_
    end
    local _10_
    do
      local t_9_ = opts
      if (nil ~= t_9_) then
        t_9_ = t_9_.headers
      else
      end
      _10_ = t_9_
    end
    for k, v in pairs((_10_ or {})) do
      headers[k] = v
    end
    if ct then
      headers["content-type"] = ct
    else
    end
    if accept then
      headers["accept"] = accept
    else
    end
    local _15_
    do
      local t_14_ = opts
      if (nil ~= t_14_) then
        t_14_ = t_14_.query
      else
      end
      _15_ = t_14_
    end
    local _18_
    do
      local t_17_ = opts
      if (nil ~= t_17_) then
        t_17_ = t_17_.timeout
      else
      end
      _18_ = t_17_
    end
    return client["http-fn"]({method = method:upper(), url = url, query = _15_, body = body, headers = headers, timeout = (_18_ or client.timeout), ssl = client.ssl})
  end
  f = _6_
  local function _20_(_, ...)
    return f(...)
  end
  return setmetatable({["fnl/docstring"] = doc.build(path, method, op_spec), ["has-body?"] = has_body_3f, ["n-path"] = n_path}, {__call = _20_})
end
local function client(schema, _3fopts)
  local source_url
  local _21_
  if (type(schema) == "string") then
    _21_ = schema
  else
    _21_ = nil
  end
  local or_23_ = _21_
  if not or_23_ then
    local t_24_ = _3fopts
    if (nil ~= t_24_) then
      t_24_ = t_24_["source-url"]
    else
    end
    or_23_ = t_24_
  end
  source_url = or_23_
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
  local _29_
  do
    local t_28_ = _3fopts
    if (nil ~= t_28_) then
      t_28_ = t_28_["base-url"]
    else
    end
    _29_ = t_28_
  end
  local or_31_ = _29_
  if not or_31_ then
    if (server_url and server_url:match("^https?://")) then
      or_31_ = server_url
    else
      or_31_ = nil
    end
  end
  if not or_31_ then
    if (source_url and server_url and server_url:match("^/")) then
      local origin = source_url:match("^(https?://[^/]+)")
      or_31_ = (origin .. server_url)
    else
      or_31_ = nil
    end
  end
  base_url = (or_31_ or error("no base-url: schema servers URL is missing or unresolvable, pass :base-url in opts"))
  local client0
  local _36_
  do
    local t_35_ = _3fopts
    if (nil ~= t_35_) then
      t_35_ = t_35_["http-fn"]
    else
    end
    _36_ = t_35_
  end
  local _39_
  do
    local t_38_ = _3fopts
    if (nil ~= t_38_) then
      t_38_ = t_38_.headers
    else
    end
    _39_ = t_38_
  end
  local _42_
  do
    local t_41_ = _3fopts
    if (nil ~= t_41_) then
      t_41_ = t_41_.timeout
    else
    end
    _42_ = t_41_
  end
  local _45_
  do
    local t_44_ = _3fopts
    if (nil ~= t_44_) then
      t_44_ = t_44_.ssl
    else
    end
    _45_ = t_44_
  end
  client0 = {["base-url"] = base_url, ["http-fn"] = (_36_ or http.request), headers = (_39_ or {}), timeout = _42_, ssl = _45_}
  for path, methods in pairs((schema0.paths or {})) do
    for method, op_spec in pairs(methods) do
      if ((type(op_spec) == "table") and op_spec.operationId) then
        client0[util["camel->kebab"](op_spec.operationId)] = make_operation(client0, path, method, op_spec)
      else
      end
    end
  end
  return client0
end
return {client = client, ["load-schema"] = load_schema}
