local function camel__3ekebab(s)
  local s0 = s:gsub("(%u+)(%u%l)", "%1-%2")
  local s1 = s0:gsub("(%l)(%u)", "%1-%2")
  return s1:lower()
end
local function extract_path_params(template)
  local tbl_21_ = {}
  local i_22_ = 0
  for p in template:gmatch("{([^}]+)}") do
    local val_23_ = p
    if (nil ~= val_23_) then
      i_22_ = (i_22_ + 1)
      tbl_21_[i_22_] = val_23_
    else
    end
  end
  return tbl_21_
end
local function resolve_path(template, args)
  local i = 0
  local function _2_(_)
    i = (i + 1)
    return tostring(args[i])
  end
  return template:gsub("{[^}]+}", _2_)
end
return {["camel->kebab"] = camel__3ekebab, ["extract-path-params"] = extract_path_params, ["resolve-path"] = resolve_path}
