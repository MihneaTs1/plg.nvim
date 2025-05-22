-- lua/plg/init.lua
local M = {}

-- initial list: plg.nvim itself
M.plugins = {
  { plugin = "MihneaTs1/plg.nvim" }
}

--- Declare a plugin spec
-- @param spec { plugin= "user/repo", config=fn?, dependencies={...}? }
function M.use(spec)
  assert(type(spec)=="table" and type(spec.plugin)=="string",
         "plg.nvim.use needs a table with a string `plugin` field")
  table.insert(M.plugins, spec)
end

-- internal: gather in topological order
local function gather(spec, seen, out)
  local name = spec.plugin:match("^.+/(.+)$")
  if seen[name] then return end
  seen[name] = true
  if spec.dependencies then
    for _, dep in ipairs(spec.dependencies) do
      gather(dep, seen, out)
    end
  end
  table.insert(out, { spec=spec, name=name })
end

--- Install missing plugins in parallel, then packadd+config
function M.install()
  local fn      = vim.fn
  local cmd     = vim.cmd
  local packdir = fn.stdpath("data").."/site/pack/plg/start/"

  -- 1) topo sort
  local seen, ordered = {}, {}
  for _, spec in ipairs(M.plugins) do
    gather(spec, seen, ordered)
  end

  -- 2) parallel git clone
  local jobs = {}
  for _, item in ipairs(ordered) do
    local target = packdir..item.name
    item.target = target
    if fn.empty(fn.glob(target))>0 then
      print("plg.nvim → cloning "..item.spec.plugin)
      jobs[#jobs+1] = fn.jobstart({
        "git","clone","--depth","1",
        "https://github.com/"..item.spec.plugin..".git",
        target,
      })
    end
  end
  if #jobs>0 then fn.jobwait(jobs, -1) end

  -- 3) packadd + config()
  for _, item in ipairs(ordered) do
    if fn.isdirectory(item.target)==1 then
      cmd("packadd "..item.name)
      if type(item.spec.config)=="function" then
        pcall(item.spec.config)
      end
    end
  end
end

-- internal: async check which of `ordered` are behind
local function async_find_outdated(ordered, on_done)
  local fn      = vim.fn
  local total   = #ordered
  if total==0 then return on_done({}) end
  local pending = total
  local outdated = {}

  for _, item in ipairs(ordered) do
    local t = item
    local target = fn.stdpath("data").."/site/pack/plg/start/"..t.name
    if fn.isdirectory(target)==1 then
      -- fetch & count behind
      local cmd = "git -C "..target.." fetch --quiet && " ..
                  "git -C "..target.." rev-list --count HEAD..@{u}"
      fn.jobstart(cmd, {
        stdout_buffered = true,
        on_stdout = function(_, data)
          local n = tonumber(data[1]) or 0
          if n>0 then
            t.target = target
            table.insert(outdated, t)
          end
        end,
        on_exit = function()
          pending = pending - 1
          if pending==0 then on_done(outdated) end
        end,
      })
    else
      pending = pending - 1
      if pending==0 then on_done(outdated) end
    end
  end
end

--- Async‐only‐outdated update
-- kicks off the check & pull in the background
function M.update()
  local fn      = vim.fn
  local packdir = fn.stdpath("data").."/site/pack/plg/start/"

  -- gather in topo order
  local seen, ordered = {}, {}
  for _, spec in ipairs(M.plugins) do
    gather(spec, seen, ordered)
  end

  -- non-blocking: find outdated, then pull only those
  async_find_outdated(ordered, function(outdated)
    if #outdated==0 then
      -- print("plg.nvim → all plugins up-to-date")
      return
    end
    local jobs = {}
    for _, item in ipairs(outdated) do
      print("plg.nvim → updating "..item.spec.plugin)
      jobs[#jobs+1] = fn.jobstart({
        "git","-C",item.target,"pull","--ff-only"
      })
    end
    if #jobs>0 then
      fn.jobwait(jobs, -1)
      print("plg.nvim → updates complete")
    end
  end)
end

return M
