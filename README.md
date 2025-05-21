# plg.nvim

## Bootstrap code
```lua
function bootstrap_plg(specs_path)
  local plugpath = vim.fn.stdpath("data") .. "/site/pack/plg/start/plg.nvim"

  -- clone plg.nvim if missing
  if vim.fn.empty(vim.fn.glob(plugpath)) > 0 then
    print("Installing plg.nvim...")
    vim.fn.system({ "git", "clone", "--depth", "1", "https://github.com/MihneaTs1/plg.nvim", plugpath })
  else
    -- only update if local HEAD != remote HEAD
    local local_sha = vim.fn.systemlist({ "git", "-C", plugpath, "rev-parse", "HEAD" })[1]
    local remote_sha = vim.fn.systemlist({ "git", "-C", plugpath, "ls-remote", "origin", "HEAD" })[1]
    remote_sha = remote_sha and remote_sha:match("^([a-f0-9]+)")

    if local_sha and remote_sha and local_sha ~= remote_sha then
      print("Updating plg.nvim...")
      vim.fn.system({ "git", "-C", plugpath, "pull", "--ff-only" })
    end
  end

  vim.opt.rtp:prepend(plugpath)

  local ok, plg = pcall(require, "plg")
  if not ok then
    vim.notify("plg.nvim failed to load!", vim.log.levels.ERROR)
    return
  end

  local function load_spec_file(file)
    local chunk, err = loadfile(file)
    if not chunk then
      vim.notify("Failed to load spec: " .. file .. "\n" .. err, vim.log.levels.ERROR)
      return
    end

    local success, specs = pcall(chunk)
    if not success then
      vim.notify("Error running spec: " .. file .. "\n" .. specs, vim.log.levels.ERROR)
      return
    end

    if type(specs) == "table" then
      for _, spec in ipairs(specs) do
        if type(spec) == "string" then
          plg.use(spec)
        elseif type(spec) == "table" then
          plg.use(spec[1], spec)
        end
      end
    end
  end

  if vim.fn.isdirectory(specs_path) == 1 then
    local files = vim.fn.glob(specs_path .. "/*.lua", true, true)
    for _, file in ipairs(files) do
      load_spec_file(file)
    end
  else
    load_spec_file(specs_path)
  end

  plg.install()
end

bootstrap_plg(vim.fn.stdpath("config") .. "/lua/plugins/")
```
