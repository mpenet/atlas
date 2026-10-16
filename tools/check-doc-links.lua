-- ABOUTME: Checks the links between the Markdown pages: every relative link
-- ABOUTME: must name an existing file, and every #anchor one of its headings.
--
-- usage: lua tools/check-doc-links.lua FILE.md...

-- GitHub's anchor for a heading: lower case, punctuation dropped, spaces as
-- dashes; repeated headings get -1, -2...
local function anchors(path)
  local found, seen, inside = {}, {}, false
  local f = io.open(path)
  if not f then return nil end
  for line in f:lines() do
    if line:match("^```") then inside = not inside end
    local text = not inside and line:match("^#+%s+(.-)%s*$")
    if text then
      local slug = text:lower():gsub("[^%w%s_%-]", ""):gsub("%s", "-")
      local n = seen[slug]
      seen[slug] = (n or -1) + 1
      found[n and (slug .. "-" .. (n + 1)) or slug] = true
    end
  end
  f:close()
  return found
end

local function dir(path)
  return path:match("^(.*)/[^/]*$") or "."
end

-- a/b/../c -> a/c
local function normalize(path)
  local parts = {}
  for part in path:gmatch("[^/]+") do
    if part == ".." and #parts > 0 and parts[#parts] ~= ".." then
      table.remove(parts)
    elseif part ~= "." then
      table.insert(parts, part)
    end
  end
  return table.concat(parts, "/")
end

local broken = 0
for _, path in ipairs({...}) do
  local inside, n = false, 0
  for line in io.lines(path) do
    n = n + 1
    if line:match("^```") then inside = not inside end
    if not inside then
      for target in line:gmatch("%]%(([^%)%s]+)%)") do
        if not target:match("^%a[%w+.-]*:") then
          local file, anchor = target:match("^([^#]*)#?(.*)$")
          local resolved = file == "" and path or normalize(dir(path) .. "/" .. file)
          local exists = io.open(resolved)
          if exists then exists:close() end
          local problem
          if not exists then
            problem = "no file " .. resolved
          elseif anchor ~= "" and resolved:match("%.md$") then
            local known = anchors(resolved)
            if not known[anchor] then problem = "no heading #" .. anchor .. " in " .. resolved end
          end
          if problem then
            broken = broken + 1
            print(string.format("%s:%d: %s: %s", path, n, target, problem))
          end
        end
      end
    end
  end
end

if broken > 0 then os.exit(1) end
