-- File: lua/plg/core/install.lua
local setup = require("plg.core.setup")
local fn    = vim.fn

local M = {}

local function git_url(repo)
  -- use full URL if provided, else assume GitHub
  if repo:match("://") then return repo end
  return "https://github.com/" .. repo .. ".git"
end

---
-- Asynchronously clone plugins (and their dependencies) in parallel.
-- @param on_complete function to call once all jobs finish
---
function M.install(on_complete)
  local base = fn.stdpath("data") .. "/site/pack/plg/start/"
  local pending = 0

  local function attempt_complete()
    pending = pending - 1
    if pending == 0 and on_complete then
      vim.schedule(on_complete)
    end
  end

  local function install_single(spec)
    local repo = spec.plugin
    local url  = git_url(repo)
    local name = repo:match("^.+/(.+)$")
    local dest = base .. name

    -- Recurse into dependencies first
    if spec.dependencies then
      for _, dep in ipairs(spec.dependencies) do
        install_single(dep)
      end
    end

    if fn.isdirectory(dest) == 0 then
      fn.mkdir(base, "p")
      pending = pending + 1
      local cmd = { "git", "clone", "--depth", "1", url, dest }
      fn.jobstart(cmd, {
        on_exit = function(_, code)
          vim.schedule(function()
            if code == 0 then
              print("plg.nvim: installed " .. repo)
            else
              print("plg.nvim: failed to install " .. repo)
            end
            attempt_complete()
          end)
        end,
      })
    end
  end

  for _, spec in ipairs(setup.get_plugins()) do
    install_single(spec)
  end

  -- if nothing to install, fire callback immediately
  if pending == 0 and on_complete then
    vim.schedule(on_complete)
  end
end

return M


-- File: lua/plg/init.lua
local setup_mod   = require("plg.core.setup")
local install_mod = require("plg.core.install")

local M = {}

---
-- One-shot setup: record specs, clone missing plugins async, then load configs.
-- @param specs table list of plugin specs
---
function M.setup(specs)
  setup_mod.setup(specs)
  install_mod.install(function()
    setup_mod.load()
  end)
end

return M

