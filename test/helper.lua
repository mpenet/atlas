-- ABOUTME: busted helper: puts the repo on package.path and installs
-- ABOUTME: the Fennel searcher so specs can be written in Fennel.
package.path = "./?.lua;./?/init.lua;" .. package.path
local ok, fennel = pcall(require, "fennel")
if ok then
  table.insert(package.searchers or package.loaders, fennel.searcher)
end
