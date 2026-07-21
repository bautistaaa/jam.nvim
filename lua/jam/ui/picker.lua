local artwork = require("jam.ui.artwork")
local util = require("jam.util")

local M = {}

local kind_labels = {
  track = "TRACK",
  album = "ALBUM",
  artist = "ARTIST",
  playlist = "PLAYLIST",
  show = "PODCAST",
  episode = "EPISODE",
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
    "%-8s  %-36s  %s",
    kind_labels[item.kind] or "OTHER",
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

local function media_entry_maker(item)
  local position
  if item.list_position then
    position = string.format("%02d", item.list_position)
  elseif (item.disc_number or 1) > 1 then
    position = string.format("%d.%02d", item.disc_number, item.track_number or 0)
  else
    position = string.format("%02d", item.track_number or 0)
  end
  return {
    value = item,
    display = string.format(
      "%-5s  %-36s  %s",
      position,
      item.name or "Unknown",
      item.subtitle or ""
    ),
    ordinal = table.concat({ item.name or "", item.subtitle or "", item.album or "" }, " "),
  }
end

local function async_finder(provider, search_config)
  local finder = { generation = 0, timer = nil, closed = false }

  local function close_timer(timer)
    if not timer or timer:is_closing() then
      return
    end
    timer:stop()
    timer:close()
  end

  function finder:close()
    self.closed = true
    local timer = self.timer
    self.timer = nil
    close_timer(timer)
  end

  return setmetatable(finder, {
    __call = function(self, prompt, process_result, process_complete)
      self.generation = self.generation + 1
      local generation = self.generation
      local previous_timer = self.timer
      self.timer = nil
      close_timer(previous_timer)
      if not prompt or vim.trim(prompt) == "" then
        process_complete()
        return
      end

      local timer = vim.uv.new_timer()
      self.timer = timer
      timer:start(search_config.debounce_ms, 0, function()
        if self.timer == timer then
          self.timer = nil
        end
        close_timer(timer)
        vim.schedule(function()
          provider:search(prompt, search_config, function(err, results)
            if self.closed or generation ~= self.generation then
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

local function compact_number(value)
  if not value then
    return nil
  elseif value >= 1000000 then
    return string.format("%.1fM", value / 1000000)
  elseif value >= 1000 then
    return string.format("%.1fK", value / 1000)
  end
  return tostring(value)
end

local function wrap_text(text, width, max_lines)
  local lines = {}
  local current = ""
  local truncated = false
  for word in text:gmatch("%S+") do
    local candidate = current == "" and word or (current .. " " .. word)
    if vim.fn.strdisplaywidth(candidate) <= width then
      current = candidate
    else
      if current ~= "" then
        table.insert(lines, current)
      end
      if max_lines and #lines >= max_lines then
        truncated = true
        break
      end
      current = word
    end
  end
  if not truncated and current ~= "" and (not max_lines or #lines < max_lines) then
    table.insert(lines, current)
  end
  if truncated and #lines > 0 then
    local last = lines[#lines]
    while last ~= "" and vim.fn.strdisplaywidth(last .. "…") > width do
      last = vim.fn.strcharpart(last, 0, vim.fn.strchars(last) - 1)
    end
    lines[#lines] = last .. "…"
  end
  return lines
end

local function metadata_lines(item, width)
  local lines = { item.name or "Unknown" }
  local details = {}
  if item.kind == "artist" then
    if item.followers then
      table.insert(details, "Followers: " .. compact_number(item.followers))
    end
    if item.popularity then
      table.insert(details, "Popularity: " .. item.popularity .. "/100")
    end
    if #details > 0 then
      table.insert(lines, table.concat(details, "  ·  "))
    end
    if item.genres and #item.genres > 0 then
      table.insert(lines, "Genres: " .. table.concat(item.genres, ", "))
    end
  elseif item.kind == "show" then
    if item.publisher then
      table.insert(lines, item.publisher)
    end
    if item.total_episodes then
      table.insert(details, "Episodes: " .. item.total_episodes)
    end
    if item.languages and #item.languages > 0 then
      table.insert(details, "Languages: " .. table.concat(item.languages, ", "))
    end
    if item.explicit then
      table.insert(details, "Explicit")
    end
    if #details > 0 then
      table.insert(lines, table.concat(details, "  ·  "))
    end
  else
    if item.subtitle and item.subtitle ~= "" then
      table.insert(lines, item.subtitle)
    end
    if item.album then
      table.insert(details, "Album: " .. item.album)
    elseif item.podcast then
      table.insert(details, "Podcast: " .. item.podcast)
    end
    if item.release_date then
      table.insert(details, "Released: " .. item.release_date)
    end
    if item.duration_ms then
      table.insert(details, "Duration: " .. duration(item.duration_ms))
    end
    if item.total_tracks then
      local count_label = item.kind == "playlist" and "Items: " or "Tracks: "
      table.insert(details, count_label .. item.total_tracks)
    end
    if item.album_type then
      table.insert(details, "Type: " .. item.album_type)
    end
    if item.popularity then
      table.insert(details, "Popularity: " .. item.popularity .. "/100")
    end
    if item.fully_played then
      table.insert(details, "Played")
    elseif item.progress_ms and item.progress_ms > 0 then
      table.insert(details, "Progress: " .. duration(item.progress_ms))
    end
    if item.explicit then
      table.insert(details, "Explicit")
    end
    if #details > 0 then
      table.insert(lines, table.concat(details, "  ·  "))
    end
  end

  local wrapped = {}
  for _, line in ipairs(lines) do
    vim.list_extend(wrapped, wrap_text(line, width))
  end
  if item.description and item.description ~= "" then
    table.insert(wrapped, "")
    local description = (item.description:gsub("%s+", " "))
    vim.list_extend(wrapped, wrap_text(description, width, 2))
  end
  return wrapped
end

local function render_metadata(buffer, window, lines, center_vertically, follow_artwork)
  if not vim.api.nvim_buf_is_valid(buffer) or not vim.api.nvim_win_is_valid(window) then
    return
  end
  local width = math.max(1, vim.api.nvim_win_get_width(window) - 4)
  local height = vim.api.nvim_win_get_height(window)
  local rendered = {}
  for _, line in ipairs(lines) do
    line = vim.fn.strcharpart(line, 0, width)
    local padding = 2 + math.max(0, math.floor((width - vim.fn.strdisplaywidth(line)) / 2))
    table.insert(rendered, string.rep(" ", padding) .. line)
  end

  local line_count = vim.api.nvim_buf_line_count(buffer)
  local start_line
  if center_vertically then
    start_line = math.max(0, math.floor((height - #rendered) / 2))
  elseif follow_artwork then
    start_line = math.min(line_count + 2, math.max(0, height - #rendered - 1))
  else
    start_line = math.max(0, height - #rendered - 1)
  end
  if line_count < start_line then
    local padding = {}
    for _ = line_count, start_line - 1 do
      table.insert(padding, "")
    end
    vim.api.nvim_buf_set_lines(buffer, line_count, line_count, false, padding)
    line_count = start_line
  end
  vim.api.nvim_buf_set_lines(
    buffer,
    start_line,
    math.min(start_line + #rendered, line_count),
    false,
    rendered
  )
end

local function previewer(artwork_config)
  local previewers = require("telescope.previewers")
  local generation = 0
  return previewers.new_buffer_previewer({
    title = "Artwork",
    define_preview = function(self, entry)
      generation = generation + 1
      local current_generation = generation
      local item = entry.value
      local buffer = self.state.bufnr
      local window = self.state.winid
      local metadata_width = math.max(20, vim.api.nvim_win_get_width(window) - 8)
      local metadata = metadata_lines(item, metadata_width)
      local render_config = vim.tbl_deep_extend("force", {}, artwork_config, {
        reserved_lines = #metadata + 2,
      })
      local artwork_backend = artwork.detect(render_config)
      artwork.clear(buffer)
      vim.api.nvim_buf_set_lines(buffer, 0, -1, false, {})
      artwork.render(buffer, window, item.image_url, render_config, function(err)
        if current_generation ~= generation or not vim.api.nvim_buf_is_valid(buffer) then
          return
        end
        render_metadata(
          buffer,
          window,
          metadata,
          err ~= nil,
          not err and artwork_backend == "chafa"
        )
      end)
    end,
    teardown = function(self)
      generation = generation + 1
      if self.state and self.state.bufnr then
        artwork.clear(self.state.bufnr)
      end
    end,
  })
end

local function run_action(provider, method, item, success, on_success)
  provider[method](provider, item, function(err, message)
    if err then
      util.notify(err, vim.log.levels.ERROR)
      return
    end
    util.notify(type(message) == "string" and message or success)
    if on_success then
      on_success()
    end
  end)
end

local function show_queued(prompt_buffer, action_state)
  if not vim.api.nvim_buf_is_valid(prompt_buffer) then
    return
  end
  local ok, picker = pcall(action_state.get_current_picker, prompt_buffer)
  if not ok or not picker then
    return
  end

  local original_prefix = picker.prompt_prefix
  local queued_prefix = "✓ QUEUED "
  picker:change_prompt_prefix(queued_prefix, "MoreMsg")
  vim.defer_fn(function()
    if not vim.api.nvim_buf_is_valid(prompt_buffer) then
      return
    end
    local current_ok, current_picker = pcall(action_state.get_current_picker, prompt_buffer)
    if current_ok and current_picker == picker and picker.prompt_prefix == queued_prefix then
      picker:change_prompt_prefix(original_prefix)
    end
  end, 1500)
end

local function open_items(provider, config, title, results_title, items, search_opts, search_query)
  local pickers = require("telescope.pickers")
  local finders = require("telescope.finders")
  local actions = require("telescope.actions")
  local action_state = require("telescope.actions.state")
  local telescope_config = require("telescope.config").values
  local picker_opts = vim.deepcopy(config.picker)

  pickers
    .new(picker_opts, {
      prompt_title = title,
      results_title = results_title,
      finder = finders.new_table({
        results = items,
        entry_maker = media_entry_maker,
      }),
      sorter = telescope_config.generic_sorter(picker_opts),
      previewer = previewer(config.artwork),
      attach_mappings = function(prompt_buffer, map)
        local function back_to_search()
          actions.close(prompt_buffer)
          vim.schedule(function()
            local opts = vim.deepcopy(search_opts or {})
            opts.default_text = search_query
            M.open(provider, config, opts)
          end)
        end

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
              "Added to queue: " .. selected.value.name,
              function()
                show_queued(prompt_buffer, action_state)
              end
            )
          end
        end
        local function pause()
          provider:pause(function(err, message)
            util.notify(err or message or "Playback paused", err and vim.log.levels.ERROR or nil)
          end)
        end
        map("i", "<Esc>", back_to_search)
        map("n", "<Esc>", back_to_search)
        map("i", "<C-q>", queue)
        map("n", "<C-q>", queue)
        map("i", "<C-p>", pause)
        map("n", "<C-p>", pause)
        return true
      end,
    })
    :find()
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
  local sorters = require("telescope.sorters")
  local picker_opts = vim.tbl_deep_extend("force", config.picker, opts)

  pickers
    .new(picker_opts, {
      prompt_title = "jam.nvim · " .. config.provider,
      finder = async_finder(provider, config.search),
      sorter = sorters.empty(),
      previewer = previewer(config.artwork),
      attach_mappings = function(prompt_buffer, map)
        local loading_tracks = false

        local function drill_down(item, method, title, results_title, on_error)
          if loading_tracks then
            return
          end
          loading_tracks = true
          local search_query = action_state.get_current_line()
          provider[method](provider, item, function(err, tracks)
            loading_tracks = false
            if err then
              if on_error and on_error(err) then
                return
              end
              util.notify(err, vim.log.levels.ERROR)
              return
            end
            if not vim.api.nvim_buf_is_valid(prompt_buffer) then
              return
            end
            if #tracks == 0 then
              util.notify(
                "No " .. results_title:lower() .. " found for " .. item.name,
                vim.log.levels.WARN
              )
              return
            end
            actions.close(prompt_buffer)
            vim.schedule(function()
              open_items(provider, config, title, results_title, tracks, opts, search_query)
            end)
          end)
        end

        actions.select_default:replace(function()
          local selected = action_state.get_selected_entry()
          if not selected then
            return
          end
          if selected.value.kind == "album" and provider.album_tracks then
            local album = selected.value
            drill_down(album, "album_tracks", "Album · " .. album.name, "Tracks")
            return
          end
          if selected.value.kind == "artist" and provider.artist_top_tracks then
            local artist = selected.value
            drill_down(
              artist,
              "artist_top_tracks",
              "Artist · " .. artist.name .. " · Top Tracks",
              "Tracks"
            )
            return
          end
          if selected.value.kind == "show" and provider.show_episodes then
            local show = selected.value
            drill_down(show, "show_episodes", "Podcast · " .. show.name, "Episodes")
            return
          end
          if selected.value.kind == "playlist" and provider.playlist_items then
            local playlist = selected.value
            drill_down(
              playlist,
              "playlist_items",
              "Playlist · " .. playlist.name,
              "Items",
              function(err)
                local lower = tostring(err):lower()
                local forbidden = lower:find("http 403", 1, true)
                  or lower:find("forbidden", 1, true)
                  or lower:find("not collaborate", 1, true)
                if not forbidden then
                  return false
                end
                util.notify(
                  "Spotify only allows browsing playlists you own or collaborate on; playing instead",
                  vim.log.levels.INFO
                )
                actions.close(prompt_buffer)
                run_action(provider, "play", playlist, "Playing " .. playlist.name)
                return true
              end
            )
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
              "Added to queue: " .. selected.value.name,
              function()
                show_queued(prompt_buffer, action_state)
              end
            )
          end
        end
        local function pause()
          provider:pause(function(err, message)
            util.notify(err or message or "Playback paused", err and vim.log.levels.ERROR or nil)
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
