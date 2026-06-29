local atlas = require("atlas")
local auth = require("atlas.auth")
local cache = require("atlas.cache")
local http_mod = require("atlas.http")
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
      elseif a:match("^%-%-select=(.+)") then
        local v = a:match("^%-%-select=(.+)")
        r["select"] = v
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
local function print_resp(resp, output, no_color, verbose, _3fselect)
  local error_3f = (resp.status and (resp.status >= 400))
  local body
  if (not error_3f and _3fselect and resp.body) then
    body = __fnl_global__select_2dpath(resp.body, _3fselect)
  else
    body = resp.body
  end
  if error_3f then
    io.stderr:write(("HTTP " .. resp.status .. "\n"))
    if verbose then
      for k, v in pairs((resp.headers or {})) do
        io.stderr:write((k .. ": " .. v .. "\n"))
      end
      io.stderr:write("\n")
    else
    end
    if resp.body then
      io.stderr:write((pretty_mod.pretty(resp.body, 0, not no_color) .. "\n"))
    else
    end
    return os.exit(1)
  else
    if verbose then
      print(("HTTP " .. resp.status))
      for k, v in pairs((resp.headers or {})) do
        print((k .. ": " .. v))
      end
      print("")
    else
    end
    local case_16_ = (output or "json")
    if (case_16_ == "raw") then
      return print(tostring(body))
    elseif (case_16_ == "status") then
      return print(resp.status)
    elseif (case_16_ == "headers") then
      for k, v in pairs((resp.headers or {})) do
        print((k .. ": " .. v))
      end
      return nil
    else
      local _ = case_16_
      if body then
        return print(pretty_mod.pretty(body, 0, not no_color))
      else
        if not verbose then
          return io.stderr:write(("HTTP " .. resp.status .. "\n"))
        else
          return nil
        end
      end
    end
  end
end
local function select_path(data, path)
  local cur = data
  local i = 1
  do
    local n = #path
    while (cur and (i <= n)) do
      local c = path:sub(i, i)
      if (c == ".") then
        i = (i + 1)
      elseif (c == "[") then
        local idx, j = path:match("^%[(%d+)%]()", i)
        if idx then
          cur = cur[(1 + tonumber(idx))]
          i = j
        else
          cur = nil
          i = (n + 1)
        end
      else
        local key, j = path:match("^([^%.%[]+)()", i)
        if key then
          cur = cur[key]
          i = j
        else
          cur = nil
          i = (n + 1)
        end
      end
    end
  end
  return cur
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
  local _25_
  do
    local t_24_ = config
    if (nil ~= t_24_) then
      t_24_ = t_24_.profiles
    else
    end
    _25_ = t_24_
  end
  profiles = (_25_ or {})
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
    local t_28_ = config
    if (nil ~= t_28_) then
      t_28_ = t_28_.profiles
    else
    end
    if (nil ~= t_28_) then
      t_28_ = t_28_[name]
    else
    end
    p = t_28_
  end
  if p then
    return print(pretty_mod.pretty(p, 0, true))
  else
    return die(("Profile not found: " .. name))
  end
