-- lua/plg/init.lua
local fn  = vim.fn
local cmd = vim.cmd
local uv  = vim.loop

local M = {}

-- 1) initial list: plg.nvim itself
M.plugins = {
  { plugin = "MihneaTs1/plg.nvim" }
}

--- Declare a plugin spec
--- @param spec table {
---   plugin       = "user/repo",     -- required
---   version?     = "tag-or-branch", -- optional pin
---   lazy?        = boolean,         -- install in opt/, not start/
---   event?       = string|{...},    -- Lazy-load on autocommand event
---   cmd?         = string|{...},    -- Lazy-load when user runs this cmd
---   ft?          = string|{...},    -- Lazy-load on FileType
---   config?      = function(),      -- Setup fn
---   dependencies?= { spec, ... }    -- Nested deps
--- }
function M.use(spec)
  assert(type(spec)=="table" and type(spec.plugin)=="string",
         "plg.nvim.use requires a table with a string `plugin` field")
  table.insert(M.plugins, spec)
end

-- internal: topologically gather specs & deps
local function gather(spec, seen, out)
  local name = spec.plugin:match("^.+/(.+)$")
  if seen[name] then return end
  seen[name] = true
  if spec.dependencies then
    for _, dep in ipairs(spec.dependencies) do
      gather(dep, seen, out)
    end
  end
  table.insert(out, { spec = spec, name = name })
end

--- Install all declared plugins
function M.install()
  local data_dir  = fn.stdpath("data")
  local start_dir = data_dir.."/site/pack/plg/start/"
  local opt_dir   = data_dir.."/site/pack/plg/opt/"

  -- 1) Topo-sort
  local seen, ordered = {}, {}
  for _, spec in ipairs(M.plugins) do
    gather(spec, seen, ordered)
  end

  -- 2) Clone missing repos
  local jobs, to_batch = {}, {}
  for _, item in ipairs(ordered) do
    local spec, name = item.spec, item.name
    local target = (spec.lazy and opt_dir or start_dir) .. name
    item.target = target

    if fn.empty(fn.glob(target)) > 0 then
      local url = "https://github.com/"..spec.plugin..".git"
      if spec.version then
        -- pinned clones one-by-one
        local args = { "git", "clone", "--depth", "1", "--branch", spec.version, url, target }
        print(("plg.nvim → cloning %s@%s"):format(spec.plugin, spec.version))
        table.insert(jobs, fn.jobstart(args))
      else
        -- unpinned get batched
        table.insert(to_batch, { url = url, target = target })
      end
    end
  end
  if #to_batch > 0 then
    -- build newline-separated "url target" list
    local list = {}
    for _, e in ipairs(to_batch) do
      table.insert(list, e.url .. " " .. e.target)
    end
    local list_str = table.concat(list, "\n")
    local shell_cmd = 
      "printf '"..list_str.."' | xargs -P4 -n2 sh -c 'git clone --depth=1 \"$0\" \"$1\"'"
    print("plg.nvim → batching clone of unversioned plugins")
    table.insert(jobs, fn.jobstart({ "sh", "-c", shell_cmd }))
  end
  if #jobs > 0 then
    fn.jobwait(jobs, -1)
  end

  -- 3) packadd + config for start-plugins, deferred
  for _, item in ipairs(ordered) do
    local spec, name = item.spec, item.name
    if fn.isdirectory(item.target) == 1 then
      if not spec.lazy then
        vim.defer_fn(function()
          cmd("packadd "..name)
          if type(spec.config)=="function" then
            pcall(spec.config)
          end
        end, 0)
      else
        -- lazy-load setup:
        --  a) on events
        if spec.event then
          local evs = type(spec.event)=="table" and spec.event or { spec.event }
          for _, ev in ipairs(evs) do
            vim.api.nvim_create_autocmd(ev, {
              callback = function()
                cmd("packadd "..name)
                if type(spec.config)=="function" then
                  vim.defer_fn(function() pcall(spec.config) end, 0)
                end
              end,
            })
          end
        end
        --  b) on commands
        if spec.cmd then
          local cmds = type(spec.cmd)=="table" and spec.cmd or { spec.cmd }
          for _, c in ipairs(cmds) do
            vim.api.nvim_create_user_command(c, function(opts)
              cmd("packadd "..name)
              if type(spec.config)=="function" then
                pcall(spec.config)
              end
              vim.api.nvim_del_user_command(c)
              vim.api.nvim_exec(opts.args or "", false)
            end, { nargs="*", bang=true })
          end
        end
        --  c) on FileType
        if spec.ft then
          local fts = type(spec.ft)=="table" and spec.ft or { spec.ft }
          vim.api.nvim_create_autocmd("FileType", {
            pattern = fts,
            callback = function()
              cmd("packadd "..name)
              if type(spec.config)=="function" then
                pcall(spec.config)
              end
            end,
          })
        end
      end
    end
  end

  -- 4) Generate a compiled one-shot loader for next startup
  M.compile_loader(ordered)
