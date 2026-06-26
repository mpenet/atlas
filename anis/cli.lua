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
      elseif ((a == "-v") or (a == "--verbose")) then
        r["verbose"] = true
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
  local function _8_(a, b)
    return (a.k < b.k)
  end
  table.sort(ops, _8_)
  for _, op in ipairs(ops) do
    local _9_
    if op.summary then
      _9_ = ("\9" .. op.summary)
    else
      _9_ = ""
    end
    print((op.k .. _9_))
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
  local _12_ = (output or "json")
  if (_12_ == "raw") then
    return print(tostring(resp.body))
  elseif (_12_ == "status") then
    return print(resp.status)
  elseif (_12_ == "headers") then
    for k, v in pairs((resp.headers or {})) do
      print((k .. ": " .. v))
    end
    return nil
  else
    local _ = _12_
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
  local _17_
  do
    local t_16_ = config
    if (nil ~= t_16_) then
      t_16_ = t_16_.profiles
    else
    end
    _17_ = t_16_
  end
  profiles = (_17_ or {})
  if (next(profiles) == nil) then
    return print("No profiles configured.")
  else
    for name, p in pairs(profiles) do
      print((name .. "\9" .. (p.schema or "(no schema)")))
    end
    return nil
  end
end
local function profile_show(config, name)
  local p
  do
    local t_20_ = config
    if (nil ~= t_20_) then
      t_20_ = t_20_.profiles
    else
    end
    if (nil ~= t_20_) then
      t_20_ = t_20_[name]
    else
    end
    p = t_20_
  end
  if p then
    return print(pretty_mod.pretty(p, 0, true))
  else
    return die(("Profile not found: " .. name))
  end
end
local function profile_add(config, name, p, args)
  assert(name, "profile name required")
  local or_24_ = p["schema-url"]
  if not or_24_ then
    local t_25_ = config
    if (nil ~= t_25_) then
      t_25_ = t_25_.profiles
    else
    end
    if (nil ~= t_25_) then
      t_25_ = t_25_[name]
    else
    end
    if (nil ~= t_25_) then
      t_25_ = t_25_.schema
    else
    end
    or_24_ = t_25_
  end
  assert(or_24_, "profile add requires --schema=URL")
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
  local _34_
  do
    local t_33_ = config
    if (nil ~= t_33_) then
      t_33_ = t_33_.profiles
    else
    end
    if (nil ~= t_33_) then
      t_33_ = t_33_[name]
    else
    end
    _34_ = t_33_
  end
  assert(_34_, ("Profile not found: " .. name))
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
    return profile_add(config, name, p, nil)
  elseif (subcmd == "remove") then
    return profile_remove(config, name)
  elseif (subcmd == "rm") then
    return profile_remove(config, name)
  else
    local _ = subcmd
    return die(("Unknown profile subcommand: " .. tostring(subcmd) .. "\nUsage: anis profile <list|show|add|remove> [name] [options]"))
  end
end
local function complete_ops(schema_or_profile)
  local config = load_config()
  local profile
  do
    local t_38_ = config
    if (nil ~= t_38_) then
      t_38_ = t_38_.profiles
    else
    end
    if (nil ~= t_38_) then
      t_38_ = t_38_[schema_or_profile]
    else
    end
    profile = t_38_
  end
  local schema
  local _42_
  do
    local t_41_ = profile
    if (nil ~= t_41_) then
      t_41_ = t_41_.schema
    else
    end
    _42_ = t_41_
  end
  schema = (_42_ or schema_or_profile)
  local opts
  local _45_
  do
    local t_44_ = profile
    if (nil ~= t_44_) then
      t_44_ = t_44_.headers
    else
    end
    _45_ = t_44_
  end
  opts = {headers = (_45_ or {})}
  local ok, c = pcall(anis.client, schema, opts)
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
  print("# anis fish completion \226\128\148 source this or put in ~/.config/fish/completions/anis.fish")
  print("")
  print("# disable file completion by default")
  print("complete -c anis -f")
  print("")
  print("# flags")
  print("complete -c anis -l list      -d 'List all operations'")
  print("complete -c anis -l help      -d 'Show operation documentation'")
  print("complete -c anis -l no-color  -d 'Disable colored output'")
  print("complete -c anis -s v -l verbose -d 'Show status and headers'")
  print("complete -c anis -l output    -d 'Output format' -r -a 'json raw status headers'")
  print("complete -c anis -l timeout   -d 'Timeout in seconds' -r")
  print("complete -c anis -l base-url  -d 'Override base URL' -r")
  print("complete -c anis -l body      -d 'Request body JSON' -r")
  print("complete -c anis -s d         -d 'Request body JSON' -r")
  print("")
  print("# profile names as first positional arg")
  print("complete -c anis -n '__fish_is_first_arg' -a '(anis profile list 2>/dev/null | cut -f1)' -d 'Profile'")
  print("complete -c anis -n '__fish_is_first_arg' -a 'profile' -d 'Manage profiles'")
  print("")
  print("# operation names as second positional arg")
  print("complete -c anis -n 'not __fish_is_first_arg' -a '(anis --complete-ops=(commandline -opc | string split \" \" -f2) 2>/dev/null)'")
  print("")
  print("# profile subcommands")
  return print("complete -c anis -n '__fish_seen_subcommand_from profile' -a 'list show add remove' -d 'Profile subcommand'")
