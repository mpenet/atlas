local atlas = require("atlas")
local auth = require("atlas.auth")
local cache = require("atlas.cache")
local http_mod = require("atlas.http")
local json = require("lunajson")
local pretty_mod = require("atlas.pretty")
local socket = require("socket")
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
local function merge_profiles(base, child)
  local result
  do
    local tbl_21_ = {}
    for k, v in pairs(base) do
      local k_22_, v_23_ = k, v
      if ((k_22_ ~= nil) and (v_23_ ~= nil)) then
        tbl_21_[k_22_] = v_23_
      else
      end
    end
    result = tbl_21_
  end
  for k, v in pairs(child) do
    if ((k == "headers") and (type(v) == "table") and (type(result[k]) == "table")) then
      local merged
      do
        local tbl_21_ = {}
        for hk, hv in pairs(result[k]) do
          local k_22_, v_23_ = hk, hv
          if ((k_22_ ~= nil) and (v_23_ ~= nil)) then
            tbl_21_[k_22_] = v_23_
          else
          end
        end
        merged = tbl_21_
      end
      for hk, hv in pairs(v) do
        merged[hk] = hv
      end
      result[k] = merged
    else
      result[k] = v
    end
  end
  return result
end
local function resolve_profile(name, profiles, _3fseen)
  local seen = (_3fseen or {})
  local p = profiles[name]
  assert(p, ("Profile not found: " .. name))
  assert(not seen[name], ("Circular extends: " .. name))
  seen[name] = true
  if p.extends then
    local base = resolve_profile(p.extends, profiles, seen)
    local child
    do
      local tbl_21_ = {}
      for k, v in pairs(p) do
        local k_22_, v_23_ = k, v
        if ((k_22_ ~= nil) and (v_23_ ~= nil)) then
          tbl_21_[k_22_] = v_23_
        else
        end
      end
      child = tbl_21_
    end
    child["extends"] = nil
    return merge_profiles(base, child)
  else
    return p
  end
end
local function coerce(s)
  return (tonumber(s) or s)
