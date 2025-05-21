-- lua/plg/init.lua
-- A minimal, async Neovim plugin manager: auto-install, notify updates, and commands with simple UI

local uv = vim.loop
local fn, api, schedule, notify = vim.fn, vim.api, vim.schedule, vim.notify
local M = { _plugins = {} }
local data_path = fn.stdpath('data') .. '/site/pack/plg'

-- Bootstrap: clone plg if missing
local function bootstrap()
  local path = data_path .. '/start/plg.nvim'
  if fn.empty(fn.glob(path)) > 0 then
    notify('Installing plg.nvim...', vim.log.levels.INFO)
    fn.system({ 'git', 'clone', '--depth', '1', 'https://github.com/MihneaTs1/plg.nvim', path })
  end
  vim.opt.rtp:prepend(path)
end

-- Register a plugin spec
function M.use(repo, opts)
  opts = opts or {}
  if not M._plugins[repo] then
    M._plugins[repo] = { repo = repo, config = opts.config, deps = opts.dependencies or {} }
    for _, d in ipairs(opts.dependencies or {}) do
      if type(d) == 'string' then M.use(d)
      elseif type(d) == 'table' then M.use(d[1], d) end
    end
  end
end

-- Load spec files
local function load_specs(specs)
  local paths = {}
  if fn.isdirectory(specs) == 1 then
    for _, f in ipairs(fn.glob(specs .. '/*.lua', true, true)) do table.insert(paths, f) end
  else
    table.insert(paths, specs)
  end
  for _, f in ipairs(paths) do
    local ok, specs = pcall(assert(loadfile(f)))
    if not ok then api.nvim_err_writeln('plg.nvim: error loading '..f..': '..specs)
    elseif type(specs) == 'table' then for _, s in ipairs(specs) do
        if type(s)=='string' then M.use(s)
        else M.use(s[1], s) end
      end
    end
  end
end

-- Async git command helper
local function git_job(cmd, args, cwd, on_exit)
  local stderr = uv.new_pipe(false)
  uv.spawn(cmd, { args=args, stdio={nil, nil, stderr}, cwd=cwd }, function(code)
    stderr:close()
    if on_exit then schedule(function() on_exit(code==0) end) end
  end)
end

-- Install missing plugins
function M.sync(specs)
  load_specs(specs)
  local to_install = {}
  for repo,_ in pairs(M._plugins) do
    local name = repo:match('.*/(.*)')
    local path = data_path..'/start/'..name
    if fn.isdirectory(path)==0 then table.insert(to_install,{repo=repo,name=name,path=path}) end
  end
  if #to_install>0 then
    notify('Installing plugins: '..table.concat(vim.tbl_map(function(p)return p.name end,to_install),', '), vim.log.levels.INFO)
    for _,p in ipairs(to_install) do
      git_job('git',{'clone','--depth','1','https://github.com/'..p.repo..'.git',p.path},nil,function(ok)
        if ok then
          vim.opt.rtp:append(p.path)
          if type(M._plugins[p.repo].config)=='function' then schedule(function() pcall(M._plugins[p.repo].config) end) end
        else notify('Failed to install '..p.name, vim.log.levels.ERROR) end
      end)
    end
  end
  -- Notify updates available
  local outdated = {}
  for repo,_ in pairs(M._plugins) do
    local name=repo:match('.*/(.*)')
    local path=data_path..'/start/'..name
    if fn.isdirectory(path)==1 then
      local local_sha = fn.systemlist({'git','-C',path,'rev-parse','HEAD'})[1]
      local remote = fn.systemlist({'git','-C',path,'ls-remote','origin','HEAD'})[1]
      local remote_sha = remote and remote:match('^([a-f0-9]+)')
      if local_sha and remote_sha and local_sha~=remote_sha then table.insert(outdated,name) end
    end
  end
  if #outdated>0 then
    notify('Updates available for: '..table.concat(outdated,', '), vim.log.levels.WARN)
  end
end

-- Update command: update selected plugins
function M.update()
  local list = {}
  for repo,_ in pairs(M._plugins) do
    local name=repo:match('.*/(.*)')
    table.insert(list,name)
  end
  vim.ui.select(list,{prompt='Update plugin:'},function(choice)
    if choice then
      local path=data_path..'/start/'..choice
      notify('Updating '..choice, vim.log.levels.INFO)
      git_job('git',{'-C',path,'pull','--ff-only'},path,function(ok)
        if ok then notify(choice..' updated',vim.log.levels.INFO)
        else notify('Failed to update '..choice, vim.log.levels.ERROR) end
      end)
    end
  end)
end

-- List command: show loaded plugins
function M.list()
  local buf=api.nvim_create_buf(false,true)
  api.nvim_buf_set_lines(buf,0,-1,false,vim.tbl_map(function(r)
    return '• '..r:match('.*/(.*)') end, vim.tbl_keys(M._plugins)))
  api.nvim_open_win(buf,true,{relative='editor',width=30,height=math.min(10,#vim.tbl_keys(M._plugins)+2),row=5,col=5,style='minimal',border='rounded'})
end

-- Clean command: remove dirs not in specs
function M.clean()
  local dirs=fn.glob(data_path..'/start/*',true,true)
  local known={}
  for repo,_ in pairs(M._plugins) do known[repo:match('.*/(.*)')]=true end
  for _,d in ipairs(dirs) do
    local n=fn.fnamemodify(d,':t')
    if not known[n] then
      fn.delete(d,'rf')
      notify('Removed '..n, vim.log.levels.INFO)
    end
  end
end

-- User commands
api.nvim_create_user_command('PlgSync', function(opts) M.sync(opts.args) end, { nargs=1 })
api.nvim_create_user_command('PlgUpdate', M.update, {})
api.nvim_create_user_command('PlgList', M.list, {})
api.nvim_create_user_command('PlgClean', M.clean, {})

-- Boot + sync on startup
bootstrap()
schedule(function() M.sync(vim.fn.stdpath('config')..'/lua/plugins') end)

return M