end
local function completion_bash()
  print("# anis bash completion \226\128\148 add to ~/.bashrc: source <(anis completion bash)")
  print("_anis_complete() {")
  print("  local cur=\"${COMP_WORDS[COMP_CWORD]}\"")
  print("  local prev=\"${COMP_WORDS[COMP_CWORD-1]}\"")
  print("  if [ $COMP_CWORD -eq 1 ]; then")
  print("    COMPREPLY=($(compgen -W \"$(anis profile list 2>/dev/null | cut -f1) profile\" -- \"$cur\"))")
  print("  elif [ $COMP_CWORD -eq 2 ] && [ \"${COMP_WORDS[1]}\" != 'profile' ]; then")
  print("    COMPREPLY=($(compgen -W \"$(anis --complete-ops=${COMP_WORDS[1]} 2>/dev/null)\" -- \"$cur\"))")
  print("  elif [ \"${COMP_WORDS[1]}\" = 'profile' ] && [ $COMP_CWORD -eq 2 ]; then")
  print("    COMPREPLY=($(compgen -W 'list show add remove' -- \"$cur\"))")
  print("  fi")
  print("}")
  return print("complete -F _anis_complete anis")
end
local function completion_zsh()
  print("# anis zsh completion \226\128\148 add to fpath or source directly")
  print("#compdef anis")
  print("_anis() {")
  print("  local state")
  print("  _arguments '1:schema-or-profile:->profile' '2:operation:->operation'")
  print("  case $state in")
  print("    profile) compadd $(anis profile list 2>/dev/null | cut -f1) profile ;;")
  print("    operation) compadd $(anis --complete-ops=${words[2]} 2>/dev/null) ;;")
  print("  esac")
  print("}")
  return print("_anis")
end
local function usage()
  print("Usage: anis <schema-or-profile> [operation] [path-params...] [options]")
  print("       anis profile <list|show|add|remove> [name] [options]")
  print("       anis completion <fish|bash|zsh>")
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
  print("Profile options (for 'anis profile add'):")
  print("  --schema=URL          Schema URL or file path")
  print("  --base-url=URL        Override base URL")
  print("  --header.KEY=VAL      Default request header")
  print("  --timeout=N           Default timeout")
  print("  --ssl.KEY=VAL         SSL options (cafile, verify, etc.)")
  print("")
  return print("Config: ~/.config/anis/config.json")
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
    local _51_ = p.operation
    if (_51_ == "fish") then
      return completion_fish()
    elseif (_51_ == "bash") then
      return completion_bash()
    elseif (_51_ == "zsh") then
      return completion_zsh()
    else
      local _ = _51_
      return die("Usage: anis completion <fish|bash|zsh>")
    end
  elseif (p.schema == "profile") then
    return run_profile(p.operation, p["path-params"][1], p, load_config())
  else
    local config = load_config()
    local profile
    do
      local t_53_ = config
      if (nil ~= t_53_) then
        t_53_ = t_53_.profiles
      else
      end
      if (nil ~= t_53_) then
        t_53_ = t_53_[p.schema]
      else
      end
      profile = t_53_
    end
    local schema
    local _57_
    do
      local t_56_ = profile
      if (nil ~= t_56_) then
        t_56_ = t_56_.schema
      else
      end
      _57_ = t_56_
    end
    schema = (_57_ or p.schema)
    local opts
    local _60_
    do
      local t_59_ = profile
      if (nil ~= t_59_) then
        t_59_ = t_59_.headers
      else
      end
      _60_ = t_59_
    end
    local or_62_ = p.timeout
    if not or_62_ then
      local t_63_ = profile
      if (nil ~= t_63_) then
        t_63_ = t_63_.timeout
      else
      end
      or_62_ = t_63_
    end
    local _66_
    do
      local t_65_ = profile
      if (nil ~= t_65_) then
        t_65_ = t_65_.ssl
      else
      end
      _66_ = t_65_
    end
    opts = {headers = (_60_ or {}), timeout = or_62_, ssl = (_66_ or {})}
    local or_68_ = p["base-url"]
    if not or_68_ then
      local t_69_ = profile
      if (nil ~= t_69_) then
        t_69_ = t_69_["base-url"]
      else
      end
      or_68_ = t_69_
    end
    if or_68_ then
      local or_71_ = p["base-url"]
      if not or_71_ then
        local t_72_ = profile
        if (nil ~= t_72_) then
          t_72_ = t_72_["base-url"]
        else
        end
        or_71_ = t_72_
      end
      opts["base-url"] = or_71_
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
