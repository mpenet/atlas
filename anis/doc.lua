local util = require("anis.util")
local function params_of_kind(op_spec, kind)
  local tbl_21_ = {}
  local i_22_ = 0
  for _, p in ipairs((op_spec.parameters or {})) do
    local val_23_
    if (p["in"] == kind) then
      val_23_ = p
    else
      val_23_ = nil
    end
    if (nil ~= val_23_) then
      i_22_ = (i_22_ + 1)
      tbl_21_[i_22_] = val_23_
    else
    end
  end
  return tbl_21_
end
local function param_type(p)
  local _4_
  do
    local t_3_ = p
    if (nil ~= t_3_) then
      t_3_ = t_3_.schema
    else
    end
    if (nil ~= t_3_) then
      t_3_ = t_3_.type
    else
    end
    _4_ = t_3_
  end
  return (_4_ or "any")
end
local function param_extras(p, required_3f)
  local parts = {}
  if required_3f then
    table.insert(parts, "[required]")
  else
  end
  local _9_
  do
    local t_8_ = p
    if (nil ~= t_8_) then
      t_8_ = t_8_.schema
    else
    end
    if (nil ~= t_8_) then
      t_8_ = t_8_.enum
    else
    end
    _9_ = t_8_
  end
  if _9_ then
    table.insert(parts, ("[" .. table.concat(p.schema.enum, "|") .. "]"))
  else
  end
  local _14_
  do
    local t_13_ = p
    if (nil ~= t_13_) then
      t_13_ = t_13_.schema
    else
    end
    if (nil ~= t_13_) then
      t_13_ = t_13_.default
    else
    end
    _14_ = t_13_
  end
  if _14_ then
    table.insert(parts, ("(default: " .. tostring(p.schema.default) .. ")"))
  else
  end
  if p.description then
    table.insert(parts, ("\226\128\148 " .. p.description))
  else
  end
  if (#parts > 0) then
    return (" " .. table.concat(parts, " "))
  else
    return ""
  end
end
local function body_schema(request_body)
  local content = request_body.content
  local schema
  local _21_
  do
    local t_20_ = content
    if (nil ~= t_20_) then
      t_20_ = t_20_["application/json"]
    else
    end
    if (nil ~= t_20_) then
      t_20_ = t_20_.schema
    else
    end
    _21_ = t_20_
  end
  local or_24_ = _21_
  if not or_24_ then
    local t_25_ = content
    if (nil ~= t_25_) then
      t_25_ = t_25_["application/x-www-form-urlencoded"]
    else
    end
    if (nil ~= t_25_) then
      t_25_ = t_25_.schema
    else
    end
    or_24_ = t_25_
  end
  if not or_24_ then
    local k = next((content or {}))
    if k then
      local t_29_ = content
      if (nil ~= t_29_) then
        t_29_ = t_29_[k]
      else
      end
      if (nil ~= t_29_) then
        t_29_ = t_29_.schema
      else
      end
      or_24_ = t_29_
    else
      or_24_ = nil
    end
  end
  schema = or_24_
  if (schema and schema.properties) then
    local required_set = {}
    for _, r in ipairs((schema.required or {})) do
      required_set[r] = true
    end
    return {properties = schema.properties, required = required_set}
  else
    return nil
  end
end
local function build(path, method, op_spec)
  local lines = {}
  local add
  local function _34_(_241)
    return table.insert(lines, _241)
  end
  add = _34_
  local path_params = params_of_kind(op_spec, "path")
  local query_params = params_of_kind(op_spec, "query")
  local has_body_3f = (nil ~= op_spec.requestBody)
  add(string.format("%s %s", method:upper(), path))
  if op_spec.summary then
    add(("\n" .. op_spec.summary))
  else
  end
  if (op_spec.description and (op_spec.description ~= op_spec.summary)) then
    add(op_spec.description)
  else
  end
  do
    local sig = {}
    for _, p in ipairs(path_params) do
      table.insert(sig, p.name)
    end
    if has_body_3f then
      table.insert(sig, "body")
    else
    end
    if (#query_params > 0) then
      table.insert(sig, "?opts")
    else
    end
    add(string.format("\nUsage: (%s %s)", util["camel->kebab"](op_spec.operationId), table.concat(sig, " ")))
  end
  if (#path_params > 0) then
    add("\nPath params:")
    for _, p in ipairs(path_params) do
      add(string.format("  %-16s %s%s", p.name, param_type(p), param_extras(p, true)))
    end
  else
  end
  if (#query_params > 0) then
    add("\nQuery params (via {:query {...}}):")
    for _, p in ipairs(query_params) do
      add(string.format("  %-16s %s%s", p.name, param_type(p), param_extras(p, p.required)))
    end
  else
  end
  if op_spec.requestBody then
    local rb = op_spec.requestBody
    local bschema = body_schema(rb)
    local _41_
    if rb.required then
      _41_ = "required"
    else
      _41_ = "optional"
    end
    local function _43_()
      if rb.description then
        return (" \226\128\148 " .. rb.description)
      else
        return ""
      end
    end
    add(string.format("\nBody: %s%s", _41_, _43_()))
    if bschema then
      for name, prop in pairs(bschema.properties) do
        local _44_
        if bschema.required[name] then
          _44_ = " [required]"
        else
          _44_ = ""
        end
        local function _46_()
          if prop.description then
            return (" \226\128\148 " .. prop.description)
          else
            return ""
          end
        end
        add(string.format("  %-16s %s%s%s", name, (prop.type or "any"), _44_, _46_()))
      end
    else
    end
  else
  end
  add("\nResponses:")
  for code, resp in pairs((op_spec.responses or {})) do
    add(string.format("  %-6s %s", tostring(code), (resp.description or "")))
  end
  return table.concat(lines, "\n")
end
return {build = build}
