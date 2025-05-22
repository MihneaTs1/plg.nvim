-- lua/plg/init.lua
local M = {}

-- Start with plg.nvim itself
M.plugins = { "MihneaTs1/plg.nvim" }

--- Add a plugin (e.g. "user/repo")
---@param plugin string
function M.use(plugin)
  table.insert(M.plugins, plugin)
end

--- Install any plugins in M.plugins that aren't already cloned
function M.install()
  local fn = vim.fn
  local data_dir = fn.stdpath("data")
  local pack_dir = data_dir .. "/site/pack/plg/start/"

  for _, plugin in ipairs(M.plugins) do
    -- derive folder name from "user/name"
    local name = plugin:match("^.+/(.+)$")
    local target = pack_dir .. name

    if fn.empty(fn.glob(target)) > 0 then
      print("plg.nvim → installing " .. plugin)
      fn.system({
        "git", "clone", "--depth", "1",
        "https://github.com/" .. plugin .. ".git",
        target,
      })
      vim.cmd("packadd " .. name)
    end
  end
end

return M
