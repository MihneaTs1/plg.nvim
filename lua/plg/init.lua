-- lua/plg/init.lua
local M = {}

-- 1) initial list contains plg.nvim itself
M.plugins = {
  { plugin = "MihneaTs1/plg.nvim" }
}

--- Declare a plugin spec
-- @param spec table { plugin = "user/repo", config = fn or nil, dependencies = { spec, ... } }
function M.use(spec)
  assert(type(spec) == "table" and type(spec.plugin) == "string",
         "plg.nvim `use` requires a table with a string `plugin` field")
  table.insert(M.plugins, spec)
end

-- internal: gather specs in dependency order
local function gather(spec, visited, ordered)
  local name = spec.plugin:match("^.+/(.+)$")
  if visited[name] then return end
  visited[name] = true
  if spec.dependencies then
    for _, dep in ipairs(spec.dependencies) do
      gather(dep, visited, ordered)
    end
  end
  table.insert(ordered, { spec = spec, name = name })
end

--- Install all declared plugins (missing ones in parallel), then packadd+config
function M.install()
  local fn      = vim.fn
  local cmd     = vim.cmd
  local packdir = fn.stdpath("data") .. "/site/pack/plg/start/"

  -- 1) topologically sort
  local visited, ordered = {}, {}
  for _, spec in ipairs(M.plugins) do
    gather(spec, visited, ordered)
  end

  -- 2) parallel git-clone for missing
  local jobs = {}
  for _, item in ipairs(ordered) do
    local target = packdir .. item.name
    if fn.empty(fn.glob(target)) > 0 then
      print("plg.nvim → cloning " .. item.spec.plugin)
      local args = {
        "git", "clone", "--depth", "1",
        "https://github.com/" .. item.spec.plugin .. ".git",
        target,
      }
      table.insert(jobs, fn.jobstart(args))
    end
    item.target = target
  end
  if #jobs > 0 then
    fn.jobwait(jobs, -1)
  end

  -- 3) load & config
  for _, item in ipairs(ordered) do
    if fn.isdirectory(item.target) == 1 then
      cmd("packadd " .. item.name)
      if type(item.spec.config) == "function" then
        pcall(item.spec.config)
      end
    end
  end
end

--- Check which installed plugins are behind their remotes
-- @return list of { name = <repo-name>, behind = <commit-count> }
function M.check_updates()
  local fn      = vim.fn
  local packdir = fn.stdpath("data") .. "/site/pack/plg/start/"
  local outdated = {}

  for _, spec in ipairs(M.plugins) do
    local name   = spec.plugin:match("^.+/(.+)$")
    local target = packdir .. name
    if fn.isdirectory(target) == 1 then
      -- fetch remote
      fn.system({ "git", "-C", target, "fetch", "--quiet" })
      -- count commits ahead of us
      local cnt = tonumber(fn.system({
        "git", "-C", target, "rev-list", "--count", "HEAD..@{u}"
      })) or 0
      if cnt > 0 then
        table.insert(outdated, { name = name, behind = cnt })
      end
    end
  end

  return outdated
end

--- Pull updates for all installed plugins in parallel
function M.update()
  local fn      = vim.fn
  local packdir = fn.stdpath("data") .. "/site/pack/plg/start/"
  local jobs    = {}

  for _, spec in ipairs(M.plugins) do
    local name   = spec.plugin:match("^.+/(.+)$")
    local target = packdir .. name
    if fn.isdirectory(target) == 1 then
      print("plg.nvim → updating " .. spec.plugin)
      table.insert(jobs, fn.jobstart({
        "git", "-C", target, "pull", "--ff-only"
      }))
    end
  end

  if #jobs > 0 then
    fn.jobwait(jobs, -1)
    print("plg.nvim → all updates complete")
  else
    print("plg.nvim → no updates found")
  end
end

return M
