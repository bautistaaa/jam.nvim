local util = require("jam.util")

local M = {
  active_images = {},
  active_urls = {},
}

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

local function render_chafa(buffer, url, config, done)
  local cache_dir = vim.fs.joinpath(vim.fn.stdpath("cache"), "jam.nvim", "artwork")
  vim.fn.mkdir(cache_dir, "p")
  local file = vim.fs.joinpath(cache_dir, vim.fn.sha256(url) .. ".img")

  local function convert()
    vim.system({
      "chafa",
      "--format",
      "symbols",
      "--colors",
      "none",
      "--size",
      string.format("%dx%d", config.width, config.height),
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
        vim.api.nvim_buf_set_lines(buffer, 0, -1, false, vim.split(result.stdout, "\n"))
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
    render_chafa(buffer, url, config, done)
  else
    done("artwork renderer unavailable")
  end
end

return M
