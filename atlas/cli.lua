local atlas = require("atlas")
local auth = require("atlas.auth")
local cache = require("atlas.cache")
local json = require("lunajson")
local pretty_mod = require("atlas.pretty")
local function config_path()
  return ((os.getenv("HOME") or ".") .. "/.config/atlas/config.json")
end
local function load_config()
  local f = io.open(config_path(), "r")
  if f then
    local ok, cfg = pcall(json.decode, f:read("*a"))
    f:close()
    if ok then
      return cfg
    else
      return error(("corrupt config: " .. config_path()))
    end
  else
    return {}
  end
end
local function read_body(s)
  local raw
  if (s == "@-") then
    raw = io.read("*a")
  else
    local path = s:match("^@(.+)")
    if path then
      local f = assert(io.open(path, "r"))
      local c = f:read("*a")
      f:close()
      raw = c
    else
      raw = s
    end
  end
  local ok, parsed = pcall(json.decode, raw)
  assert(ok, ("invalid JSON in body: " .. tostring(parsed)))
  return parsed
end
local function save_config(cfg)
  local path = config_path()
  local dir = path:match("^(.+)/[^/]+$")
  os.execute(("mkdir -p " .. dir))
  local f = assert(io.open(path, "w"))
  f:write(json.encode(cfg))
  return f:close()
end
local function parse_args(args)
  local r = {["path-params"] = {}, query = {}, headers = {}, ssl = {}}
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
      elseif a:match("^%-%-ssl%.(.-)=(.+)") then
        local k, v = a:match("^%-%-ssl%.(.-)=(.+)")
        r.ssl[k] = v
      elseif a:match("^%-%-body=(.*)") then
        local v = a:match("^%-%-body=(.*)")
        r["body"] = read_body(v)
      elseif (a == "-d") then
        i = (i + 1)
        r["body"] = read_body(args[i])
      elseif a:match("^%-%-schema=(.+)") then
        local v = a:match("^%-%-schema=(.+)")
        r["schema-url"] = v
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
      elseif (a == "--reload") then
        r["reload"] = true
      elseif (a == "--logout") then
        r["logout"] = true
      elseif ((a == "-v") or (a == "--verbose")) then
        r["verbose"] = true
      elseif a:match("^%-%-cache%-ttl=(.+)") then
        local v = a:match("^%-%-cache%-ttl=(.+)")
        r["cache-ttl"] = tonumber(v)
      elseif a:match("^%-%-complete%-ops=(.+)") then
        local v = a:match("^%-%-complete%-ops=(.+)")
        r["complete-ops"] = v
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
  local function _9_(a, b)
    return (a.k < b.k)
  end
  table.sort(ops, _9_)
  for _, op in ipairs(ops) do
    local _10_
    if op.summary then
      _10_ = ("\t" .. op.summary)
    else
      _10_ = ""
    end
    print((op.k .. _10_))
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
  local case_13_ = (output or "json")
  if (case_13_ == "raw") then
    return print(tostring(resp.body))
  elseif (case_13_ == "status") then
    return print(resp.status)
  elseif (case_13_ == "headers") then
    for k, v in pairs((resp.headers or {})) do
      print((k .. ": " .. v))
    end
    return nil
  else
    local _ = case_13_
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
local function strip_location(msg)
  local s = tostring(msg)
  local r = s:gsub("[^%s:]+%.lua:%d+: ", "")
  return r
end
local function die(msg)
  io.stderr:write((strip_location(tostring(msg)) .. "\n"))
  return os.exit(1)
end
local function profile_list(config)
  local profiles
  local _18_
  do
    local t_17_ = config
    if (nil ~= t_17_) then
      t_17_ = t_17_.profiles
    else
    end
    _18_ = t_17_
  end
  profiles = (_18_ or {})
  if (next(profiles) == nil) then
    return print("No profiles configured.")
  else
    for name, p in pairs(profiles) do
      print((name .. "\t" .. (p.schema or "(no schema)")))
    end
    return nil
  end
