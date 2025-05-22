-- lua/plg/init.lua
local fn  = vim.fn
local cmd = vim.cmd
local uv  = vim.loop

local M = {}

-- 1) initial list: plg.nvim itself
M.plugins = {
  { plugin = "MihneaTs1/plg.nvim" }
}

-- normalize a spec (string, array-shorthand, or full table) into a proper spec table
local function normalize_spec(spec)
  if type(spec) == "string" then
    -- "user/repo"
    spec = { plugin = spec }

  elseif type(spec) == "table" then
    -- array-shorthand: { "user/repo", lazy = true, … }
    if spec.plugin == nil then
      local shorthand = spec[1]
      if type(shorthand) == "string" then
        spec.plugin = shorthand
        spec[1] = nil
      else
        error("plg.nvim.use spec tables require a `.plugin` field or [1] = plugin string")
      end
    end
    assert(type(spec.plugin) == "string", "plg.nvim.use `plugin` must be a string")

    -- recursively normalize dependencies
    if spec.dependencies then
      for i, dep in ipairs(spec.dependencies) do
        spec.dependencies[i] = normalize_spec(dep)
      end
    end

  else
    error("plg.nvim.use received invalid spec type: " .. type(spec))
  end

  return spec
end

--- Declare a plugin (string, shorthand array, or full spec table)
-- @param spec string|table
function M.use(spec)
  spec = normalize_spec(spec)
  table.insert(M.plugins, spec)
end

--- Load plugin specs from a file or directory of files
-- Each file must `return { spec1, spec2, … }`
-- @param source string: path to a file or folder
function M.setup(source)
  local stat = assert(uv.fs_stat(source), "plg.nvim.setup: not found: " .. source)
  if stat.type == "file" then
    local specs = dofile(source)
    assert(type(specs) == "table", "plg.nvim.setup: file must return a table")
    for _, spec in ipairs(specs) do
      M.use(spec)
    end

  elseif stat.type == "directory" then
    local it = assert(uv.fs_scandir(source), "plg.nvim.setup: cannot scan " .. source)
    while true do
      local name, t = uv.fs_scandir_next(it)
      if not name then break end
      if t == "file" then
        local path = source .. "/" .. name
        local ok, specs = pcall(dofile, path)
        if ok and type(specs) == "table" then
          for _, spec in ipairs(specs) do
            M.use(spec)
          end
        end
      end
    end

  else
    error("plg.nvim.setup: unsupported type: " .. stat.type)
  end
end

-- internal: topologically gather specs & their dependencies
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
-- • missing ones are cloned (batch for unpinned, individual for pinned)
-- • start-plugins are packadded + config deferred
-- • opt-plugins have lazy-load autocommands
function M.install()
  local data_dir  = fn.stdpath("data")
  local start_dir = data_dir .. "/site/pack/plg/start/"
  local opt_dir   = data_dir .. "/site/pack/plg/opt/"

  -- 1) Topo-sort
  local seen, ordered = {}, {}
  for _, spec in ipairs(M.plugins) do
    gather(spec, seen, ordered)
  end

  -- 2) Clone missing repos
  local jobs, batch = {}, {}
  for _, item in ipairs(ordered) do
    local s, name = item.spec, item.name
    local target = (s.lazy and opt_dir or start_dir) .. name
    item.target = target

    if fn.empty(fn.glob(target)) > 0 then
      local url = "https://github.com/" .. s.plugin .. ".git"
      if s.version then
        table.insert(jobs, fn.jobstart({
          "git", "clone", "--depth", "1", "--branch", s.version, url, target
        }))
      else
        batch[#batch+1] = { url = url, tgt = target }
      end
    end
  end

  if #batch > 0 then
    local lines = {}
    for _, e in ipairs(batch) do
      lines[#lines+1] = e.url .. " " .. e.tgt
    end
    local list   = table.concat(lines, "\n")
    local cmdline = "printf '" .. list .. "' | xargs -P4 -n2 sh -c 'git clone --depth=1 \"$0\" \"$1\"'"
    table.insert(jobs, fn.jobstart({ "sh", "-c", cmdline }))
  end

  if #jobs > 0 then
    fn.jobwait(jobs, -1)
  end

  -- 3) packadd + config (deferred for start-plugins; lazy hooks for opt-plugins)
  for _, item in ipairs(ordered) do
    local s, name, tgt = item.spec, item.name, item.target
    if fn.isdirectory(tgt) == 1 then
      if not s.lazy then
        vim.defer_fn(function()
          cmd("packadd " .. name)
          if type(s.config) == "function" then pcall(s.config) end
        end, 0)
      else
        -- lazy: On Events
        if s.event then
          for _, ev in ipairs(type(s.event) == "table" and s.event or { s.event }) do
            vim.api.nvim_create_autocmd(ev, {
              callback = function()
                cmd("packadd " .. name)
                vim.defer_fn(function()
                  if type(s.config) == "function" then pcall(s.config) end
                end, 0)
              end,
            })
          end
        end
        -- lazy: On Commands
        if s.cmd then
          for _, c in ipairs(type(s.cmd) == "table" and s.cmd or { s.cmd }) do
            vim.api.nvim_create_user_command(c, function(opts)
              cmd("packadd " .. name)
              if type(s.config) == "function" then pcall(s.config) end
              vim.api.nvim_del_user_command(c)
              vim.api.nvim_exec(opts.args or "", false)
            end, { nargs = "*", bang = true })
          end
        end
        -- lazy: On FileType
        if s.ft then
          vim.api.nvim_create_autocmd("FileType", {
            pattern = type(s.ft) == "table" and s.ft or { s.ft },
            callback = function()
              cmd("packadd " .. name)
              if type(s.config) == "function" then pcall(s.config) end
            end,
          })
        end
      end
    end
  end
end

-- internal async finder: which plugins are behind their remotes
local function async_find_outdated(ordered, cb)
  local pending, out = #ordered, {}
  if pending == 0 then return cb(out) end

  for _, item in ipairs(ordered) do
    local tgt = fn.stdpath("data") .. "/site/pack/plg/start/" .. item.name
    if fn.isdirectory(tgt) == 1 then
      local cmdstr = ("git -C %s fetch --quiet && git -C %s rev-list --count HEAD..@{u}")
                     :format(tgt, tgt)
      fn.jobstart(cmdstr, {
        stdout_buffered = true,
        on_stdout = function(_, data)
          if tonumber(data[1]) and tonumber(data[1]) > 0 then
            out[#out+1] = item
          end
        end,
        on_exit = function()
          pending = pending - 1
          if pending == 0 then cb(out) end
        end,
      })
    else
      pending = pending - 1
      if pending == 0 then cb(out) end
    end
  end
end

--- Update only the outdated (skip pinned), async so UI never blocks
function M.update()
  local seen, ordered = {}, {}
  for _, spec in ipairs(M.plugins) do
    gather(spec, seen, ordered)
  end

  async_find_outdated(ordered, function(out)
    if #out == 0 then return end
    local jobs = {}
    for _, item in ipairs(out) do
      local s, name = item.spec, item.name
      if not s.version then
        local tgt = fn.stdpath("data") .. "/site/pack/plg/start/" .. name
        jobs[#jobs+1] = fn.jobstart({ "git", "-C", tgt, "pull", "--ff-only" })
      end
    end
    if #jobs > 0 then fn.jobwait(jobs, -1) end
  end)
end

return M
