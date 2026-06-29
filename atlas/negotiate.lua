local preferred = {"application/json", "application/x-www-form-urlencoded", "multipart/form-data"}
local function pick_media_type(content)
  if content then
    local found = nil
    for _, mt in ipairs(preferred) do
      if found then break end
      if content[mt] then
        found = mt
      else
      end
    end
    if not found then
      for k, _ in pairs(content) do
        if found then break end
        found = k
      end
    else
    end
    return found
  else
    return nil
  end
end
local function pick_content_type(op_spec)
  if op_spec.requestBody then
    return pick_media_type(op_spec.requestBody.content)
  else
    return nil
  end
end
local function pick_accept(op_spec)
  local seen = {}
  local types = {}
  for _, resp in pairs((op_spec.responses or {})) do
    for mt, _0 in pairs((resp.content or {})) do
      if not seen[mt] then
        seen[mt] = true
        table.insert(types, mt)
      else
      end
    end
  end
  if (#types > 0) then
    table.sort(types)
    return table.concat(types, ", ")
  else
    return nil
  end
end
return {["pick-content-type"] = pick_content_type, ["pick-accept"] = pick_accept}
