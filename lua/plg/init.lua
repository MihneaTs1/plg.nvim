-- lua/plg/init.lua
local M = {}

-- 1) initial list: plg.nvim itself (unpinned)
M.plugins = {
  { plugin = "MihneaTs1/plg.nvim" }
}

--- Declare a plugin spec
-- @param spec table {
--   plugin      = "user/repo",           -- required
--   version?    = "tag-or-branch",       -- optional: pin to this ref
--   config?     = function() end,        -- optional setup
--   dependencies? = { spec, … }          -- optional deps
-- }
function M.use(spec)
  assert(type(spec) == "table" and type(spec.plugin) == "string",
         "plg.nvim.use requires a table with a string `plugin` field")
  table.insert(M.plugins, spec)
end

-- internal: gather specs in dependency order
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

--- Install all declared plugins:
-- • missing ones are cloned in parallel (using `--branch spec.version` if set)  
-- • then each is `packadd`ed and its `config()` called
function M.install()
  local fn      = vim.fn
  local cmd     = vim.cmd
  local packdir = fn.stdpath("data") .. "/site/pack/plg/start/"

  -- 1) topo‐sort into `ordered`
  local seen, ordered = {}, {}
  for _, spec in ipairs(M.plugins) do
    gather(spec, seen, ordered)
  end

  -- 2) clone missing repos in parallel
  local jobs = {}
  for _, item in ipairs(ordered) do
    local spec, name = item.spec, item.name
    local target = packdir .. name
    item.target = target

    if fn.empty(fn.glob(target)) > 0 then
      -- build git‐clone args
      local args = { "git", "clone", "--depth", "1" }
      if spec.version then
        table.insert(args, "--branch")
        table.insert(args, spec.version)
      end
      table.insert(args, "https://github.com/" .. spec.plugin .. ".git")
      table.insert(args, target)

      print(("plg.nvim → cloning %s%s"):format(
        spec.plugin,
        spec.version and "@" .. spec.version or ""
      ))
      jobs[#jobs + 1] = fn.jobstart(args)
    end
  end
  if #jobs > 0 then fn.jobwait(jobs, -1) end

  -- 3) packadd + config
  for _, item in ipairs(ordered) do
    if fn.isdirectory(item.target) == 1 then
      cmd("packadd " .. item.name)
      if type(item.spec.config) == "function" then
        pcall(item.spec.config)
      end
    end
  end
end

-- internal: async‐check which of `ordered` are behind their remotes
local function async_find_outdated(ordered, on_done)
  local fn      = vim.fn
  local pending = #ordered
  local outdated = {}

  if pending == 0 then return on_done(outdated) end

  for _, item in ipairs(ordered) do
    local name   = item.name
    local target = fn.stdpath("data") .. "/site/pack/plg/start/" .. name

    if fn.isdirectory(target) == 1 then
      local cmd_str = table.concat({
        "git -C", target,
        "fetch --quiet &&",
        "git -C", target,
        "rev-list --count HEAD..@{u}"
      }, " ")
      fn.jobstart(cmd_str, {
        stdout_buffered = true,
        on_stdout = function(_, data)
          local n = tonumber(data[1]) or 0
          if n > 0 then
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

--- Update only those plugins which:
-- • are actually behind their remote  
-- • AND were _not_ pinned via `version`
-- Runs entirely asynchronously so Neovim UI is never blocked.
function M.update()
  local fn      = vim.fn
  local packdir = fn.stdpath("data") .. "/site/pack/plg/start/"

  -- gather in topo order
  local seen, ordered = {}, {}
  for _, spec in ipairs(M.plugins) do
    gather(spec, seen, ordered)
  end

  -- async find outdated, then pull only unpinned ones
  async_find_outdated(ordered, function(outdated)
    if #outdated == 0 then
      print("plg.nvim → all plugins up-to-date")
      return
    end

    local jobs = {}
    for _, item in ipairs(outdated) do
      local spec, name = item.spec, item.name
      local target     = packdir .. name

      if spec.version then
        print(("plg.nvim → pinned %s@%s, skipping update")
              :format(spec.plugin, spec.version))
      else
        print("plg.nvim → updating " .. spec.plugin)
        jobs[#jobs + 1] = fn.jobstart({
          "git", "-C", target, "pull", "--ff-only"
        })
      end
    end

    if #jobs > 0 then
      fn.jobwait(jobs, -1)
      print("plg.nvim → updates complete")
    end
  end)
end

return M
