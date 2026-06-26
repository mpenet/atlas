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
local function build(path, method, op_spec)
  local lines = {}
  local add
  local function _7_(_241)
    return table.insert(lines, _241)
  end
  add = _7_
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
      local function _12_()
        if p.description then
          return (" \226\128\148 " .. p.description)
        else
          return ""
        end
      end
      add(string.format("  %-14s %s%s", p.name, param_type(p), _12_()))
    end
  else
  end
  if (#query_params > 0) then
    add("\nQuery params:")
    for _, p in ipairs(query_params) do
      local _14_
      if p.required then
        _14_ = " [required]"
      else
        _14_ = ""
      end
      local function _16_()
        if p.description then
          return (" \226\128\148 " .. p.description)
        else
          return ""
        end
      end
      add(string.format("  %-14s %s%s%s", p.name, param_type(p), _14_, _16_()))
    end
  else
  end
  if op_spec.requestBody then
    local _18_
    if op_spec.requestBody.required then
      _18_ = "required"
    else
      _18_ = "optional"
    end
    local function _20_()
      if op_spec.requestBody.description then
        return (" \226\128\148 " .. op_spec.requestBody.description)
      else
        return ""
      end
    end
    add(string.format("\nBody: %s%s", _18_, _20_()))
  else
  end
  add("\nResponses:")
  for code, resp in pairs((op_spec.responses or {})) do
    add(string.format("  %-6s %s", tostring(code), (resp.description or "")))
  end
  return table.concat(lines, "\n")
end
return {build = build}