end
local function profile_show(config, name)
  local p
  do
    local t_21_ = config
    if (nil ~= t_21_) then
      t_21_ = t_21_.profiles
    else
    end
    if (nil ~= t_21_) then
      t_21_ = t_21_[name]
    else
    end
    p = t_21_
  end
  if p then
    return print(pretty_mod.pretty(p, 0, true))
  else
    return die(("Profile not found: " .. name))
  end
end
local function profile_add(config, name, p)
  assert(name, "profile name required")
  local or_25_ = p["schema-url"]
  if not or_25_ then
    local t_26_ = config
    if (nil ~= t_26_) then
      t_26_ = t_26_.profiles
    else
    end
    if (nil ~= t_26_) then
      t_26_ = t_26_[name]
    else
    end
    if (nil ~= t_26_) then
      t_26_ = t_26_.schema
    else
    end
    or_25_ = t_26_
  end
  assert(or_25_, "profile add requires --schema=URL")
  local profiles = (config.profiles or {})
  local existing = (profiles[name] or {})
  local updated = {schema = (p["schema-url"] or existing.schema)}
  if p["base-url"] then
    updated["base-url"] = p["base-url"]
  else
  end
  if p.timeout then
    updated["timeout"] = p.timeout
  else
  end
  if next(p.headers) then
    updated["headers"] = p.headers
  else
  end
  if next(p.ssl) then
    updated["ssl"] = p.ssl
  else
  end
  profiles[name] = updated
  config["profiles"] = profiles
  save_config(config)
  return print(("Profile '" .. name .. "' saved."))
end
local function profile_remove(config, name)
  assert(name, "profile name required")
  local _35_
  do
    local t_34_ = config
    if (nil ~= t_34_) then
      t_34_ = t_34_.profiles
    else
    end
    if (nil ~= t_34_) then
      t_34_ = t_34_[name]
    else
    end
    _35_ = t_34_
  end
  assert(_35_, ("Profile not found: " .. name))
  config.profiles[name] = nil
  save_config(config)
  return print(("Profile '" .. name .. "' removed."))
end
local function run_profile(subcmd, name, p, config)
  if (subcmd == "list") then
    return profile_list(config)
  elseif (subcmd == "show") then
    return profile_show(config, name)
  elseif (subcmd == "add") then
    return profile_add(config, name, p)
  elseif (subcmd == "remove") then
    return profile_remove(config, name)
  elseif (subcmd == "rm") then
    return profile_remove(config, name)
  else
    local _ = subcmd
    return die(("Unknown profile subcommand: " .. tostring(subcmd) .. "\nUsage: atlas profile <list|show|add|remove> [name] [options]"))
  end
end
local function complete_ops(schema_or_profile)
  local config = load_config()
  local profile
  do
    local t_39_ = config
    if (nil ~= t_39_) then
      t_39_ = t_39_.profiles
    else
    end
    if (nil ~= t_39_) then
      t_39_ = t_39_[schema_or_profile]
    else
    end
    profile = t_39_
  end
  local schema
  local _43_
  do
    local t_42_ = profile
    if (nil ~= t_42_) then
      t_42_ = t_42_.schema
    else
    end
    _43_ = t_42_
  end
  schema = (_43_ or schema_or_profile)
  local opts
  local _46_
  do
    local t_45_ = profile
    if (nil ~= t_45_) then
      t_45_ = t_45_.headers
    else
    end
    _46_ = t_45_
  end
  opts = {headers = (_46_ or {})}
  local ok, c = pcall(atlas.client, schema, opts)
  if ok then
    for k, v in pairs(c) do
      if op_3f(v) then
        print(k)
      else
      end
    end
    return nil
  else
    return nil
  end
