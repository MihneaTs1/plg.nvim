local plg = require("plg")

-- Load all plugins from plugins.lua
local function load_plugins()
    local ok, err = pcall(require, "plugins")
    if not ok then
        vim.notify("plg.nvim: failed to load plugins: " .. err, vim.log.levels.ERROR)
    end
end

-- Check if plugins are missing (i.e. never installed)
local function needs_install()
    for repo, _ in pairs(plg._plugins or {}) do
        local name = repo:match(".*/(.*)")
        local path = vim.fn.stdpath("data") .. "/site/pack/plg/start/" .. name
        if vim.fn.empty(vim.fn.glob(path)) == 1 then
            return true
        end
    end
    return false
end

load_plugins()

-- If missing plugins, do install
vim.schedule(function()
    if needs_install() then
        vim.notify("plg.nvim: installing plugins...", vim.log.levels.INFO)
        plg.install()
    else
        -- Still append runtimepaths + config (for reload or after lazy-load)
        for repo, data in pairs(plg._plugins or {}) do
            local name = repo:match(".*/(.*)")
            local path = vim.fn.stdpath("data") .. "/site/pack/plg/start/" .. name
            if vim.fn.isdirectory(path) == 1 then
                vim.opt.runtimepath:append(path)
                if type(data.config) == "function" then
                    pcall(data.config)
                end
            end
        end
    end
end)
