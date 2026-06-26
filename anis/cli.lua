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
        local ok, parsed, err = pcall(json.decode, v)
        assert(ok, ("invalid JSON in --body: " .. tostring(err)))
        r["body"] = parsed
      elseif (a == "-d") then
        i = (i + 1)
        local ok, parsed, err = pcall(json.decode, args[i])
        assert(ok, ("invalid JSON in -d: " .. tostring(err)))
        r["body"] = parsed
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
      elseif ((a == "-v") or (a == "--verbose")) then
        r["verbose"] = true
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
local function print_resp(resp, output, no_color, verbose)
  if verbose then
    print(("HTTP " .. resp.status))
    for k, v in pairs((resp.headers or {})) do
      print((k .. ": " .. v))
    end
    print("")
  else
  end
  local _10_ = (output or "json")
  if (_10_ == "raw") then
    return print(tostring(resp.body))
  elseif (_10_ == "status") then
    return print(resp.status)
  elseif (_10_ == "headers") then
    for k, v in pairs((resp.headers or {})) do
      print((k .. ": " .. v))
    end
    return nil
  else
    local _ = _10_
    if resp.body then
      return print(pretty_mod.pretty(resp.body, 0, not no_color))
    else
      if not verbose then
        return io.stderr:write(("HTTP " .. resp.status .. "\n"))
      else
        return nil
      end
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
  print("  -v, --verbose         Show status and response headers")
  print("")
  print("Config: ~/.config/anis/config.json")
  return print("  { \"profiles\": { \"myapi\": { \"schema\": \"https://...\", \"headers\": {} } } }")
end
local function run(args)
  local p = parse_args(args)
  if not p.schema then
    usage()
    os.exit(0)
  else
  end
  local config = load_config()
  local profile
  do
    local t_15_ = config
    if (nil ~= t_15_) then
      t_15_ = t_15_.profiles
    else
    end
    if (nil ~= t_15_) then
      t_15_ = t_15_[p.schema]
    else
    end
    profile = t_15_
  end
  local schema
  local _19_
  do
    local t_18_ = profile
    if (nil ~= t_18_) then
      t_18_ = t_18_.schema
    else
    end
    _19_ = t_18_
  end
  schema = (_19_ or p.schema)
  local opts
  local _22_
  do
    local t_21_ = profile
    if (nil ~= t_21_) then
      t_21_ = t_21_.headers
    else
    end
    _22_ = t_21_
  end
  local or_24_ = p.timeout
  if not or_24_ then
    local t_25_ = profile
    if (nil ~= t_25_) then
      t_25_ = t_25_.timeout
    else
    end
    or_24_ = t_25_
  end
  local _28_
  do
    local t_27_ = profile
    if (nil ~= t_27_) then
      t_27_ = t_27_.ssl
    else
    end
    _28_ = t_27_
  end
  opts = {headers = (_22_ or {}), timeout = or_24_, ssl = _28_}
  local or_30_ = p["base-url"]
  if not or_30_ then
    local t_31_ = profile
    if (nil ~= t_31_) then
      t_31_ = t_31_["base-url"]
    else
    end
    or_30_ = t_31_
  end
  if or_30_ then
    local or_33_ = p["base-url"]
    if not or_33_ then
      local t_34_ = profile
      if (nil ~= t_34_) then
        t_34_ = t_34_["base-url"]
      else
      end
      or_33_ = t_34_
    end
    opts["base-url"] = or_33_
  else
  end
  local ok_c, c = pcall(anis.client, schema, opts)
  if not ok_c then
    die(("failed to build client: " .. tostring(c)))
  else
  end
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
    local ok_r, resp = pcall(op, table.unpack(call_args))
    if ok_r then
      return print_resp(resp, p.output, p["no-color"], p.verbose)
    else
      return die(("request failed: " .. tostring(resp)))
    end
  else
    return die("No operation specified. Use --list to see available operations.")
  end
end
local function main(args)
  local ok, err = pcall(run, args)
  if not ok then
    return die(tostring(err))
  else
    return nil
  end
end
return {main = main}
