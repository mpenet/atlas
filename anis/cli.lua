local anis = require("anis")
local json = require("lunajson")
local pretty_mod = require("anis.pretty")
local function config_path()
  return ((os.getenv("HOME") or ".") .. "/.config/anis/config.json")
end
local function load_config()
  local f = io.open(config_path(), "r")
  if f then
    local cfg = json.decode(f:read("*a"))
    f:close()
    return cfg
  else
    return {}
  end
end
local function parse_args(args)
  local r = {["path-params"] = {}, query = {}, headers = {}}
  local i = 1
  while (i <= #args) do
    do
      local a = args[i]
      if a:match("^%-%-query%.(.-)=(.+)") then
        local k, v = a:match("^%-%-query%.(.-)=(.+)")
        r.query[k] = v
      elseif a:match("^%-%-header%.(.-)=(.+)") then
        local k, v = a:match("^%-%-header%.(.-)=(.+)")
        r.headers[k] = v
      elseif a:match("^%-%-body=(.*)") then
        local v = a:match("^%-%-body=(.*)")
        r["body"] = json.decode(v)
      elseif (a == "-d") then
        i = (i + 1)
        r["body"] = json.decode(args[i])
      elseif a:match("^%-%-timeout=(.+)") then
        local v = a:match("^%-%-timeout=(.+)")
        r["timeout"] = tonumber(v)
      elseif a:match("^%-%-base%-url=(.+)") then
        local v = a:match("^%-%-base%-url=(.+)")
        r["base-url"] = v
      elseif a:match("^%-%-output=(.+)") then
        local v = a:match("^%-%-output=(.+)")
        r["output"] = v
      elseif (a == "--list") then
        r["list"] = true
      elseif (a == "--help") then
        r["help"] = true
      elseif (a == "--no-color") then
        r["no-color"] = true
      elseif not a:match("^%-") then
        if not r.schema then
          r["schema"] = a
        elseif not r.operation then
          r["operation"] = a
        else
          table.insert(r["path-params"], a)
        end
      else
      end
    end
    i = (i + 1)
  end
  return r
end
local function coerce(s)
  return (tonumber(s) or s)
end
local function op_3f(v)
  return ((type(v) == "table") and (nil ~= v["has-body?"]))
end
local function list_ops(c)
  local ops = {}
  for k, v in pairs(c) do
    if op_3f(v) then
      local doc = v["fnl/docstring"]
      local summary
      if doc then
        summary = doc:match("^([^\n]+)")
      else
        summary = nil
      end
      table.insert(ops, {k = k, summary = summary})
    else
    end
  end
  local function _6_(a, b)
    return (a.k < b.k)
  end
  table.sort(ops, _6_)
  for _, op in ipairs(ops) do
    local _7_
    if op.summary then
      _7_ = ("\9" .. op.summary)
    else
      _7_ = ""
    end
    print((op.k .. _7_))
  end
  return nil
end
local function print_resp(resp, output, no_color)
  local _9_ = (output or "json")
  if (_9_ == "raw") then
    return print(tostring(resp.body))
  elseif (_9_ == "status") then
    return print(resp.status)
  elseif (_9_ == "headers") then
    for k, v in pairs((resp.headers or {})) do
      print((k .. ": " .. v))
    end
    return nil
  else
    local _ = _9_
    if resp.body then
      return print(pretty_mod.pretty(resp.body, 0, not no_color))
    else
      return io.stderr:write(("HTTP " .. resp.status .. "\n"))
    end
  end
end
local function die(msg)
  io.stderr:write((msg .. "\n"))
  return os.exit(1)
end
local function usage()
  print("Usage: anis <schema-or-profile> [operation] [path-params...] [options]")
  print("")
  print("Options:")
  print("  --list                List all operations")
  print("  --help                Show operation documentation")
  print("  --body=JSON           Request body")
  print("  -d JSON               Request body (alternative)")
  print("  --query.KEY=VAL       Query parameter")
  print("  --header.KEY=VAL      Per-request header")
  print("  --timeout=N           Timeout in seconds")
  print("  --base-url=URL        Override base URL")
  print("  --output=json|raw|status|headers  Output format (default: json)")
  print("  --no-color            Disable colored output")
  print("")
  print("Config: ~/.config/anis/config.json")
  return print("  { \"profiles\": { \"myapi\": { \"schema\": \"https://...\", \"headers\": {} } } }")
end
local function main(args)
  local p = parse_args(args)
  if not p.schema then
    usage()
    os.exit(0)
  else
  end
  local config = load_config()
  local profile
  do
    local t_13_ = config
    if (nil ~= t_13_) then
      t_13_ = t_13_.profiles
    else
    end
    if (nil ~= t_13_) then
      t_13_ = t_13_[p.schema]
    else
    end
    profile = t_13_
  end
  local schema
  local _17_
  do
    local t_16_ = profile
    if (nil ~= t_16_) then
      t_16_ = t_16_.schema
    else
    end
    _17_ = t_16_
  end
  schema = (_17_ or p.schema)
  local opts
  local _20_
  do
    local t_19_ = profile
    if (nil ~= t_19_) then
      t_19_ = t_19_.headers
    else
    end
    _20_ = t_19_
  end
  local or_22_ = p.timeout
  if not or_22_ then
    local t_23_ = profile
    if (nil ~= t_23_) then
      t_23_ = t_23_.timeout
    else
    end
    or_22_ = t_23_
  end
  local _26_
  do
    local t_25_ = profile
    if (nil ~= t_25_) then
      t_25_ = t_25_.ssl
    else
    end
    _26_ = t_25_
  end
  opts = {headers = (_20_ or {}), timeout = or_22_, ssl = _26_}
  local or_28_ = p["base-url"]
  if not or_28_ then
    local t_29_ = profile
    if (nil ~= t_29_) then
      t_29_ = t_29_["base-url"]
    else
    end
    or_28_ = t_29_
  end
  if or_28_ then
    local or_31_ = p["base-url"]
    if not or_31_ then
      local t_32_ = profile
      if (nil ~= t_32_) then
        t_32_ = t_32_["base-url"]
      else
      end
      or_31_ = t_32_
    end
    opts["base-url"] = or_31_
  else
  end
  local c = anis.client(schema, opts)
  if p.list then
    return list_ops(c)
  elseif (p.help and not p.operation) then
    return list_ops(c)
  elseif p.help then
    local op = c[p.operation]
    if op then
      return print((op["fnl/docstring"] or "No documentation available."))
    else
      return die(("Unknown operation: " .. p.operation))
    end
  elseif p.operation then
    local op = c[p.operation]
    if not op then
      die(("Unknown operation: " .. p.operation))
    else
    end
    local path_args
    do
      local tbl_21_ = {}
      local i_22_ = 0
      for _, v in ipairs(p["path-params"]) do
        local val_23_ = coerce(v)
        if (nil ~= val_23_) then
          i_22_ = (i_22_ + 1)
          tbl_21_[i_22_] = val_23_
        else
        end
      end
      path_args = tbl_21_
    end
    local call_args
    do
      local tbl_21_ = {}
      local i_22_ = 0
      for _, v in ipairs(path_args) do
        local val_23_ = v
        if (nil ~= val_23_) then
          i_22_ = (i_22_ + 1)
          tbl_21_[i_22_] = val_23_
        else
        end
      end
      call_args = tbl_21_
    end
    local req_opts
    do
      local o = {}
      if next(p.query) then
        o["query"] = p.query
      else
      end
      if next(p.headers) then
        o["headers"] = p.headers
      else
      end
      if p.timeout then
        o["timeout"] = p.timeout
      else
      end
      if next(o) then
        req_opts = o
      else
        req_opts = nil
      end
    end
    if op["has-body?"] then
      table.insert(call_args, p.body)
    else
    end
    if req_opts then
      table.insert(call_args, req_opts)
    else
    end
    local resp = op(table.unpack(call_args))
    return print_resp(resp, p.output, p["no-color"])
  else
    return die("No operation specified. Use --list to see available operations.")
  end
end
return {main = main}
