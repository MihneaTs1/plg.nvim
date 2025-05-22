# plg.nvim

## Bootstrap code
```lua
-- Bootstrap plg.nvim
local fn = vim.fn
local install_path = fn.stdpath('data') .. '/site/pack/plg/start/plg.nvim'

if fn.empty(fn.glob(install_path)) > 0 then
  fn.system({
    'git',
    'clone',
    '--depth', '1',
    'https://github.com/MihneaTs1/plg.nvim',
    install_path,
  })
  -- add to runtimepath
  vim.cmd('packadd plg.nvim')
end

-- now load plg.nvim
-- require('plg').setup()
```
