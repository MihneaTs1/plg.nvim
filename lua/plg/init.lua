-- lua/plg/init.lua
-- A minimal, single-file Neovim plugin manager with self-bootstrap, install, and update

local uv = vim.loop
local fn, api, defer = vim.fn, vim.api, vim.defer_fn
local M = { _plugins = {} }
local root = fn.stdpath('data') .. '/site/pack/plg'

-- Simple floating-window UI
local ui = {}
function ui.open(count)
  ui.total      = count
  ui.done_count = 0
  ui.buf        = api.nvim_create_buf(false, true)
  ui.win = api.nvim_open_win(ui.buf, false, {
    relative = 'editor', width = 50, height = 10,
    row = math.floor(vim.o.lines/2 - 5), col = math.floor(vim.o.columns/2 - 25),
    style = 'minimal', border = 'rounded',
  })
  api.nvim_buf_set_lines(ui.buf, 0, -1, false, { 'plg.nvim: processing plugins...' })
end
function ui.log(msg)
  if ui.buf and api.nvim_buf_is_valid(ui.buf) then
    local lines = api.nvim_buf_get_lines(ui.buf, 0, -1, false)
    table.insert(lines, msg)
    api.nvim_buf_set_lines(ui.buf, 0, -1, false, lines)
  end
end
function ui.mark_done(name, ok)
  ui.done_count = ui.done_count + 1
  ui.log(name .. (ok and ' ✔️' or ' ❌'))
  if ui.done_count >= ui.total then
    ui.log('All done.')
    defer(function()
      if api.nvim_win_is_valid(ui.win) then api.nvim_win_close(ui.win, true) end
    end, 0)
  end
end

-- 1. Self-bootstrap: clone or load plg.nvim
local self_path = root .. '/start/plg.nvim'
if fn.empty(fn.glob(self_path)) > 0 then
  print('Installing plg.nvim...')
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
  local stdout = uv.new_pipe(false)
  local stderr = uv.new_pipe(false)
  local handle
  handle = uv.spawn(cmd, {
    args   = args,
    stdio  = { nil, stdout, stderr },
    cwd    = cwd,
  }, function(code)
    stdout:close(); stderr:close(); handle:close()
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
  local install_list, check_list = {}, {}
  for repo,data in pairs(M._plugins) do
    local name = repo:match('.*/(.*)')
    local path = root .. '/start/' .. name
    local url  = 'https://github.com/' .. repo .. '.git'

    if fn.isdirectory(path) == 0 then
      table.insert(install_list, { repo=repo, name=name, path=path, url=url })
    else
      table.insert(check_list,   { repo=repo, name=name, path=path })
    end
  end

  -- nothing new at all?
  if #install_list + #check_list == 0 then
    return
  end

  -- open UI for initial checks + installs
  ui.open(#install_list + #check_list)

  -- 1) schedule all installs
  for _,p in ipairs(install_list) do
    ui.log('Installing ' .. p.name .. '…')
    git_async('git', { 'clone', '--depth', '1', p.url, p.path }, nil, p.name, function()
      vim.opt.rtp:append(p.path)
      local cfg = M._plugins[p.repo].config
      if type(cfg) == 'function' then
        defer(function() pcall(cfg) end, 10)
      end
    end)
  end

  -- 2) schedule all remote-HEAD checks
  for _,p in ipairs(check_list) do
    ui.log('Checking ' .. p.name .. '…')
    -- spawn ls-remote
    uv.spawn('git', {
      args  = { '-C', p.path, 'ls-remote', 'origin', 'HEAD' },
      stdio = { nil, uv.new_pipe(false), uv.new_pipe(false) },
    }, vim.schedule_wrap(function(code)
      -- once ls-remote exits, compare SHAs synchronously (fast disk/low-latency)
      local local_sha  = fn.systemlist({ 'git', '-C', p.path, 'rev-parse', 'HEAD' })[1]
      local remote_sha = fn.systemlist({ 'git', '-C', p.path, 'ls-remote', 'origin', 'HEAD' })[1]:match('^([a-f0-9]+)')
      if local_sha and remote_sha and local_sha ~= remote_sha then
        -- bump UI.total dynamically
        ui.total = ui.total + 1
        ui.log('Updating ' .. p.name .. '…')
        git_async('git', { '-C', p.path, 'pull', '--ff-only' }, p.path, p.name, function()
          vim.opt.rtp:append(p.path)
        end)
      end
      -- mark the check itself as done
      ui.mark_done(p.name, true)
    end))
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

-- Public interface: sync plugins (install + update)
function M.sync(specs_path)
  load_specs(specs_path)
  process_plugins()
end

-- Update-only command (UI box for updates)
function M.update()
  local updates = {}
  for repo in pairs(M._plugins) do
    local name = repo:match('.*/(.*)')
    local path = root .. '/start/' .. name
    if fn.isdirectory(path) == 1 then
      local local_sha = fn.systemlist({ 'git','-C',path,'rev-parse','HEAD' })[1]
      local info      = fn.systemlist({ 'git','-C',path,'ls-remote','origin','HEAD' })[1]
      local remote_sha= info and info:match('^([a-f0-9]+)')
      if local_sha and remote_sha and local_sha ~= remote_sha then
        table.insert(updates, { repo = repo, path = path, name = name })
      end
    end
  end

  if #updates == 0 then return end
  ui.open(#updates)
  for _, p in ipairs(updates) do
    ui.log('Updating ' .. p.name .. '...')
    git_async('git', { '-C',p.path,'pull','--ff-only' }, p.path, p.name)
  end
end

-- User commands
api.nvim_create_user_command('PlgSync', function(opts) M.sync(opts.args) end, { nargs = 1 })
api.nvim_create_user_command('PlgUpdate', M.update, {})
api.nvim_create_user_command('PlgList', function() end, {}) -- implement as needed
api.nvim_create_user_command('PlgClean', function() end, {})

-- Auto-check and apply updates after startup
vim.schedule(function()
  -- assumes specs were already loaded and installed via Sync
  M.update()
end)

return M
