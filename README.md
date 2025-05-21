# plg.nvim

## Bootstrap code
```lua
-- bootstrap_only.lua
-- Minimal bootstrap: install plg.nvim if missing (no updates)

local fn = vim.fn
local api = vim.api

-- Determine install path for plg.nvim
local install_path = fn.stdpath('data') .. '/site/pack/plg/start/plg.nvim'

-- Clone if not already installed
if fn.empty(fn.glob(install_path)) > 0 then
  print('Installing plg.nvim...')
  fn.system({
    'git',
    'clone',
    '--depth', '1',
    'https://github.com/MihneaTs1/plg.nvim',
    install_path,
  })
end

-- Add plg.nvim to runtimepath
vim.opt.rtp:prepend(install_path)

```