end
local function completion_fish()
  print("# atlas fish completion \226\128\148 source this or put in ~/.config/fish/completions/atlas.fish")
  print("")
  print("# disable file completion by default")
  print("complete -c atlas -f")
  print("")
  print("# flags")
  print("complete -c atlas -l list      -d 'List all operations'")
  print("complete -c atlas -l help      -d 'Show operation documentation'")
  print("complete -c atlas -l no-color  -d 'Disable colored output'")
  print("complete -c atlas -s v -l verbose -d 'Show status and headers'")
  print("complete -c atlas -l output    -d 'Output format' -r -a 'json raw status headers'")
  print("complete -c atlas -l timeout   -d 'Timeout in seconds' -r")
  print("complete -c atlas -l base-url  -d 'Override base URL' -r")
  print("complete -c atlas -l body      -d 'Request body JSON' -r")
  print("complete -c atlas -s d         -d 'Request body JSON' -r")
  print("")
  print("# profile names as first positional arg")
  print("complete -c atlas -n '__fish_is_first_arg' -a '(atlas profile list 2>/dev/null | cut -f1)' -d 'Profile'")
  print("complete -c atlas -n '__fish_is_first_arg' -a 'profile' -d 'Manage profiles'")
  print("")
  print("# operation names as second positional arg")
  print("complete -c atlas -n 'not __fish_is_first_arg' -a '(atlas --complete-ops=(commandline -opc | string split \" \" -f2) 2>/dev/null)'")
  print("")
  print("# profile subcommands")
  return print("complete -c atlas -n '__fish_seen_subcommand_from profile' -a 'list show add remove' -d 'Profile subcommand'")
end
local function completion_bash()
  print("# atlas bash completion \226\128\148 add to ~/.bashrc: source <(atlas completion bash)")
  print("_atlas_complete() {")
  print("  local cur=\"${COMP_WORDS[COMP_CWORD]}\"")
  print("  local prev=\"${COMP_WORDS[COMP_CWORD-1]}\"")
  print("  if [ $COMP_CWORD -eq 1 ]; then")
  print("    COMPREPLY=($(compgen -W \"$(atlas profile list 2>/dev/null | cut -f1) profile\" -- \"$cur\"))")
  print("  elif [ $COMP_CWORD -eq 2 ] && [ \"${COMP_WORDS[1]}\" != 'profile' ]; then")
  print("    COMPREPLY=($(compgen -W \"$(atlas --complete-ops=${COMP_WORDS[1]} 2>/dev/null)\" -- \"$cur\"))")
  print("  elif [ \"${COMP_WORDS[1]}\" = 'profile' ] && [ $COMP_CWORD -eq 2 ]; then")
  print("    COMPREPLY=($(compgen -W 'list show add remove' -- \"$cur\"))")
  print("  fi")
  print("}")
  return print("complete -F _atlas_complete atlas")
end
local function completion_zsh()
  print("# atlas zsh completion \226\128\148 add to fpath or source directly")
  print("#compdef atlas")
  print("_atlas() {")
  print("  local state")
  print("  _arguments '1:schema-or-profile:->profile' '2:operation:->operation'")
  print("  case $state in")
  print("    profile) compadd $(atlas profile list 2>/dev/null | cut -f1) profile ;;")
  print("    operation) compadd $(atlas --complete-ops=${words[2]} 2>/dev/null) ;;")
  print("  esac")
  print("}")
  return print("_atlas")
end
local function usage()
  print("Usage: atlas <schema-or-profile> [operation] [path-params...] [options]")
  print("       atlas profile <list|show|add|remove> [name] [options]")
  print("       atlas auth <profile> [--logout]")
  print("       atlas completion <fish|bash|zsh>")
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
  print("  --reload              Re-fetch and re-cache the schema")
  print("  --cache-ttl=N         Schema cache TTL in seconds (default: 3600)")
  print("")
  print("Auth options (for 'atlas auth <profile>'):")
  print("  --logout              Clear cached token")
  print("")
  print("Profile options (for 'atlas profile add'):")
  print("  --schema=URL          Schema URL or file path")
  print("  --base-url=URL        Override base URL")
  print("  --header.KEY=VAL      Default request header")
  print("  --timeout=N           Default timeout")
  print("  --ssl.KEY=VAL         SSL options (cafile, verify, etc.)")
  print("")
  return print("Config: ~/.config/atlas/config.json")
