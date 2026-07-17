local artwork = require("jam.ui.artwork")
local util = require("jam.util")

local M = {}

local kind_icons = {
  track = "♪",
  album = "▣",
  artist = "●",
  playlist = "≡",
}

local function duration(milliseconds)
  if not milliseconds then
    return ""
  end
  local seconds = math.floor(milliseconds / 1000)
  return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end

local function entry_maker(item)
  local label = string.format(
    "%s  %-36s  %s",
    kind_icons[item.kind] or "·",
    item.name or "Unknown",
    item.subtitle or ""
  )
  return {
    value = item,
    display = label,
    ordinal = table.concat(
      { item.name or "", item.subtitle or "", item.album or "", item.kind or "" },
      " "
    ),
  }
end

local function async_finder(provider, search_config)
  local finder = { generation = 0, timer = nil, closed = false }

  function finder:close()
    self.closed = true
    if self.timer then
      self.timer:stop()
      self.timer:close()
      self.timer = nil
    end
  end

  return setmetatable(finder, {
    __call = function(self, prompt, process_result, process_complete)
      self.generation = self.generation + 1
      local generation = self.generation
      if self.timer then
        self.timer:stop()
        self.timer:close()
      end
      if not prompt or vim.trim(prompt) == "" then
        process_complete()
        return
      end

      local timer = vim.uv.new_timer()
      self.timer = timer
      timer:start(search_config.debounce_ms, 0, function()
        timer:stop()
        timer:close()
        if self.timer == timer then
          self.timer = nil
        end
        vim.schedule(function()
          provider:search(prompt, search_config, function(err, results)
            if self.closed or generation ~= self.generation then
              process_complete()
              return
            end
            if err then
              util.notify(err, vim.log.levels.ERROR)
              process_complete()
              return
            end
            for _, item in ipairs(results) do
              if process_result(entry_maker(item)) then
                break
              end
            end
            process_complete()
          end)
        end)
      end)
    end,
  })
end

local function previewer(artwork_config)
  local previewers = require("telescope.previewers")
  return previewers.new_buffer_previewer({
    title = "Album",
    define_preview = function(self, entry)
      local item = entry.value
      artwork.clear(self.state.bufnr)
      vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, {
        item.name or "Unknown",
        item.subtitle or "",
        item.album and ("Album: " .. item.album) or "",
        item.kind and ("Type: " .. item.kind) or "",
        item.duration_ms and ("Duration: " .. duration(item.duration_ms)) or "",
        "",
        item.image_url or "No album artwork",
      })
      artwork.render(self.state.bufnr, self.state.winid, item.image_url, artwork_config)
    end,
    teardown = function(self)
      artwork.clear(self.state.bufnr)
    end,
  })
end

local function run_action(provider, method, item, success)
  provider[method](provider, item, function(err)
    if err then
      util.notify(err, vim.log.levels.ERROR)
      return
    end
    util.notify(success)
  end)
end

function M.open(provider, config, opts)
  opts = opts or {}
  local ok, pickers = pcall(require, "telescope.pickers")
  if not ok then
    util.notify("telescope.nvim is required to open Jam", vim.log.levels.ERROR)
    return
  end

  local actions = require("telescope.actions")
  local action_state = require("telescope.actions.state")
  local telescope_config = require("telescope.config").values
  local picker_opts = vim.tbl_deep_extend("force", config.picker, opts)

  pickers
    .new(picker_opts, {
      prompt_title = "jam.nvim · " .. config.provider,
      finder = async_finder(provider, config.search),
      sorter = telescope_config.generic_sorter(picker_opts),
      previewer = previewer(config.artwork),
      attach_mappings = function(prompt_buffer, map)
        actions.select_default:replace(function()
          local selected = action_state.get_selected_entry()
          if not selected then
            return
          end
          actions.close(prompt_buffer)
          run_action(provider, "play", selected.value, "Playing " .. selected.value.name)
        end)

        local function queue()
          local selected = action_state.get_selected_entry()
          if selected then
            run_action(
              provider,
              "add_to_queue",
              selected.value,
              "Added to queue: " .. selected.value.name
            )
          end
        end
        local function pause()
          provider:pause(function(err)
            util.notify(err or "Playback paused", err and vim.log.levels.ERROR or nil)
          end)
        end
        map("i", "<C-q>", queue)
        map("n", "<C-q>", queue)
        map("i", "<C-p>", pause)
        map("n", "<C-p>", pause)
        return true
      end,
    })
    :find()
end

return M
