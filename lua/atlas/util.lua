local function resolve_ref(root, ref_str)
  if (root and ref_str:match("^#/")) then
    local cur = root
    do
      local path = ref_str:sub(3)
      for part in path:gmatch("[^/]+") do
        if cur then
          cur = cur[part]
        else
        end
      end
    end
    return cur
  else
    return nil
  end
end
local function deref_deep(root, obj, _3fseen)
  if (type(obj) ~= "table") then
    return obj
  else
    local ref = obj["$ref"]
    if ref then
      local _4_
      do
        local t_3_ = _3fseen
        if (nil ~= t_3_) then
          t_3_ = t_3_[ref]
        else
        end
        _4_ = t_3_
      end
      if _4_ then
        return {}
      else
        local resolved = resolve_ref(root, ref)
        local seen
        do
          local tbl_21_ = {}
          for k, v in pairs((_3fseen or {})) do
            local k_22_, v_23_ = k, v
            if ((k_22_ ~= nil) and (v_23_ ~= nil)) then
              tbl_21_[k_22_] = v_23_
            else
            end
          end
          seen = tbl_21_
        end
        seen[ref] = true
        return deref_deep(root, (resolved or {}), seen)
      end
    else
      local tbl_21_ = {}
      for k, v in pairs(obj) do
        local k_22_, v_23_ = k, deref_deep(root, v, _3fseen)
        if ((k_22_ ~= nil) and (v_23_ ~= nil)) then
          tbl_21_[k_22_] = v_23_
        else
        end
      end
      return tbl_21_
    end
  end
end
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
  local function _12_(param)
    i = (i + 1)
    local v = args[i]
    assert(v, ("missing required path parameter: " .. param))
    return tostring(v)
  end
  return template:gsub("{([^}]+)}", _12_)
end
return {["camel->kebab"] = camel__3ekebab, ["extract-path-params"] = extract_path_params, ["resolve-path"] = resolve_path, ["deref-deep"] = deref_deep}