end

--- Generate `plugin/plg_compiled.lua` with profiling & cache
function M.compile_loader(ordered)
  local data_dir   = fn.stdpath("data")
  local plugin_dir = data_dir.."/site/pack/plg/start/plg.nvim/plugin"
  fn.mkdir(plugin_dir, "p")
  local cache_file = fn.stdpath("cache").."/plg_load_times.json"

  local lines = {
    "-- Autogenerated by plg.nvim — do not edit.",
    "local uv = vim.loop",
    "local load_times = {}",
    "local function load_plugin(name)",
    "  local s = uv.hrtime()",
    "  vim.cmd('packadd '..name)",
    "  local ms = (uv.hrtime() - s) / 1e6",
    "  if ms > 5 then",
    "    print(('⚡️ %s took %.1fms to load'):format(name, ms))",
    "  end",
    "  load_times[name] = ms",
    "end",
  }

  for _, item in ipairs(ordered) do
    if not item.spec.lazy then
      table.insert(lines, ("load_plugin('%s')"):format(item.name))
    end
  end
  table.insert(lines, ("vim.fn.writefile({vim.fn.json_encode(load_times)}, '%s')"):format(cache_file))

  local fp = assert(io.open(plugin_dir.."/plg_compiled.lua", "w"))
  fp:write(table.concat(lines, "\n"))
  fp:close()
end

-- internal: async check which plugins are behind
local function async_find_outdated(ordered, on_done)
  local pending = #ordered
  local outdated = {}
  if pending == 0 then return on_done(outdated) end

  for _, item in ipairs(ordered) do
    local target = fn.stdpath("data").."/site/pack/plg/start/"..item.name
    if fn.isdirectory(target) == 1 then
      local cmd_str = 
        "git -C "..target.." fetch --quiet && "..
        "git -C "..target.." rev-list --count HEAD..@{u}"
      fn.jobstart(cmd_str, {
        stdout_buffered = true,
        on_stdout = function(_, data)
          if tonumber(data[1]) and tonumber(data[1]) > 0 then
            table.insert(outdated, item)
          end
        end,
        on_exit = function()
          pending = pending - 1
          if pending == 0 then on_done(outdated) end
        end,
      })
    else
      pending = pending - 1
      if pending == 0 then on_done(outdated) end
    end
  end
end

--- Update only the outdated (and skip pinned), entirely async
function M.update()
  -- gather topo order
  local seen, ordered = {}, {}
  for _, spec in ipairs(M.plugins) do gather(spec, seen, ordered) end

  async_find_outdated(ordered, function(outdated)
    if #outdated == 0 then
      print("plg.nvim → all plugins up-to-date")
      return
    end
    local jobs = {}
    for _, item in ipairs(outdated) do
      local spec, name = item.spec, item.name
      local target = fn.stdpath("data").."/site/pack/plg/start/"..name
      if spec.version then
        print(("plg.nvim → pinned %s@%s → skipping update"):format(
          spec.plugin, spec.version))
      else
        print("plg.nvim → updating "..spec.plugin)
        table.insert(jobs,
          fn.jobstart({ "git", "-C", target, "pull", "--ff-only" }))
      end
    end
    if #jobs > 0 then
      fn.jobwait(jobs, -1)
      print("plg.nvim → updates complete")
    end
  end)
end

return M
