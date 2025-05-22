-- lua/plg/core/setup.lua
local M = {
  _plugins = {}
}

local function validate_spec(spec)
  assert(type(spec) == "table", "each plugin spec must be a table")
  assert(type(spec.plugin) == "string", "'plugin' field is required and must be a string")
  if spec.dependencies then
    assert(type(spec.dependencies) == "table",
      "'dependencies' must be a list of plugin specs")
    for _, dep in ipairs(spec.dependencies) do
      validate_spec(dep)
    end
  end
  if spec.config then
    assert(type(spec.config) == "function",
      "'config' must be a function")
  end
end

--- User calls this in their init.lua:
function M.setup(specs)
  assert(type(specs) == "table", "plg.setup() expects a table of plugin specs")
  for _, spec in ipairs(specs) do
    validate_spec(spec)
  end
  M._plugins = specs
end

function M.load()
  for _, spec in ipairs(M._plugins) do
    local name = spec.plugin:match("^.+/(.+)$")
    -- first ensure it’s on runtimepath
    vim.cmd("packadd " .. name)
    -- then run user’s config()
    if spec.config then
      spec.config()
    end
  end
end

--- Other modules call this to get the list:
function M.get_plugins()
  return M._plugins
end

return M

