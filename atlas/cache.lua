local json = require("lunajson")
local function cache_dir()
  return ((os.getenv("HOME") or ".") .. "/.cache/atlas/schemas")
end
local function hash_url(url)
  local h = 5381
  for i = 1, #url do
    h = (((h * 31) + string.byte(url, i)) % 2147483647)
  end
  return string.format("%d", h)
end
local function cache_path(url)
  return (cache_dir() .. "/" .. hash_url(url) .. ".json")
end
local function get(url, ttl)
  local f = io.open(cache_path(url), "r")
  if f then
    local ok, data = pcall(json.decode, f:read("*a"))
    f:close()
    if (ok and data and (data.url == url) and ((os.time() - data.cached_at) < ttl)) then
      return data.schema
    else
      return nil
    end
  else
    return nil
  end
end
local function put(url, schema)
  local dir = cache_dir()
  os.execute(("mkdir -p '" .. dir:gsub("'", "'\\''") .. "'"))
  local f = io.open(cache_path(url), "w")
  if f then
    f:write(json.encode({url = url, cached_at = os.time(), schema = schema}))
    return f:close()
  else
    return nil
  end
end
return {get = get, put = put}
