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
  local case_3_ = type(v)
  if (case_3_ == "table") then
    if (next(v) == nil) then
      return c("punct", "{}", uc)
    elseif array_3f(v) then
      local items
      do
        local tbl_26_ = {}
        local i_27_ = 0
        for _, x in ipairs(v) do
          local val_28_ = (pad_2b .. pretty(x, (ind + 1), uc))
          if (nil ~= val_28_) then
            i_27_ = (i_27_ + 1)
            tbl_26_[i_27_] = val_28_
          else
          end
        end
        items = tbl_26_
      end
      return (c("punct", "[", uc) .. "\n" .. table.concat(items, (c("punct", ",", uc) .. "\n")) .. "\n" .. pad .. c("punct", "]", uc))
    else
      local items = {}
      for k, x in pairs(v) do
        table.insert(items, (pad_2b .. c("key", string.format("%q", tostring(k)), uc) .. c("punct", ": ", uc) .. pretty(x, (ind + 1), uc)))
      end
      return (c("punct", "{", uc) .. "\n" .. table.concat(items, (c("punct", ",", uc) .. "\n")) .. "\n" .. pad .. c("punct", "}", uc))
    end
  elseif (case_3_ == "string") then
    return c("string", string.format("%q", v), uc)
  elseif (case_3_ == "number") then
    return c("number", tostring(v), uc)
  elseif (case_3_ == "boolean") then
    return c("bool", tostring(v), uc)
  elseif (case_3_ == "nil") then
    return c("null", "null", uc)
  else
    local _ = case_3_
    return tostring(v)
  end
end
local function yaml_needs_quotes_3f(s)
  return ((s == "") or s:match("^[0-9]") or s:match("^[-~|>!&*%%@`#,{}%[%]:]") or s:match("[\n\r\t]") or s:match(":[ \t]") or s:match(" #") or s:match("^%s") or s:match("%s$") or (s == "true") or (s == "false") or (s == "null") or (s == "~") or (s == ".inf") or (s == "-.inf") or (s == ".nan"))
end
local function yaml_escape(s)
  return s:gsub("\\", "\\\\"):gsub("\"", "\\\""):gsub("\n", "\\n"):gsub("\r", "\\r"):gsub("\t", "\\t")
end
local function yaml(v, _3findent, _3fuse_color)
  local ind = (_3findent or 0)
  local uc = (_3fuse_color ~= false)
  local pad = string.rep("  ", ind)
  local case_7_ = type(v)
  if (case_7_ == "table") then
    if (next(v) == nil) then
      return c("punct", "{}", uc)
    elseif array_3f(v) then
      local lines = {}
      for _, x in ipairs(v) do
        local rendered = yaml(x, (ind + 1), uc)
        if rendered:match("^\n") then
          table.insert(lines, (pad .. c("punct", "-", uc) .. " " .. rendered:gsub("^\n%s*", "")))
        else
          table.insert(lines, (pad .. c("punct", "-", uc) .. " " .. rendered))
        end
      end
      return ("\n" .. table.concat(lines, "\n"))
    else
      local lines = {}
      for k, x in pairs(v) do
        local key = tostring(k)
        local rendered = yaml(x, (ind + 1), uc)
        if rendered:match("^\n") then
          table.insert(lines, (pad .. c("key", key, uc) .. c("punct", ":", uc) .. rendered))
        else
          table.insert(lines, (pad .. c("key", key, uc) .. c("punct", ":", uc) .. " " .. rendered))
        end
      end
      return ("\n" .. table.concat(lines, "\n"))
    end
  elseif (case_7_ == "string") then
    local s
    if yaml_needs_quotes_3f(v) then
      s = ("\"" .. yaml_escape(v) .. "\"")
    else
      s = v
    end
    return c("string", s, uc)
  elseif (case_7_ == "number") then
    return c("number", tostring(v), uc)
  elseif (case_7_ == "boolean") then
    return c("bool", tostring(v), uc)
  else
    local _ = case_7_
    return c("null", "null", uc)
  end
end
return {pretty = pretty, yaml = yaml}