end
local function parse_args(args)
  local r = {["path-params"] = {}, query = {}, headers = {}, ssl = {}, ["body-params"] = {}}
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
      elseif a:match("^%-%-body%.(.-)=(.+)") then
        local k, v = a:match("^%-%-body%.(.-)=(.+)")
        r["body-params"][k] = coerce(v)
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
  local function _14_(a, b)
    return (a.k < b.k)
  end
  table.sort(ops, _14_)
  for _, op in ipairs(ops) do
    local _15_
    if op.summary then
      _15_ = ("\t" .. op.summary)
    else
      _15_ = ""
    end
    print((op.k .. _15_))
  end
  return nil
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
        local j_iter = path:match("^%[%]()", i)
        if j_iter then
          local rest = path:sub(j_iter)
          local result = {}
          if (type(cur) == "table") then
            for _, v in ipairs(cur) do
              local function _17_()
                if (#rest > 0) then
                  return select_path(v, rest)
                else
                  return v
                end
              end
              table.insert(result, _17_())
            end
          else
          end
          cur = result
          i = (n + 1)
        else
          local idx, j = path:match("^%[(%d+)%]()", i)
          if idx then
            cur = cur[(1 + tonumber(idx))]
            i = j
          else
            cur = nil
            i = (n + 1)
          end
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
local function print_resp(resp, output, no_color, verbose, _3fselect, _3felapsed)
  local error_3f = (resp.status and (resp.status >= 400))
  local body
  if (not error_3f and _3fselect and resp.body) then
    body = select_path(resp.body, _3fselect)
  else
    body = resp.body
  end
  local timing
  if _3felapsed then
    timing = ("  " .. string.format("%.3fs", _3felapsed))
  else
    timing = ""
  end
  if error_3f then
    io.stderr:write(("HTTP " .. resp.status .. timing .. "\n"))
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
      print(("HTTP " .. resp.status .. timing))
      for k, v in pairs((resp.headers or {})) do
        print((k .. ": " .. v))
      end
      print("")
    else
    end
    local case_28_ = (output or "json")
    if (case_28_ == "raw") then
      return print(tostring(body))
    elseif (case_28_ == "status") then
      return print(resp.status)
    elseif (case_28_ == "headers") then
      for k, v in pairs((resp.headers or {})) do
        print((k .. ": " .. v))
      end
      return nil
    else
      local _ = case_28_
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
  local _34_
  do
    local t_33_ = config
    if (nil ~= t_33_) then
      t_33_ = t_33_.profiles
    else
    end
    _34_ = t_33_
  end
  profiles = (_34_ or {})
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
  local profiles
  local _38_
  do
    local t_37_ = config
    if (nil ~= t_37_) then
      t_37_ = t_37_.profiles
    else
    end
    _38_ = t_37_
  end
  profiles = (_38_ or {})
  local p
  if profiles[name] then
    p = resolve_profile(name, profiles, {})
  else
    p = nil
  end
  if p then
    return print(pretty_mod.pretty(p, 0, true))
  else
    return die(("Profile not found: " .. name))
  end
end
local function run_profile(subcmd, name, config)
  if (subcmd == "list") then
    return profile_list(config)
  elseif (subcmd == "show") then
    return profile_show(config, name)
  else
    local _ = subcmd
    return die(("Unknown profile subcommand: " .. tostring(subcmd) .. "\nUsage: atlas profile <list|show> [name]"))
  end
end
local function complete_ops(schema_or_profile)
  local config = load_config()
  local profiles
  local _44_
  do
    local t_43_ = config
    if (nil ~= t_43_) then
      t_43_ = t_43_.profiles
    else
    end
    _44_ = t_43_
  end
  profiles = (_44_ or {})
  local profile
  if profiles[schema_or_profile] then
    profile = resolve_profile(schema_or_profile, profiles, {})
  else
    profile = nil
  end
  local schema
  local _48_
  do
    local t_47_ = profile
    if (nil ~= t_47_) then
      t_47_ = t_47_.schema
    else
    end
    _48_ = t_47_
  end
  schema = (_48_ or schema_or_profile)
  local opts
  local _51_
  do
    local t_50_ = profile
    if (nil ~= t_50_) then
      t_50_ = t_50_.headers
    else
    end
    _51_ = t_50_
  end
  opts = {headers = (_51_ or {})}
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
  print("complete -c atlas -f")
  print("")
  print("# count non-flag positional args before cursor")
  print("function __atlas_num_args")
  print("    set -l n 0")
  print("    for t in (commandline -opc)[2..]")
  print("        string match -qr '^-' -- $t; or set n (math $n + 1)")
  print("    end")
  print("    echo $n")
  print("end")
  print("")
  print("# \226\148\128\226\148\128 first positional \226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128")
  print("complete -c atlas -n 'test (__atlas_num_args) -eq 0' -a '(atlas profile list 2>/dev/null | cut -f1)' -d Profile")
  print("complete -c atlas -n 'test (__atlas_num_args) -eq 0' -a profile    -d 'Manage profiles'")
  print("complete -c atlas -n 'test (__atlas_num_args) -eq 0' -a auth       -d 'Authenticate a profile'")
  print("complete -c atlas -n 'test (__atlas_num_args) -eq 0' -a completion -d 'Print shell completion script'")
  print("")
  print("# \226\148\128\226\148\128 profile subcommands \226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128")
  print("complete -c atlas -n '__fish_seen_subcommand_from profile; and test (__atlas_num_args) -eq 1' -a list -d 'List profiles'")
  print("complete -c atlas -n '__fish_seen_subcommand_from profile; and test (__atlas_num_args) -eq 1' -a show -d 'Show resolved profile'")
  print("complete -c atlas -n '__fish_seen_subcommand_from profile; and __fish_seen_subcommand_from show' -a '(atlas profile list 2>/dev/null | cut -f1)'")
  print("")
  print("# \226\148\128\226\148\128 auth <profile> \226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128")
  print("complete -c atlas -n '__fish_seen_subcommand_from auth; and test (__atlas_num_args) -eq 1' -a '(atlas profile list 2>/dev/null | cut -f1)'")
  print("")
  print("# \226\148\128\226\148\128 completion <shell> \226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128")
  print("complete -c atlas -n '__fish_seen_subcommand_from completion; and test (__atlas_num_args) -eq 1' -a 'fish bash zsh'")
  print("")
  print("# \226\148\128\226\148\128 operation names (second positional, non-special first arg) \226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128")
  print("complete -c atlas -n 'not __fish_seen_subcommand_from profile auth completion; and test (__atlas_num_args) -eq 1' -a '(atlas --complete-ops=(commandline -opc)[2] 2>/dev/null)'")
  print("")
  print("# \226\148\128\226\148\128 flags \226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128")
  print("complete -c atlas -l list      -d 'List all operations'")
  print("complete -c atlas -l help      -d 'Show operation documentation'")
  print("complete -c atlas -l no-color  -d 'Disable colored output'")
  print("complete -c atlas -s v -l verbose -d 'Show status and response headers'")
  print("complete -c atlas -l reload    -d 'Re-fetch and re-cache the schema'")
  print("complete -c atlas -l output    -r -d 'Output format' -a 'json raw status headers'")
  print("complete -c atlas -l select    -r -d 'Select nested value (.items[0].name)'")
  print("complete -c atlas -l timeout   -r -d 'Timeout in seconds'")
  print("complete -c atlas -l cache-ttl -r -d 'Schema cache TTL in seconds'")
  print("complete -c atlas -l base-url  -r -d 'Override base URL'")
  print("complete -c atlas -l body      -r -d 'Request body (JSON, @file, @-)'")
  print("complete -c atlas -s d         -r -d 'Request body (JSON, @file, @-)'")
  return print("complete -c atlas -l logout    -d 'Clear cached token (for auth subcommand)'")
end
local function completion_bash()
  print("# atlas bash completion \226\128\148 add to ~/.bashrc: source <(atlas completion bash)")
  print("_atlas_complete() {")
  print("  local cur=\"${COMP_WORDS[COMP_CWORD]}\"")
  print("  local first=\"${COMP_WORDS[1]}\"")
  print("  local second=\"${COMP_WORDS[2]}\"")
  print("  if [ $COMP_CWORD -eq 1 ]; then")
  print("    local profiles=$(atlas profile list 2>/dev/null | cut -f1)")
  print("    COMPREPLY=($(compgen -W \"$profiles profile auth completion\" -- \"$cur\"))")
  print("  elif [ $COMP_CWORD -eq 2 ]; then")
  print("    case \"$first\" in")
  print("      profile)    COMPREPLY=($(compgen -W 'list show' -- \"$cur\")) ;;")
  print("      auth)       COMPREPLY=($(compgen -W \"$(atlas profile list 2>/dev/null | cut -f1)\" -- \"$cur\")) ;;")
  print("      completion) COMPREPLY=($(compgen -W 'fish bash zsh' -- \"$cur\")) ;;")
  print("      *)          COMPREPLY=($(compgen -W \"$(atlas --complete-ops=$first 2>/dev/null)\" -- \"$cur\")) ;;")
  print("    esac")
  print("  elif [ $COMP_CWORD -eq 3 ] && [ \"$first\" = 'profile' ] && [ \"$second\" = 'show' ]; then")
  print("    COMPREPLY=($(compgen -W \"$(atlas profile list 2>/dev/null | cut -f1)\" -- \"$cur\"))")
  print("  fi")
  print("}")
  return print("complete -F _atlas_complete atlas")
end
local function completion_zsh()
  print("# atlas zsh completion \226\128\148 add to fpath or source directly")
  print("#compdef atlas")
  print("_atlas() {")
  print("  local state first=${words[2]}")
  print("  _arguments '1:schema-or-profile:->first' '2:arg:->second' '3:name:->third'")
  print("  case $state in")
  print("    first)")
  print("      local profiles=($(atlas profile list 2>/dev/null | cut -f1))")
  print("      compadd $profiles profile auth completion ;;")
  print("    second)")
  print("      case $first in")
  print("        profile)    compadd list show ;;")
  print("        auth)       compadd $(atlas profile list 2>/dev/null | cut -f1) ;;")
  print("        completion) compadd fish bash zsh ;;")
  print("        *)          compadd $(atlas --complete-ops=$first 2>/dev/null) ;;")
  print("      esac ;;")
  print("    third)")
  print("      if [ \"${words[2]}\" = 'profile' ] && [ \"${words[3]}\" = 'show' ]; then")
  print("        compadd $(atlas profile list 2>/dev/null | cut -f1)")
  print("      fi ;;")
  print("  esac")
  print("}")
  return print("_atlas")
end
local function usage()
  print("Usage: atlas <schema-or-profile> [operation] [path-params...] [options]")
  print("       atlas profile <list|show> [name]")
  print("       atlas auth <profile> [--logout]")
  print("       atlas completion <fish|bash|zsh>")
  print("")
  print("Options:")
  print("  --list                List all operations")
  print("  --help                Show operation documentation")
  print("  --body=JSON           Request body (inline JSON, @file, @-)")
  print("  -d JSON               Alias for --body")
  print("  --body.KEY=VAL        Build request body from individual fields")
  print("  --query.KEY=VAL       Query parameter")
  print("  --header.KEY=VAL      Per-request header")
  print("  --timeout=N           Timeout in seconds")
  print("  --base-url=URL        Override base URL")
  print("  --output=json|raw|status|headers  Output format (default: json)")
  print("  --select=PATH         Select nested value (e.g. .items[0].name)")
  print("  --no-color            Disable colored output")
  print("  -v, --verbose         Show status and response headers")
  print("  --reload              Re-fetch and re-cache the schema")
  print("  --cache-ttl=N         Schema cache TTL in seconds (default: 3600)")
  print("")
  print("Auth options (for 'atlas auth <profile>'):")
  print("  --logout              Clear cached token")
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
    local _61_
    do
      local t_60_ = profile
      if (nil ~= t_60_) then
        t_60_ = t_60_.ssl
      else
      end
      _61_ = t_60_
    end
    for k, v in pairs((_61_ or {})) do
      local k_22_, v_23_ = k, v
      if ((k_22_ ~= nil) and (v_23_ ~= nil)) then
        tbl_21_[k_22_] = v_23_
      else
      end
    end
    ssl = tbl_21_
  end
  local tls
  local function _65_()
    local t_64_ = profile
    if (nil ~= t_64_) then
      t_64_ = t_64_.tls
    else
    end
    return t_64_
  end
  tls = tls__3essl(_65_())
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
  local profiles
  local _70_
  do
    local t_69_ = config
    if (nil ~= t_69_) then
      t_69_ = t_69_.profiles
    else
    end
    _70_ = t_69_
  end
  profiles = (_70_ or {})
  local profile
  if profiles[profile_name] then
    profile = resolve_profile(profile_name, profiles, {})
  else
    profile = nil
  end
  assert(profile, ("Profile not found: " .. profile_name))
  local auth_cfg
  do
    local t_73_ = profile
    if (nil ~= t_73_) then
      t_73_ = t_73_.auth
    else
    end
    auth_cfg = t_73_
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
    local case_82_ = p.operation
    if (case_82_ == "fish") then
      return completion_fish()
    elseif (case_82_ == "bash") then
      return completion_bash()
    elseif (case_82_ == "zsh") then
      return completion_zsh()
    else
      local _ = case_82_
      return die("Usage: atlas completion <fish|bash|zsh>")
    end
  elseif (p.schema == "profile") then
    return run_profile(p.operation, p["path-params"][1], load_config())
  elseif (p.schema == "auth") then
    return run_auth(p.operation, p, load_config())
  else
    local config = load_config()
    local profiles
    local _85_
    do
      local t_84_ = config
      if (nil ~= t_84_) then
        t_84_ = t_84_.profiles
      else
      end
      _85_ = t_84_
    end
    profiles = (_85_ or {})
    local profile
    if profiles[p.schema] then
      profile = resolve_profile(p.schema, profiles, {})
    else
      profile = nil
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
        return print((op["cli/help"] or "No documentation available."))
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
        local body
        if (not p.body and next(p["body-params"])) then
          body = p["body-params"]
        else
          body = p.body
        end
        table.insert(call_args, body)
      else
      end
      if req_opts then
        table.insert(call_args, req_opts)
      else
      end
      local t0 = socket.gettime()
      local ok_r, resp = pcall(op, table.unpack(call_args))
      local elapsed = (socket.gettime() - t0)
      if ok_r then
        return print_resp(resp, p.output, p["no-color"], p.verbose, p.select, elapsed)
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
