local util = require("atlas.util")
local negotiate = require("atlas.negotiate")
local doc = require("atlas.doc")
local json = require("lunajson")
local http = require("atlas.http")
local ltn12 = require("ltn12")
local socket_http = require("socket.http")
local https = require("ssl.https")
local function load_schema(path)
  local content
  if path:match("^https?://") then
    local requester
    if path:match("^https://") then
      requester = https
    else
      requester = socket_http
    end
    local body_out = {}
    local ok, code = requester.request({url = path, method = "GET", sink = ltn12.sink.table(body_out)})
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
  local ok, parsed, err = pcall(json.decode, content)
  assert(ok, string.format("failed to parse schema JSON from '%s': %s", path, tostring(err)))
  return parsed
end
local function make_operation(client, path, method, op_spec)
  local param_names = util["extract-path-params"](path)
  local n_path = #param_names
  local has_body_3f = (nil ~= op_spec.requestBody)
  local ct = negotiate["pick-content-type"](op_spec)
  local accept = negotiate["pick-accept"](op_spec)
  local n_opts
  local _3_
  if has_body_3f then
    _3_ = 2
  else
    _3_ = 1
  end
  n_opts = (n_path + _3_)
  local f
  local function _5_(...)
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
    local _9_
    do
      local t_8_ = opts
      if (nil ~= t_8_) then
        t_8_ = t_8_.headers
      else
      end
      _9_ = t_8_
    end
    for k, v in pairs((_9_ or {})) do
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
    local _14_
    do
      local t_13_ = opts
      if (nil ~= t_13_) then
        t_13_ = t_13_.query
      else
      end
      _14_ = t_13_
    end
    local _17_
    do
      local t_16_ = opts
      if (nil ~= t_16_) then
        t_16_ = t_16_.timeout
      else
      end
      _17_ = t_16_
    end
    return client["http-fn"]({method = method:upper(), url = url, query = _14_, body = body, headers = headers, timeout = (_17_ or client.timeout), ssl = client.ssl})
  end
  f = _5_
  local function _19_(_, ...)
    return f(...)
  end
  return setmetatable({["fnl/docstring"] = doc.build(path, method, op_spec), ["has-body?"] = has_body_3f, ["n-path"] = n_path}, {__call = _19_})
end
local function client(schema, _3fopts)
  local source_url
  local _20_
  if (type(schema) == "string") then
    _20_ = schema
  else
    _20_ = nil
  end
  local or_22_ = _20_
  if not or_22_ then
    local t_23_ = _3fopts
    if (nil ~= t_23_) then
      t_23_ = t_23_["source-url"]
    else
    end
    or_22_ = t_23_
  end
  source_url = or_22_
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
  local _28_
  do
    local t_27_ = _3fopts
    if (nil ~= t_27_) then
      t_27_ = t_27_["base-url"]
    else
    end
    _28_ = t_27_
  end
  local or_30_ = _28_
  if not or_30_ then
    if (server_url and server_url:match("^https?://")) then
      or_30_ = server_url
    else
      or_30_ = nil
    end
  end
  if not or_30_ then
    if (source_url and server_url and server_url:match("^/")) then
      local origin = source_url:match("^(https?://[^/]+)")
      or_30_ = (origin .. server_url)
    else
      or_30_ = nil
    end
  end
  base_url = (or_30_ or error("no base-url: schema servers URL is missing or unresolvable, pass :base-url in opts"))
  local client0
  local _35_
  do
    local t_34_ = _3fopts
    if (nil ~= t_34_) then
      t_34_ = t_34_["http-fn"]
    else
    end
    _35_ = t_34_
  end
  local _38_
  do
    local t_37_ = _3fopts
    if (nil ~= t_37_) then
      t_37_ = t_37_.headers
    else
    end
    _38_ = t_37_
  end
  local _41_
  do
    local t_40_ = _3fopts
    if (nil ~= t_40_) then
      t_40_ = t_40_.timeout
    else
    end
    _41_ = t_40_
  end
  local _44_
  do
    local t_43_ = _3fopts
    if (nil ~= t_43_) then
      t_43_ = t_43_.ssl
    else
    end
    _44_ = t_43_
  end
  client0 = {["base-url"] = base_url, ["http-fn"] = (_35_ or http.request), headers = (_38_ or {}), timeout = _41_, ssl = _44_}
  for path, methods in pairs(schema0.paths) do
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
