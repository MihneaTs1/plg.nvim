-- lua/plg/init.lua
local M = {}

-- start with plg.nvim itself
M.plugins = {
  {
    plugin = "MihneaTs1/plg.nvim",
  }
}

--- Declare a plugin spec
-- @param spec table { plugin = "user/repo", config = fn or nil, dependencies = { spec, ... } or nil }
function M.use(spec)
  assert(type(spec) == "table" and type(spec.plugin) == "string",
         "plg.nvim `use` requires a table with a string `plugin` field")
  table.insert(M.plugins, spec)
end

--- Internal installer, handles one spec (and its dependencies) exactly once
local function install_one(spec, visited)
  local fn = vim.fn
  local cmd = vim.cmd

  -- extract repo name
  local name = spec.plugin:match("^.+/(.+)$")
  if visited[name] then return end
  visited[name] = true

  -- first install dependencies
  if spec.dependencies then
    for _, dep in ipairs(spec.dependencies) do
      install_one(dep, visited)
    end
  end

  -- then plugin itself
  local data_dir = fn.stdpath("data")
  local target = data_dir .. "/site/pack/plg/start/" .. name
  if fn.empty(fn.glob(target)) > 0 then
    print("plg.nvim → installing " .. spec.plugin)
    fn.system{
      "git", "clone", "--depth", "1",
      "https://github.com/" .. spec.plugin .. ".git",
      target,
    }
    cmd("packadd " .. name)
  end

  -- finally run its config (now that it's loaded)
  if type(spec.config) == "function" then
    pcall(spec.config)
  end
end

--- Install all declared plugins (recursively)
function M.install()
  local visited = {}
  for _, spec in ipairs(M.plugins) do
    install_one(spec, visited)
  end
end

return M
