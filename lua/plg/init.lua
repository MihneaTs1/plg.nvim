-- lua/plg/init.lua
local setup_module   = require("plg.core.setup")
local install_module = require("plg.core.install")

local M = {}

function M.setup(specs)
  setup_module.setup(specs)
  install_module.install()
  setup_module.load()
end

vim.api.nvim_create_user_command("PlgInstall", M.install, {
  desc = "Install plugins declared via require('plg').setup()"
})

return M

