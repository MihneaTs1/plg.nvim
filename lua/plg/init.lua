-- lua/plg/init.lua
local M = {}

-- start with plg.nvim itself
M.plugins = {
  { plugin = "MihneaTs1/plg.nvim" }
}

--- Declare a plugin spec
-- @param spec table { plugin = "user/repo", config = fn or nil, dependencies = { spec, ... } or nil }
function M.use(spec)
  assert(type(spec) == "table" and type(spec.plugin) == "string",
         "plg.nvim `use` requires a table with a string `plugin` field")
  table.insert(M.plugins, spec)
end

--- Install all declared plugins, cloning missing ones in parallel
function M.install()
  local fn  = vim.fn
  local cmd = vim.cmd
  local data_dir = fn.stdpath("data")
  local pack_dir = data_dir .. "/site/pack/plg/start/"

  -- 1) Topologically sort all specs (deps first)
  local visited = {}
  local ordered = {}
  local function gather(spec)
    local name = spec.plugin:match("^.+/(.+)$")
    if visited[name] then return end
    visited[name] = true
    if spec.dependencies then
      for _, dep in ipairs(spec.dependencies) do
        gather(dep)
      end
    end
    table.insert(ordered, { spec = spec, name = name })
  end
  for _, spec in ipairs(M.plugins) do
    gather(spec)
  end

  -- 2) Launch git‐clone jobs for every missing repo
  local jobs = {}
  for _, item in ipairs(ordered) do
    item.target = pack_dir .. item.name
    if fn.empty(fn.glob(item.target)) > 0 then
      print("plg.nvim → cloning " .. item.spec.plugin)
      local cmd_args = {
        "git", "clone", "--depth", "1",
        "https://github.com/" .. item.spec.plugin .. ".git",
        item.target,
      }
      table.insert(jobs, fn.jobstart(cmd_args))
    end
  end

  -- 3) Wait for all clones to finish
  if #jobs > 0 then
    fn.jobwait(jobs, -1)
  end

  -- 4) packadd & config in dependency order
  for _, item in ipairs(ordered) do
    if fn.isdirectory(item.target) == 1 then
      cmd("packadd " .. item.name)
      if type(item.spec.config) == "function" then
        pcall(item.spec.config)
      end
    end
  end
end

return M
