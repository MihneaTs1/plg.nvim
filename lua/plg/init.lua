-- lua/plg/init.lua
local setup_module   = require("plg.core.setup")
local install_module = require("plg.core.install")

local M = {}

function M.setup(specs)
  setup_module.setup(specs)
  install_module.install()
  setup_module.load()
end

return M

