package.path = "./?.lua;./?/init.lua;" .. package.path
local ok, fennel = pcall(require, "fennel")
if ok then
  table.insert(package.searchers or package.loaders, fennel.searcher)
end
