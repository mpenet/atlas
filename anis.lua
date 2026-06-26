local util = require("anis.util")
local negotiate = require("anis.negotiate")
local doc = require("anis.doc")
local json = require("lunajson")
local http = require("anis.http")
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
    assert(ok, tostring(code))
    assert(((code >= 200) and (code < 300)), string.format("HTTP %s fetching schema from %s", code, path))
    content = table.concat(body_out)
  else
    local f = assert(io.open(path, "r"))
    local c = f:read("*a")
    f:close()
    content = c
  end
  return json.decode(content)
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
      local tbl_16_ = {}
      for k, v in pairs((client.headers or {})) do
        local k_17_, v_18_ = k, v
        if ((k_17_ ~= nil) and (v_18_ ~= nil)) then
          tbl_16_[k_17_] = v_18_
        else
        end
      end
      headers = tbl_16_
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
  if (type(schema) == "string") then
    source_url = schema
  else
    source_url = nil
  end
  local schema0
  if source_url then
    schema0 = load_schema(source_url)
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
  local _24_
  do
    local t_23_ = _3fopts
    if (nil ~= t_23_) then
      t_23_ = t_23_["base-url"]
    else
    end
    _24_ = t_23_
  end
  local or_26_ = _24_
  if not or_26_ then
    if (server_url and server_url:match("^https?://")) then
      or_26_ = server_url
    else
      or_26_ = nil
    end
  end
  if not or_26_ then
    if (source_url and server_url and server_url:match("^/")) then
      local origin = source_url:match("^(https?://[^/]+)")
      or_26_ = (origin .. server_url)
    else
      or_26_ = nil
    end
  end
  base_url = (or_26_ or error("no base-url: schema servers URL is missing or unresolvable, pass :base-url in opts"))
  local client0
  local _31_
  do
    local t_30_ = _3fopts
    if (nil ~= t_30_) then
      t_30_ = t_30_["http-fn"]
    else
    end
    _31_ = t_30_
  end
  local _34_
  do
    local t_33_ = _3fopts
    if (nil ~= t_33_) then
      t_33_ = t_33_.headers
    else
    end
    _34_ = t_33_
  end
  local _37_
  do
    local t_36_ = _3fopts
    if (nil ~= t_36_) then
      t_36_ = t_36_.timeout
    else
    end
    _37_ = t_36_
  end
  local _40_
  do
    local t_39_ = _3fopts
    if (nil ~= t_39_) then
      t_39_ = t_39_.ssl
    else
    end
    _40_ = t_39_
  end
  client0 = {["base-url"] = base_url, ["http-fn"] = (_31_ or http.request), headers = (_34_ or {}), timeout = _37_, ssl = _40_}
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
return {client = client}
