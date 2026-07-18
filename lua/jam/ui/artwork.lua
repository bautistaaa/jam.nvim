local util = require("jam.util")

local M = {
  active_images = {},
  active_urls = {},
}

local artwork_namespace = vim.api.nvim_create_namespace("jam.nvim.artwork")
local highlight_groups = {}
local highlight_group_count = 0
local max_highlight_groups = 1024

local function image_terminal()
  return vim.env.KITTY_WINDOW_ID ~= nil
    or vim.env.WEZTERM_PANE ~= nil
    or (vim.env.TERM_PROGRAM or ""):lower():find("kitty", 1, true) ~= nil
end

function M.detect(config)
  if not config.enabled or config.backend == "none" then
    return "none", "disabled"
  end
  if config.backend ~= "auto" then
    return config.backend, "configured explicitly"
  end

  local image_ok = pcall(require, "image")
  if image_ok and image_terminal() then
    return "image", "image.nvim and a compatible terminal were detected"
  end
  if util.executable("chafa") and util.executable("curl") then
    return "chafa", "chafa is executable"
  end
  return "text", "no supported image renderer was detected"
end

function M.clear(buffer)
  M.active_urls[buffer] = nil
  if buffer and vim.api.nvim_buf_is_valid(buffer) then
    vim.api.nvim_buf_clear_namespace(buffer, artwork_namespace, 0, -1)
  end
  local image = M.active_images[buffer]
  if image then
    pcall(image.clear, image)
    M.active_images[buffer] = nil
  end
end

local function render_image(buffer, window, url, config, done)
  M.clear(buffer)
  M.active_urls[buffer] = url
  local ok, image_module = pcall(require, "image")
  if not ok then
    done("image.nvim could not be loaded")
    return
  end

  vim.schedule(function()
    if M.active_urls[buffer] ~= url then
      return
    end
    local created, image = pcall(image_module.from_url, url, {
      buffer = buffer,
      window = window,
      with_virtual_padding = true,
      max_width = config.width,
      max_height = config.height,
    })
    if not created or not image then
      done("image.nvim could not render this artwork")
      return
    end
    M.active_images[buffer] = image
    local rendered, render_err = pcall(image.render, image)
    done(rendered and nil or tostring(render_err))
  end)
end

local function parse_sgr(parameters, style)
  local values = {}
  for value in (parameters .. ";"):gmatch("(.-);") do
    table.insert(values, tonumber(value) or 0)
  end

  local index = 1
  while index <= #values do
    local code = values[index]
    if code == 0 then
      style.fg = nil
      style.bg = nil
      style.reverse = false
    elseif code == 7 then
      style.reverse = true
    elseif code == 27 then
      style.reverse = false
    elseif code == 39 then
      style.fg = nil
    elseif code == 49 then
      style.bg = nil
    elseif (code == 38 or code == 48) and values[index + 1] == 2 then
      local color = string.format(
        "#%02x%02x%02x",
        values[index + 2] or 0,
        values[index + 3] or 0,
        values[index + 4] or 0
      )
      style[code == 38 and "fg" or "bg"] = color
      index = index + 4
    end
    index = index + 1
  end
end

local function highlight_group(style)
  local fg, bg = style.fg, style.bg
  if style.reverse then
    fg, bg = bg, fg
  end
  if not fg and not bg then
    return nil
  end

  local key = (fg or "none") .. "_" .. (bg or "none")
  if not highlight_groups[key] then
    if highlight_group_count >= max_highlight_groups then
      return nil
    end
    highlight_group_count = highlight_group_count + 1
    local name = string.format("JamArtworkColor%04d", highlight_group_count)
    vim.api.nvim_set_hl(0, name, { fg = fg, bg = bg })
    highlight_groups[key] = name
  end
  return highlight_groups[key]
end

local function reset_highlight_groups()
  highlight_groups = {}
  highlight_group_count = 0
end

