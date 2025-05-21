# plg.nvim

## Bootstrap code
```lua
local function bootstrap_plugins(specs_path)
  local root = vim.fn.stdpath("data") .. "/site/pack/plugins/start"
  vim.fn.mkdir(root, "p")

  local function add(repo, opts)
    opts = opts or {}
    local name = repo:match(".*/(.*)")
    local path = root .. "/" .. name

    if vim.fn.isdirectory(path) == 0 then
      local url = "https://github.com/" .. repo .. ".git"
      print("Installing " .. repo .. "...")
      vim.fn.system({ "git", "clone", "--depth", "1", url, path })
    end

    vim.opt.runtimepath:append(path)

    if type(opts.config) == "function" then
      pcall(opts.config)
    end

    if opts.dependencies then
      for _, dep in ipairs(opts.dependencies) do
        if type(dep) == "string" then
          add(dep)
        elseif type(dep) == "table" then
          add(dep[1], dep)
        end
      end
    end
  end

  local ok, specs = pcall(dofile, specs_path)
  if not ok then
    vim.notify("Failed to load plugin specs: " .. specs_path, vim.log.levels.ERROR)
    return
  end

  for _, spec in ipairs(specs) do
    if type(spec) == "string" then
      add(spec)
    elseif type(spec) == "table" then
      add(spec[1], spec)
    end
  end
end
```