end
local function tls__3essl(tls)
  if tls then
    local ssl = {}
    if tls.cert then
      ssl["certificate"] = tls.cert
    else
    end
    if tls.key then
      ssl["key"] = tls.key
    else
    end
    if tls.insecure then
      ssl["verify"] = "none"
    else
    end
    if next(ssl) then
      return ssl
    else
      return nil
    end
  else
    return nil
  end
end
local function merge_ssl(profile, cli_ssl)
  local ssl
  do
    local tbl_21_ = {}
    local _56_
    do
      local t_55_ = profile
      if (nil ~= t_55_) then
        t_55_ = t_55_.ssl
      else
      end
      _56_ = t_55_
    end
    for k, v in pairs((_56_ or {})) do
      local k_22_, v_23_ = k, v
      if ((k_22_ ~= nil) and (v_23_ ~= nil)) then
        tbl_21_[k_22_] = v_23_
      else
      end
    end
    ssl = tbl_21_
  end
  local tls
  local function _60_()
    local t_59_ = profile
    if (nil ~= t_59_) then
      t_59_ = t_59_.tls
    else
    end
    return t_59_
  end
  tls = tls__3essl(_60_())
  if tls then
    for k, v in pairs(tls) do
      ssl[k] = v
    end
  else
  end
  if cli_ssl then
    for k, v in pairs(cli_ssl) do
      ssl[k] = v
    end
  else
  end
  return ssl
end
local function run_auth(profile_name, p, config)
  assert(profile_name, "Usage: atlas auth <profile> [--logout]")
  local profile
  do
    local t_64_ = config
    if (nil ~= t_64_) then
      t_64_ = t_64_.profiles
    else
    end
    if (nil ~= t_64_) then
      t_64_ = t_64_[profile_name]
    else
    end
    profile = t_64_
  end
  assert(profile, ("Profile not found: " .. profile_name))
  local auth_cfg
  do
    local t_67_ = profile
    if (nil ~= t_67_) then
      t_67_ = t_67_.auth
    else
    end
    auth_cfg = t_67_
  end
  assert((auth_cfg and auth_cfg.name and (auth_cfg.name ~= "")), ("No auth configured for profile: " .. profile_name))
  local ssl = merge_ssl(profile, p.ssl)
  if p.logout then
    auth["clear-token"](profile_name)
    return print(("Logged out: " .. profile_name))
  else
    auth["clear-token"](profile_name)
    local ok, result = pcall(auth.authenticate, profile_name, auth_cfg, ssl)
    if ok then
      return print(("Authenticated: " .. profile_name))
    else
      return die(tostring(result))
    end
  end
end
local function load_schema_cached(url, ttl, reload_3f, ssl, headers)
  local cached
  if not reload_3f then
    cached = cache.get(url, ttl)
  else
    cached = nil
  end
  if cached then
    return cached
  else
    local schema = atlas["load-schema"](url, ssl, headers)
    cache.put(url, schema)
    return schema
  end
