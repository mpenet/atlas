local socket_http = require("socket.http")
local https = require("ssl.https")
local ltn12 = require("ltn12")
local json = require("lunajson")
local function url_encode(s)
  local function _1_(c)
    return string.format("%%%02X", string.byte(c))
  end
  return tostring(s):gsub("[^%w%-%.%_%~]", _1_)
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
  local ok_enc, payload
  if req["raw-body"] then
    ok_enc, payload = true, req["raw-body"]
  else
    if req.body then
      ok_enc, payload = pcall(json.encode, req.body)
    else
      ok_enc, payload = true, nil
    end
  end
  assert(ok_enc, string.format("failed to encode request body: %s", tostring(payload)))
  local headers
  do
    local tbl_21_ = {}
    for k, v in pairs((req.headers or {})) do
      local k_22_, v_23_ = k, v
      if ((k_22_ ~= nil) and (v_23_ ~= nil)) then
        tbl_21_[k_22_] = v_23_
      else
      end
    end
    headers = tbl_21_
  end
  local body_out = {}
  if payload then
    headers["content-length"] = tostring(#payload)
  else
  end
  local req_table
  if (req.ssl and url:match("^https://")) then
    local tbl_21_ = {}
    for k, v in pairs(req.ssl) do
      local k_22_, v_23_ = k, v
      if ((k_22_ ~= nil) and (v_23_ ~= nil)) then
        tbl_21_[k_22_] = v_23_
      else
      end
    end
    req_table = tbl_21_
  else
    req_table = {}
  end
  req_table["url"] = url
  req_table["method"] = req.method
  req_table["headers"] = headers
  req_table["timeout"] = req.timeout
  local _12_
  if payload then
    _12_ = ltn12.source.string(payload)
  else
    _12_ = nil
  end
  req_table["source"] = _12_
  req_table["sink"] = ltn12.sink.table(body_out)
  local ok, code, resp_headers = requester.request(req_table)
  assert(ok, string.format("%s %s failed: %s", req.method, url, tostring(code)))
  local raw = table.concat(body_out)
  local body
  if (#raw > 0) then
    local ok0, val = pcall(json.decode, raw)
    if ok0 then
      body = val
    else
      body = raw
    end
  else
    body = nil
  end
  return {status = code, headers = resp_headers, body = body}
end
return {request = request}
