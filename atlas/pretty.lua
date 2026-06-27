local colors = {reset = "\27[0m", key = "\27[36m", string = "\27[32m", number = "\27[33m", bool = "\27[35m", null = "\27[31m", punct = "\27[90m"}
local function c(color, s, use_color)
  if use_color then
    return (colors[color] .. s .. colors.reset)
  else
    return s
  end
end
local function array_3f(t)
  local count = 0
  local max_n = 0
  for k, _ in pairs(t) do
    count = (count + 1)
    if ((type(k) == "number") and (k > max_n)) then
      max_n = k
    else
    end
  end
  return (count == max_n)
end
local function pretty(v, indent, use_color)
  local ind = (indent or 0)
  local uc = (use_color ~= false)
  local pad = string.rep("  ", ind)
  local pad_2b = string.rep("  ", (ind + 1))
  local _3_ = type(v)
  if (_3_ == "table") then
    if (next(v) == nil) then
      return c("punct", "{}", uc)
    elseif array_3f(v) then
      local items
      do
        local tbl_21_ = {}
        local i_22_ = 0
        for _, x in ipairs(v) do
          local val_23_ = (pad_2b .. pretty(x, (ind + 1), uc))
          if (nil ~= val_23_) then
            i_22_ = (i_22_ + 1)
            tbl_21_[i_22_] = val_23_
          else
          end
        end
        items = tbl_21_
      end
      return (c("punct", "[", uc) .. "\n" .. table.concat(items, (c("punct", ",", uc) .. "\n")) .. "\n" .. pad .. c("punct", "]", uc))
    else
      local items = {}
      for k, x in pairs(v) do
        table.insert(items, (pad_2b .. c("key", string.format("%q", tostring(k)), uc) .. c("punct", ": ", uc) .. pretty(x, (ind + 1), uc)))
      end
      return (c("punct", "{", uc) .. "\n" .. table.concat(items, (c("punct", ",", uc) .. "\n")) .. "\n" .. pad .. c("punct", "}", uc))
    end
  elseif (_3_ == "string") then
    return c("string", string.format("%q", v), uc)
  elseif (_3_ == "number") then
    return c("number", tostring(v), uc)
  elseif (_3_ == "boolean") then
    return c("bool", tostring(v), uc)
  elseif (_3_ == "nil") then
    return c("null", "null", uc)
  else
    local _ = _3_
    return tostring(v)
  end
end
return {pretty = pretty}