end
local function run(args)
  local p = parse_args(args)
  if not p.schema then
    usage()
    os.exit(0)
  else
  end
  if p["complete-ops"] then
    complete_ops(p["complete-ops"])
    os.exit(0)
  else
  end
  if (p.schema == "completion") then
    local case_75_ = p.operation
    if (case_75_ == "fish") then
      return completion_fish()
    elseif (case_75_ == "bash") then
      return completion_bash()
    elseif (case_75_ == "zsh") then
      return completion_zsh()
    else
      local _ = case_75_
      return die("Usage: atlas completion <fish|bash|zsh>")
    end
  elseif (p.schema == "profile") then
    return run_profile(p.operation, p["path-params"][1], p, load_config())
  elseif (p.schema == "auth") then
    return run_auth(p.operation, p, load_config())
  else
    local config = load_config()
    local profile
    do
      local t_77_ = config
      if (nil ~= t_77_) then
        t_77_ = t_77_.profiles
      else
      end
      if (nil ~= t_77_) then
        t_77_ = t_77_[p.schema]
      else
      end
      profile = t_77_
    end
    local raw_schema
    local _81_
    do
      local t_80_ = profile
      if (nil ~= t_80_) then
        t_80_ = t_80_.schema
      else
      end
      _81_ = t_80_
    end
    raw_schema = (_81_ or p.schema)
    local ttl
    local or_83_ = p["cache-ttl"]
    if not or_83_ then
      local t_84_ = profile
      if (nil ~= t_84_) then
        t_84_ = t_84_["cache-ttl"]
      else
      end
      or_83_ = t_84_
    end
    ttl = (or_83_ or 3600)
    local ssl = merge_ssl(profile, p.ssl)
    local auth_cfg
    do
      local a
      do
        local t_86_ = profile
        if (nil ~= t_86_) then
          t_86_ = t_86_.auth
        else
        end
        a = t_86_
      end
      if (a and a.name and (a.name ~= "")) then
        auth_cfg = a
      else
        auth_cfg = nil
      end
    end
    local auth_token
    if auth_cfg then
      local ok, token = pcall(auth["ensure-token"], p.schema, auth_cfg, ssl)
      if ok then
        auth_token = token
      else
        auth_token = die(("authentication failed: " .. tostring(token)))
      end
    else
      auth_token = nil
    end
    local schema_headers
    if auth_token then
      schema_headers = {authorization = ("Bearer " .. auth_token)}
    else
      schema_headers = nil
    end
    local schema
    if ((type(raw_schema) == "string") and raw_schema:match("^https?://")) then
      schema = load_schema_cached(raw_schema, ttl, p.reload, ssl, schema_headers)
    else
      schema = raw_schema
    end
    local opts
    local _93_
    do
      local tbl_21_ = {}
      local _95_
      do
        local t_94_ = profile
        if (nil ~= t_94_) then
          t_94_ = t_94_.headers
        else
        end
        _95_ = t_94_
      end
      for k, v in pairs((_95_ or {})) do
        local k_22_, v_23_ = k, v
        if ((k_22_ ~= nil) and (v_23_ ~= nil)) then
          tbl_21_[k_22_] = v_23_
        else
        end
      end
      _93_ = tbl_21_
    end
    local or_98_ = p.timeout
    if not or_98_ then
      local t_99_ = profile
      if (nil ~= t_99_) then
        t_99_ = t_99_.timeout
      else
      end
      or_98_ = t_99_
    end
    opts = {headers = _93_, timeout = or_98_, ssl = ssl}
    if auth_token then
      opts.headers["authorization"] = ("Bearer " .. auth_token)
    else
    end
    local or_102_ = p["base-url"]
    if not or_102_ then
      local t_103_ = profile
      if (nil ~= t_103_) then
        t_103_ = t_103_["base-url"]
      else
      end
      or_102_ = t_103_
    end
    if or_102_ then
      local or_105_ = p["base-url"]
      if not or_105_ then
        local t_106_ = profile
        if (nil ~= t_106_) then
          t_106_ = t_106_["base-url"]
        else
        end
        or_105_ = t_106_
      end
      opts["base-url"] = or_105_
    else
    end
    if (type(schema) == "table") then
      opts["source-url"] = raw_schema
    else
    end
    local ok_c, c = pcall(atlas.client, schema, opts)
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
        local tbl_26_ = {}
        local i_27_ = 0
        for _, v in ipairs(p["path-params"]) do
          local val_28_ = coerce(v)
          if (nil ~= val_28_) then
            i_27_ = (i_27_ + 1)
            tbl_26_[i_27_] = val_28_
          else
          end
        end
        path_args = tbl_26_
      end
      local call_args
      do
        local tbl_26_ = {}
        local i_27_ = 0
        for _, v in ipairs(path_args) do
          local val_28_ = v
          if (nil ~= val_28_) then
            i_27_ = (i_27_ + 1)
            tbl_26_[i_27_] = val_28_
          else
          end
        end
        call_args = tbl_26_
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
