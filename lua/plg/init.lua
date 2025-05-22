-- lua/plg/init.lua
local setup_module   = require("plg.core.setup")
local install_module = require("plg.core.install")

local M = {}

function M.setup(specs)
  setup_module.setup(specs)
  -- you could even run loading/config here:
  -- for _, spec in ipairs(specs) do
  --   if spec.config then spec.config() end
  -- end
end

function M.install()
  install_module.install()
end

vim.api.nvim_create_user_command("PlgInstall", M.install, {
  desc = "Install plugins declared via require('plg').setup()"
})

return M

