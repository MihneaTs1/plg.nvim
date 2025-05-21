-- lua/plg/init.lua
-- A minimal, single-file Neovim plugin manager with self-bootstrap, install, and update (lazy notifications)

local uv = vim.loop
local fn, api, defer = vim.fn, vim.api, vim.defer_fn
local M = { _plugins = {} }
local root = fn.stdpath('data') .. '/site/pack/plg'

-- Notification-based UI (no floating window)
local ui = {}
local notify = vim.notify or function(msg, level)
  api.nvim_echo({{msg}}, true, {})
end
function ui.open(count)
  ui.total = count
  ui.done_count = 0
  notify(('plg.nvim: processing %d plugins...'):format(count), vim.log.levels.INFO)
end
function ui.log(msg)
  notify(msg, vim.log.levels.INFO)
end
function ui.mark_done(name, ok)
  ui.done_count = ui.done_count + 1
  notify(name .. (ok and ' ✔️' or ' ❌'), vim.log.levels.INFO)
  if ui.done_count >= ui.total then
    notify('plg.nvim: All done.', vim.log.levels.INFO)
  end
end

-- 1. Self-bootstrap: clone or load plg.nvim itself
local self_path = root .. '/start/plg.nvim'
if fn.empty(fn.glob(self_path)) > 0 then
  notify('Installing plg.nvim...', vim.log.levels.INFO)
  fn.system({ 'git', 'clone', '--depth', '1', 'https://github.com/MihneaTs1/plg.nvim', self_path })
end
vim.opt.rtp:prepend(self_path)

-- 1a. Register plg.nvim for internal update checks
M._plugins['MihneaTs1/plg.nvim'] = { repo = 'MihneaTs1/plg.nvim', config = nil }

-- 2. Define plugin specification
function M.use(repo, opts)
  opts = opts or {}
  if not M._plugins[repo] then
    M._plugins[repo] = { repo = repo, config = opts.config }
    if opts.dependencies then
      for _, d in ipairs(opts.dependencies) do
        if type(d) == 'string' then M.use(d) else M.use(d[1], d) end
      end
    end
  end
end

-- Internal: run git commands asynchronously
local function git_async(cmd, args, cwd, name, cb)
  local stdout, stderr = uv.new_pipe(false), uv.new_pipe(false)
  local handle
  handle = uv.spawn(cmd, { args = args, stdio = { nil, stdout, stderr }, cwd = cwd }, function(code)
    stdout:close(); stderr:close(); handle:close();
    vim.schedule(function()
      ui.mark_done(name, code == 0)
      if code == 0 and cb then cb() end
    end)
  end)
  stdout:read_start(function() end)
  stderr:read_start(function() end)
end

-- 3 & 4. Determine missing vs outdated and perform operations
local function process_plugins()
  local install_list, update_list = {}, {}
  for repo in pairs(M._plugins) do
    local name = repo:match('.*/(.*)')
    local path = root .. '/start/' .. name
    local url = 'https://github.com/' .. repo .. '.git'

    if fn.isdirectory(path) == 0 then
      table.insert(install_list, { repo = repo, path = path, name = name, url = url })
    else
      -- Check remote HEAD only if installed
      local local_sha = fn.systemlist({ 'git', '-C', path, 'rev-parse', 'HEAD' })[1]
      local remote_info = fn.systemlist({ 'git', '-C', path, 'ls-remote', 'origin', 'HEAD' })[1]
      local remote_sha = remote_info and remote_info:match('^([a-f0-9]+)')
      if local_sha and remote_sha and local_sha ~= remote_sha then
        table.insert(update_list, { repo = repo, path = path, name = name, url = url })
      end
    end
  end

  local total = #install_list + #update_list
  if total == 0 then return end

  ui.open(total)

  -- Perform installs
  for _, p in ipairs(install_list) do
    ui.log('Installing ' .. p.name .. '...')
    git_async('git', { 'clone', '--depth', '1', p.url, p.path }, nil, p.name, function()
      vim.opt.rtp:append(p.path)
      if type(M._plugins[p.repo].config) == 'function' then
        defer(function() pcall(M._plugins[p.repo].config) end, 10)
      end
    end)
  end

  -- Perform updates
  for _, p in ipairs(update_list) do
    ui.log('Updating ' .. p.name .. '...')
    git_async('git', { '-C', p.path, 'pull', '--ff-only' }, p.path, p.name, function()
      vim.opt.rtp:append(p.path)
    end)
  end
end

-- 5. Load user spec files
local function load_specs(specs_path)
  local files = fn.isdirectory(specs_path) == 1 and fn.glob(specs_path .. '/*.lua', true, true) or { specs_path }
  for _, f in ipairs(files) do
    local ok, specs = pcall(assert(loadfile(f)))
    if not ok then api.nvim_err_writeln('plg.nvim: error loading ' .. f .. ': ' .. specs) end
    if type(specs) == 'table' then
      for _, s in ipairs(specs) do
        if type(s) == 'string' then M.use(s) else M.use(s[1], s) end
      end
    end
  end
end

-- Public interface: sync plugins
function M.sync(specs_path)
  load_specs(specs_path)
  process_plugins()
end

return M
