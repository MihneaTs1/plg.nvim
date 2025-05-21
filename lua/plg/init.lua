-- lua/plg.lua (this lives in the root of your plg.nvim repo under `lua/plg.lua`)
local fn = vim.fn
local M = {}
local pending = {}

-- add to install queue
function M.use(repo)
  table.insert(pending, repo)
end

-- clone any new plugins, then clear queue
function M.install()
  local data = fn.stdpath('data')
  for _, repo in ipairs(pending) do
    local name = repo:match('/([^/]+)$')
    local dest = data..'/site/pack/plg/start/'..name
    if fn.empty(fn.glob(dest)) > 0 then
      fn.system { 'git', 'clone', '--depth', '1',
        'https://github.com/'..repo, dest }
    end
  end
  pending = {}
end

-- pull latest for each installed plugin (silent)
function M.update()
  local data = fn.stdpath('data')
  local dir = data..'/site/pack/plg/start'
  for _, d in ipairs(fn.glob(dir..'/*', true, true)) do
    if fn.isdirectory(d) == 1 then
      fn.system { 'git', '-C', d, 'pull', '--ff-only' }
    end
  end
end

-- update the manager itself
function M.upgrade()
  local mgr = fn.stdpath('config')..'/autoload/plg.nvim'
  fn.system { 'git', '-C', mgr, 'pull', '--ff-only' }
end

return M
