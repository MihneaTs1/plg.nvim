# plg.nvim

## Bootstrap code
```lua
local function bootstrap_plg(specs_path)
  local install_path = vim.fn.stdpath("data") .. "/site/pack/plg/start/plg.nvim"
  local update_stamp = install_path .. "/.plg-last-update"

  -- Helper: check file age
  local function needs_update()
    local stat = vim.loop.fs_stat(update_stamp)
    if not stat then return true end
    local age = os.time() - stat.mtime.sec
    return age > 86400 -- > 1 day
  end

  -- Clone or update plugin manager
  if vim.fn.empty(vim.fn.glob(install_path)) > 0 then
    print("Installing plg.nvim...")
    vim.fn.system({ "git", "clone", "--depth", "1", "https://github.com/MihneaTs1/plg.nvim", install_path })
    vim.fn.writefile({ os.date() }, update_stamp) -- mark fresh install
  elseif needs_update() then
    print("Updating plg.nvim...")
    vim.fn.system({ "git", "-C", install_path, "pull", "--ff-only" })
    vim.fn.writefile({ os.date() }, update_stamp)
  end

  vim.opt.rtp:prepend(install_path)

  local ok, plg = pcall(require, "plg")
  if not ok then
    vim.notify("plg.nvim failed to load!", vim.log.levels.ERROR)
    return
  end

  -- Plugin loader
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

  -- Load from file or directory
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
