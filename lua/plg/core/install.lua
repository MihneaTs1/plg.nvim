-- lua/plg/core/install.lua
local setup = require("plg.core.setup")
local fn    = vim.fn

local M = {}

-- Install one spec (and its deps) if not already there:
local function install_single(spec, base)
  local repo = spec.plugin
  local name = repo:match("^.+/(.+)$")
  local dest = base .. name

  -- first install dependencies
  if spec.dependencies then
    for _, dep in ipairs(spec.dependencies) do
      install_single(dep, base)
    end
  end

  -- then install this plugin
  if fn.isdirectory(dest) == 0 then
    fn.mkdir(base, "p")
    fn.system({ "git", "clone", repo, dest })
    print("plg.nvim: installed " .. repo)
  else
    -- already there
  end
end

function M.install()
  local base = fn.stdpath("data") .. "/site/pack/plg/start/"
  for _, spec in ipairs(setup.get_plugins()) do
    install_single(spec, base)
  end
end

return M

