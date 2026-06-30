local function camel__3ekebab(s)
  local s0 = s:gsub("(%u+)(%u%l)", "%1-%2")
  local s1 = s0:gsub("(%l)(%u)", "%1-%2")
  return s1:lower()
end
local function extract_path_params(template)
  local tbl_26_ = {}
  local i_27_ = 0
  for p in template:gmatch("{([^}]+)}") do
    local val_28_ = p
    if (nil ~= val_28_) then
      i_27_ = (i_27_ + 1)
      tbl_26_[i_27_] = val_28_
    else
    end
  end
  return tbl_26_
end
local function resolve_path(template, args)
  local i = 0
  local function _2_(param)
    i = (i + 1)
    local v = args[i]
    assert(v, ("missing required path parameter: " .. param))
    return tostring(v)
  end
  return template:gsub("{([^}]+)}", _2_)
end
return {["camel->kebab"] = camel__3ekebab, ["extract-path-params"] = extract_path_params, ["resolve-path"] = resolve_path}
