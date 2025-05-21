# plg.nvim

## Bootstrap code
```lua
-- bootstrap.lua (put this in ~/.config/nvim/lua/bootstrap.lua and call it from your init.lua with `require'bootstrap'`)
local fn = vim.fn
local install_path = fn.stdpath'config'..'/autoload/plg.nvim'

if fn.empty(fn.glob(install_path)) > 0 then
  fn.system {
    'git', 'clone', '--depth', '1',
    'https://github.com/MihneaTs1/plg.nvim',
    install_path,
  }
end

vim.opt.rtp:prepend(install_path)
return require'plg'

```
