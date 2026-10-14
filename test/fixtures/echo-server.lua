-- ABOUTME: One-shot HTTP server for transport specs: prints its port, then
-- ABOUTME: answers N requests with JSON describing each request it received.
local socket = require("socket")
local count = tonumber(arg[1]) or 1
local srv = assert(socket.bind("127.0.0.1", 0))
local _, port = srv:getsockname()
io.write(port, "\n")
io.flush()
srv:settimeout(10)
for _ = 1, count do
  local conn = assert(srv:accept())
  conn:settimeout(5)
  local line = conn:receive("*l")
  local method, path = line:match("^(%S+) (%S+)")
  local headers = {}
  while true do
    local h = conn:receive("*l")
    if h == nil or h == "" then break end
    local k, v = h:match("^([^:]+):%s*(.*)$")
    if k then headers[k:lower()] = v end
  end
  local n = tonumber(headers["content-length"] or "0")
  local body = n > 0 and conn:receive(n) or ""
  local function q(s) return '"' .. s:gsub('[%c"\\]', function(c) return string.format("\\u%04x", c:byte()) end) .. '"' end
  local payload = "{\"method\":" .. q(method) .. ",\"path\":" .. q(path)
    .. ",\"body\":" .. q(body) .. ",\"content_type\":" .. q(headers["content-type"] or "") .. "}"
  conn:send("HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: "
    .. #payload .. "\r\nConnection: close\r\n\r\n" .. payload)
  conn:close()
end
srv:close()
