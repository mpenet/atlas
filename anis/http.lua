local socket_http = require("socket.http")
local https = require("ssl.https")
local ltn12 = require("ltn12")
local json = require("lunajson")
local function url_encode(s)
  local function _1_(c)
    return string.format("%%%02X", string.byte(c))
  end
  return tostring(s)("gsub", "[^%w%-%.%_%~]", _1_)
end
local function encode_query(params)
  if params then
    local parts = {}
    for k, v in pairs(params) do
      table.insert(parts, (url_encode(k) .. "=" .. url_encode(v)))
    end
    if (#parts > 0) then
      return table.concat(parts, "&")
    else
      return nil
    end
  else
    return nil
  end
end
local function build_url(url, query)
  local qs = encode_query(query)
  if qs then
    return (url .. "?" .. qs)
  else
    return url
  end
end
local function request(req)
  local url = build_url(req.url, req.query)
  local requester
  if url:match("^https://") then
    requester = https
  else
    requester = socket_http
  end
  local payload
  if req.body then
    payload = json.encode(req.body)
  else
    payload = nil
  end
  local headers
  do
    local tbl_16_ = {}
    for k, v in pairs((req.headers or {})) do
      local k_17_, v_18_ = k, v
      if ((k_17_ ~= nil) and (v_18_ ~= nil)) then
        tbl_16_[k_17_] = v_18_
      else
      end
    end
    headers = tbl_16_
  end
  local body_out = {}
  if payload then
    headers["content-length"] = tostring(#payload)
  else
  end
  local req_table
  local _9_
  if payload then
    _9_ = ltn12.source.string(payload)
  else
    _9_ = nil
  end
  req_table = {url = url, method = req.method, headers = headers, timeout = req.timeout, source = _9_, sink = ltn12.sink.table(body_out)}
  if (req.ssl and url:match("^https://")) then
    for k, v in pairs(req.ssl) do
      req_table[k] = v
    end
  else
  end
  local ok, code, resp_headers = requester.request(req_table)
  assert(ok, tostring(code))
  local raw = table.concat(body_out)
  local _12_
  if (#raw > 0) then
    _12_ = json.decode(raw)
  else
    _12_ = nil
  end
  return {status = code, headers = resp_headers, body = _12_}
end
return {request = request}
