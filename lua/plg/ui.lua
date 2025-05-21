local M = {}

local win, buf
local lines = {}
local total = 0
local done = 0

function M.open(count)
  total = count
  done = 0
  lines = {}

  buf = vim.api.nvim_create_buf(false, true)
  win = vim.api.nvim_open_win(buf, false, {
    relative = "editor",
    width = 50,
    height = 10,
    row = math.floor(vim.o.lines / 2 - 5),
    col = math.floor(vim.o.columns / 2 - 25),
    style = "minimal",
    border = "rounded",
  })

  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "plg.nvim: installing plugins..." })
end

function M.log(msg)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return -- skip if UI wasn't opened
  end
  table.insert(lines, msg)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
end

function M.mark_done(name, ok)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return
  end

  done = done + 1
  local symbol = ok and "✔️" or "❌"
  M.log(name .. " " .. symbol)

  if done >= total then
    M.log("All done. Closing...")
    vim.defer_fn(function()
      if vim.api.nvim_win_is_valid(win) then
        vim.api.nvim_win_close(win, true)
      end
    end, 1000)
  end
end

return M