end
local function profile_add(config, name, p)
  assert(name, "profile name required")
  local or_32_ = p["schema-url"]
  if not or_32_ then
    local t_33_ = config
    if (nil ~= t_33_) then
      t_33_ = t_33_.profiles
    else
    end
    if (nil ~= t_33_) then
      t_33_ = t_33_[name]
    else
    end
    if (nil ~= t_33_) then
      t_33_ = t_33_.schema
    else
    end
    or_32_ = t_33_
  end
  assert(or_32_, "profile add requires --schema=URL")
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
  local _42_
  do
    local t_41_ = config
    if (nil ~= t_41_) then
      t_41_ = t_41_.profiles
    else
    end
    if (nil ~= t_41_) then
      t_41_ = t_41_[name]
    else
    end
    _42_ = t_41_
  end
  assert(_42_, ("Profile not found: " .. name))
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
    local t_46_ = config
    if (nil ~= t_46_) then
      t_46_ = t_46_.profiles
    else
    end
    if (nil ~= t_46_) then
      t_46_ = t_46_[schema_or_profile]
    else
    end
    profile = t_46_
  end
  local schema
  local _50_
  do
    local t_49_ = profile
    if (nil ~= t_49_) then
      t_49_ = t_49_.schema
    else
    end
    _50_ = t_49_
  end
  schema = (_50_ or schema_or_profile)
  local opts
  local _53_
  do
    local t_52_ = profile
    if (nil ~= t_52_) then
      t_52_ = t_52_.headers
    else
    end
    _53_ = t_52_
  end
  opts = {headers = (_53_ or {})}
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
  print("  --select=PATH             Select nested value (e.g. .items[0].name)")
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
    local _63_
    do
      local t_62_ = profile
      if (nil ~= t_62_) then
        t_62_ = t_62_.ssl
      else
      end
      _63_ = t_62_
    end
    for k, v in pairs((_63_ or {})) do
      local k_22_, v_23_ = k, v
      if ((k_22_ ~= nil) and (v_23_ ~= nil)) then
        tbl_21_[k_22_] = v_23_
      else
      end
    end
    ssl = tbl_21_
  end
  local tls
  local function _67_()
    local t_66_ = profile
    if (nil ~= t_66_) then
      t_66_ = t_66_.tls
    else
    end
    return t_66_
  end
  tls = tls__3essl(_67_())
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
    local t_71_ = config
    if (nil ~= t_71_) then
      t_71_ = t_71_.profiles
    else
    end
    if (nil ~= t_71_) then
      t_71_ = t_71_[profile_name]
    else
    end
    profile = t_71_
  end
  assert(profile, ("Profile not found: " .. profile_name))
  local auth_cfg
  do
    local t_74_ = profile
    if (nil ~= t_74_) then
      t_74_ = t_74_.auth
    else
    end
    auth_cfg = t_74_
  end
  assert((auth_cfg and auth_cfg.name and (auth_cfg.name ~= "")), ("No auth configured for profile: " .. profile_name))
  local ssl = merge_ssl(profile, p.ssl)
  if (auth_cfg.name == "external-tool") then
    local ok, headers = pcall(auth["get-headers"], profile_name, auth_cfg, ssl)
    if ok then
      for k, v in pairs(headers) do
        print((k .. ": " .. v))
      end
      return nil
    else
      return die(tostring(headers))
    end
  elseif p.logout then
    auth["clear-token"](profile_name)
    return print(("Logged out: " .. profile_name))
  else
    auth["clear-token"](profile_name)
    local ok, result = pcall(auth["get-headers"], profile_name, auth_cfg, ssl)
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
    local case_83_ = p.operation
    if (case_83_ == "fish") then
      return completion_fish()
    elseif (case_83_ == "bash") then
      return completion_bash()
    elseif (case_83_ == "zsh") then
      return completion_zsh()
    else
      local _ = case_83_
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
      local t_85_ = config
      if (nil ~= t_85_) then
        t_85_ = t_85_.profiles
      else
      end
      if (nil ~= t_85_) then
        t_85_ = t_85_[p.schema]
      else
      end
      profile = t_85_
    end
    local raw_schema
    local _89_
    do
      local t_88_ = profile
      if (nil ~= t_88_) then
        t_88_ = t_88_.schema
      else
      end
      _89_ = t_88_
    end
    raw_schema = (_89_ or p.schema)
    local ttl
    local or_91_ = p["cache-ttl"]
    if not or_91_ then
      local t_92_ = profile
      if (nil ~= t_92_) then
        t_92_ = t_92_["cache-ttl"]
      else
      end
      or_91_ = t_92_
    end
    ttl = (or_91_ or 3600)
    local ssl = merge_ssl(profile, p.ssl)
    local auth_cfg
    do
      local a
      do
        local t_94_ = profile
        if (nil ~= t_94_) then
          t_94_ = t_94_.auth
        else
        end
        a = t_94_
      end
      if (a and a.name and (a.name ~= "")) then
        auth_cfg = a
      else
        auth_cfg = nil
      end
    end
    local auth_headers
    if auth_cfg then
      local ok, h = pcall(auth["get-headers"], p.schema, auth_cfg, ssl)
      if ok then
        auth_headers = h
      else
        auth_headers = die(("authentication failed: " .. tostring(h)))
      end
    else
      auth_headers = nil
    end
    local schema
    if ((type(raw_schema) == "string") and raw_schema:match("^https?://")) then
      schema = load_schema_cached(raw_schema, ttl, p.reload, ssl, auth_headers)
    else
      schema = raw_schema
    end
    local opts
    local _100_
    do
      local tbl_21_ = {}
      local _102_
      do
        local t_101_ = profile
        if (nil ~= t_101_) then
          t_101_ = t_101_.headers
        else
        end
        _102_ = t_101_
      end
      for k, v in pairs((_102_ or {})) do
        local k_22_, v_23_ = k, v
        if ((k_22_ ~= nil) and (v_23_ ~= nil)) then
          tbl_21_[k_22_] = v_23_
        else
        end
      end
      _100_ = tbl_21_
    end
    local or_105_ = p.timeout
    if not or_105_ then
      local t_106_ = profile
      if (nil ~= t_106_) then
        t_106_ = t_106_.timeout
      else
      end
      or_105_ = t_106_
    end
    opts = {headers = _100_, timeout = or_105_, ssl = ssl}
    if auth_headers then
      for k, v in pairs(auth_headers) do
        opts.headers[k] = v
      end
    else
    end
    if auth_cfg then
      local wrapped = auth["wrap-http-fn"](auth_cfg, http_mod.request)
      if wrapped then
        opts["http-fn"] = wrapped
      else
      end
    else
    end
    local or_111_ = p["base-url"]
    if not or_111_ then
      local t_112_ = profile
      if (nil ~= t_112_) then
        t_112_ = t_112_["base-url"]
      else
      end
      or_111_ = t_112_
    end
    if or_111_ then
      local or_114_ = p["base-url"]
      if not or_114_ then
        local t_115_ = profile
        if (nil ~= t_115_) then
          t_115_ = t_115_["base-url"]
        else
        end
        or_114_ = t_115_
      end
      opts["base-url"] = or_114_
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
        return print_resp(resp, p.output, p["no-color"], p.verbose, p.select)
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