local function decode_ansi(output)
  local lines = {}
  local highlights = {}
  local style = { reverse = false }

  for raw_line in (output .. "\n"):gmatch("(.-)\n") do
    local text = ""
    local position = 1
    while position <= #raw_line do
      local start_index, end_index, parameters, command =
        raw_line:find("\27%[([%d;?]*)([%a])", position)
      local chunk = start_index and raw_line:sub(position, start_index - 1)
        or raw_line:sub(position)
      if chunk ~= "" then
        local start_column = #text
        text = text .. chunk
        local group = highlight_group(style)
        if group then
          table.insert(highlights, {
            line = #lines,
            start_column = start_column,
            end_column = #text,
            group = group,
          })
        end
      end
      if not start_index then
        break
      end
      if command == "m" then
        parse_sgr(parameters, style)
      end
      position = end_index + 1
    end
    table.insert(lines, text)
  end

  if lines[#lines] == "" then
    table.remove(lines)
  end
  return lines, highlights
end

local function center_artwork(lines, highlights, window, reserved_lines)
  if not window or not vim.api.nvim_win_is_valid(window) then
    return lines, highlights
  end

  local window_width = vim.api.nvim_win_get_width(window)
  local window_height = math.max(1, vim.api.nvim_win_get_height(window) - (reserved_lines or 0))
  local artwork_width = 0
  for _, line in ipairs(lines) do
    artwork_width = math.max(artwork_width, vim.fn.strdisplaywidth(line))
  end

  local left_padding = math.max(0, math.floor((window_width - artwork_width) / 2))
  local top_padding = math.max(0, math.floor((window_height - #lines) / 2))
  local prefix = string.rep(" ", left_padding)
  local centered = {}
  for _ = 1, top_padding do
    table.insert(centered, "")
  end
  for _, line in ipairs(lines) do
    table.insert(centered, prefix .. line)
  end
  for _, highlight in ipairs(highlights) do
    highlight.line = highlight.line + top_padding
    highlight.start_column = highlight.start_column + left_padding
    highlight.end_column = highlight.end_column + left_padding
  end
  return centered, highlights
end

local function render_chafa(buffer, window, url, config, done)
  local cache_dir = vim.fs.joinpath(vim.fn.stdpath("cache"), "jam.nvim", "artwork")
  vim.fn.mkdir(cache_dir, "p")
  local file = vim.fs.joinpath(cache_dir, vim.fn.sha256(url) .. ".img")
  local render_width = config.width
  local render_height = config.height
  if window and vim.api.nvim_win_is_valid(window) then
    render_width = math.max(1, math.min(render_width, vim.api.nvim_win_get_width(window)))
    render_height = math.max(
      1,
      math.min(
        render_height,
        vim.api.nvim_win_get_height(window) - (config.reserved_lines or 0)
      )
    )
  end

  local function convert()
    vim.system({
      "chafa",
      "--format",
      "symbols",
      "--colors",
      "full",
      "--work",
      "9",
      "--size",
      string.format("%dx%d", render_width, render_height),
      file,
    }, { text = true }, function(result)
      vim.schedule(function()
        if
          result.code ~= 0
          or not vim.api.nvim_buf_is_valid(buffer)
          or M.active_urls[buffer] ~= url
        then
          done("chafa could not render this artwork")
          return
        end
        vim.api.nvim_buf_clear_namespace(buffer, artwork_namespace, 0, -1)
        reset_highlight_groups()
        local lines, highlights = decode_ansi(result.stdout)
        lines, highlights = center_artwork(lines, highlights, window, config.reserved_lines)
        vim.api.nvim_buf_set_lines(buffer, 0, -1, false, lines)
        for _, highlight in ipairs(highlights) do
          vim.api.nvim_buf_add_highlight(
            buffer,
            artwork_namespace,
            highlight.group,
            highlight.line,
            highlight.start_column,
            highlight.end_column
          )
        end
        if not config.cache then
          vim.uv.fs_unlink(file)
        end
        done()
      end)
    end)
  end

  if vim.uv.fs_stat(file) then
    convert()
    return
  end
  vim.system(
    { "curl", "--fail", "--silent", "--location", "--output", file, url },
    {},
    function(result)
      if result.code ~= 0 then
        done("album artwork download failed")
        return
      end
      vim.schedule(function()
        if M.active_urls[buffer] == url then
          convert()
        end
      end)
    end
  )
end

function M.render(buffer, window, url, config, done)
  done = done or function() end
  if not url then
    done("no artwork is available")
    return
  end
  M.active_urls[buffer] = url
  local backend = M.detect(config)
  if backend == "image" then
    render_image(buffer, window, url, config, done)
  elseif backend == "chafa" then
    render_chafa(buffer, window, url, config, done)
  else
    done("artwork renderer unavailable")
  end
end

return M
