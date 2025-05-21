# plg.nvim

## Bootstrap code
```lua
-- plugin/plg-bootstrap.lua
-- Minimal bootstrap: silently install plg.nvim if missing, then invoke sync

local fn = vim.fn

-- 3. Check/install in pack directory (autoload isn’t needed for Lua modules)
local install_path = fn.stdpath('data') .. '/site/pack/plg/start/plg.nvim'
if fn.empty(fn.glob(install_path)) > 0 then
  fn.system({
    'git', 'clone', '--depth', '1',
    'https://github.com/MihneaTs1/plg.nvim',
    install_path,
  })
end

-- 4. Add to runtimepath
vim.opt.rtp:prepend(install_path)

-- 4. Call the manager to load specs and show UI as needed
--    Place your plugin spec files under ~/.config/nvim/lua/plugins/*.lua
require('plg').sync(fn.stdpath('config') .. '/lua/plugins')
```
