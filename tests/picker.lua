vim.o.columns = 160
vim.o.lines = 50

local config = require("jam.config").setup({
  artwork = { enabled = false },
})

local search_requests = 0
local provider = {
  search = function(_, query, _, callback)
    search_requests = search_requests + 1
    vim.defer_fn(function()
      callback(nil, {
        {
          id = "track-one",
          uri = "spotify:track:one",
          kind = "track",
          name = query .. " result one",
          subtitle = "Test Artist",
          description = "A   test\npodcast " .. string.rep("with a long description ", 20),
        },
        {
          id = "track-two",
          uri = "spotify:track:two",
          kind = "track",
          name = query .. " result two",
          subtitle = "Test Artist",
        },
      })
    end, 20)
  end,
}

require("jam.ui.picker").open(provider, config, { default_text = "swim bts" })

local prompt_buffer
assert(
  vim.wait(1000, function()
    for _, buffer in ipairs(vim.api.nvim_list_bufs()) do
      if vim.bo[buffer].filetype == "TelescopePrompt" then
        prompt_buffer = buffer
        return true
      end
    end
    return false
  end),
  "Telescope prompt did not open"
)

local action_state = require("telescope.actions.state")
local picker = action_state.get_current_picker(prompt_buffer)
assert(
  vim.wait(1000, function()
    return type(picker.manager) == "table" and picker.manager:num_results() == 2
  end),
  "search results did not populate"
)

local function visible_results()
  local lines = vim.api.nvim_buf_get_lines(picker.results_bufnr, 0, -1, false)
  return vim.tbl_filter(function(line)
    return line ~= ""
  end, lines)
end

assert(#visible_results() == 2, "search result buffer was blank before resize")
picker:set_selection(picker:get_row(1))
assert(
  vim.wait(1000, function()
    for _, buffer in ipairs(vim.api.nvim_list_bufs()) do
      if
        buffer ~= picker.results_bufnr
        and buffer ~= prompt_buffer
        and vim.api.nvim_buf_is_valid(buffer)
      then
        local preview = table.concat(vim.api.nvim_buf_get_lines(buffer, 0, -1, false), "\n")
        if preview:find("A test podcast", 1, true) and preview:find("…", 1, true) then
          return true
        end
      end
    end
    return false
  end),
  "preview description metadata did not render"
)
vim.o.columns = math.max(80, vim.o.columns - 20)
vim.o.lines = math.max(24, vim.o.lines - 5)
vim.cmd("doautocmd VimResized")
assert(
  vim.wait(1000, function()
    return #visible_results() == 2
  end),
  "search result buffer was blank after resize"
)
vim.wait(500, function()
  return false
end)
assert(search_requests == 1, "resizing triggered another provider search")

require("telescope.actions").close(prompt_buffer)
print("jam.nvim picker tests passed")
