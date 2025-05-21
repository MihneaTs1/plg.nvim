local uv = vim.loop
local ui = require("plg.ui")
local plg = {}
local PlgRoot = vim.fn.stdpath("data") .. "/site/pack/plg/start"

vim.fn.mkdir(PlgRoot, "p")

plg._plugins = {}

function plg.use(repo, opts)
    opts = opts or {}
    if not plg._plugins[repo] then
        plg._plugins[repo] = { config = opts.config, done = false }
        if opts.dependencies then
            for _, dep in ipairs(opts.dependencies) do
                if type(dep) == "string" then
                    plg.use(dep)
                elseif type(dep) == "table" then
                    plg.use(dep[1], dep)
                end
            end
        end
    end
end

local function run_git_async(cmd, args, cwd, name, on_success)
    local stdout = uv.new_pipe(false)
    local stderr = uv.new_pipe(false)

    local handle
    handle = uv.spawn(cmd, {
        args = args,
        stdio = { nil, stdout, stderr },
        cwd = cwd,
    }, function(code)
        stdout:close()
        stderr:close()
        handle:close()
        vim.schedule(function()
            if code == 0 then
                if on_success then on_success() end
                ui.mark_done(name, true)
            else
                ui.mark_done(name, false)
            end
        end)
    end)

    stdout:read_start(function() end)
    stderr:read_start(function() end)
end

function plg.install()
  local repos = vim.tbl_keys(plg._plugins)
  if #repos == 0 then return end

  local new_plugins = {}
  local already_installed = {}

  for _, repo in ipairs(repos) do
    local name = repo:match(".*/(.*)")
    local path = PlgRoot .. "/" .. name
    local is_installed = vim.fn.isdirectory(path) == 1 and vim.fn.isdirectory(path .. "/.git") == 1
    if not is_installed then
      table.insert(new_plugins, { repo = repo, path = path, name = name })
    else
      table.insert(already_installed, { repo = repo, path = path, name = name })
    end
  end

  -- Only show UI window if installing new plugins
  if #new_plugins > 0 then
    require("plg.ui").open(#repos)
  end

  local function finish(repo, path)
    vim.opt.runtimepath:append(path)
    plg._plugins[repo].done = true
    local cfg = plg._plugins[repo].config
    if type(cfg) == "function" then
      vim.defer_fn(function()
        pcall(cfg)
      end, 10)
    end
  end

  -- Install new plugins (show UI)
  for _, item in ipairs(new_plugins) do
    local url = "https://github.com/" .. item.repo .. ".git"
    require("plg.ui").log("Installing " .. item.name .. "...")
    run_git_async("git", { "clone", "--depth", "1", url, item.path }, nil, item.name, function()
      finish(item.repo, item.path)
    end)
  end

  -- Update existing plugins (silent)
  for _, item in ipairs(already_installed) do
    run_git_async("git", { "-C", item.path, "pull", "--ff-only" }, item.path, item.name, function()
      finish(item.repo, item.path)
    end)
  end
end

-- Add UI commands

-- :PlgSync — full install
vim.api.nvim_create_user_command("PlgSync", function()
    plg.install()
end, {})

-- :PlgUpdate — only update installed
vim.api.nvim_create_user_command("PlgUpdate", function()
    local repos = vim.tbl_keys(plg._plugins)
    if #repos == 0 then return end

    local ui = require("plg.ui")
    ui.open(#repos)

    for _, repo in ipairs(repos) do
        local name = repo:match(".*/(.*)")
        local path = PlgRoot .. "/" .. name

        local function finish()
            vim.opt.runtimepath:append(path)
            plg._plugins[repo].done = true
            local cfg = plg._plugins[repo].config
            if type(cfg) == "function" then
                vim.defer_fn(function()
                    pcall(cfg)
                end, 10)
            end
        end

        if vim.fn.isdirectory(path) == 1 and vim.fn.isdirectory(path .. "/.git") == 1 then
            ui.log("Updating " .. name .. "...")
            run_git_async("git", { "pull", "--ff-only" }, path, name, finish)
        else
            ui.mark_done(name, false)
        end
    end
end, {})

-- :PlgClean — delete unused plugin folders
vim.api.nvim_create_user_command("PlgClean", function()
    local existing_dirs = vim.fn.glob(PlgRoot .. "/*", 1, 1)
    local known = {}
    for repo in pairs(plg._plugins) do
        local name = repo:match(".*/(.*)")
        known[name] = true
    end

    local ui = require("plg.ui")
    local to_delete = {}

    for _, dir in ipairs(existing_dirs) do
        local name = vim.fn.fnamemodify(dir, ":t")
        if not known[name] then
            table.insert(to_delete, { name = name, path = dir })
        end
    end

    if #to_delete == 0 then
        print("No unused plugins to remove.")
        return
    end

    ui.open(#to_delete)

    for _, item in ipairs(to_delete) do
        vim.fn.delete(item.path, "rf")
        ui.log("Deleted " .. item.name)
        ui.mark_done(item.name, true)
    end
end, {})

-- :PlgList — list all declared plugins

vim.api.nvim_create_user_command("PlgList", function()
    local ui = require("plg.ui")
    local repos = vim.tbl_keys(plg._plugins)

    local buf = vim.api.nvim_create_buf(false, true)
    local win = vim.api.nvim_open_win(buf, true, {
        relative = "editor",
        width = 60,
        height = math.min(10, #repos + 2),
        row = math.floor(vim.o.lines / 2 - 5),
        col = math.floor(vim.o.columns / 2 - 30),
        style = "minimal",
        border = "rounded",
    })

    local lines = { "plg.nvim: Registered Plugins" }
    for _, repo in ipairs(repos) do
        local name = repo:match(".*/(.*)")
        table.insert(lines, "• " .. name)
    end
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

    -- Buffer options
    vim.bo[buf].filetype = "plglist"
    vim.bo[buf].buftype = "nofile"
    vim.bo[buf].bufhidden = "wipe"
    vim.bo[buf].modifiable = false
    vim.bo[buf].swapfile = false

    -- Keymaps inside buffer
    vim.keymap.set("n", "q", function()
        if vim.api.nvim_win_is_valid(win) then
            vim.api.nvim_win_close(win, true)
        end
    end, { buffer = buf, silent = true })

    vim.keymap.set("n", "<Esc>", function()
        if vim.api.nvim_win_is_valid(win) then
            vim.api.nvim_win_close(win, true)
        end
    end, { buffer = buf, silent = true })

    -- Optional: close when leaving buffer
    vim.api.nvim_create_autocmd("BufLeave", {
        buffer = buf,
        callback = function()
            if vim.api.nvim_win_is_valid(win) then
                vim.api.nvim_win_close(win, true)
            end
        end
    })

    -- Put you inside the window so keymaps actually trigger
    vim.api.nvim_set_current_win(win)
end, {})

return plg
