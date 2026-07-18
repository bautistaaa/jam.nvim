local config = require("jam.config")
local providers = require("jam.providers")
local util = require("jam.util")

local M = {}

function M.setup(opts)
  providers.reset()
  local values = config.setup(opts)
  pcall(function()
    require("telescope").load_extension("jam")
  end)
  return values
end

local function provider()
  local ok, result = pcall(providers.get, config.values.provider, config.values)
  if not ok then
    util.notify(result, vim.log.levels.ERROR)
    return nil
  end
  return result
end

function M.open(opts)
  local active = provider()
  if active then
    require("jam.ui.picker").open(active, config.values, opts)
  end
end

function M.auth()
  local active = provider()
  if not active then
    return
  end
  util.notify("Opening Spotify authorization in your browser…")
  active.auth:login(function(err)
    util.notify(err or "Spotify connected", err and vim.log.levels.ERROR or nil)
  end)
end

function M.logout()
  local active = provider()
  if active then
    active.auth:logout()
    util.notify("Spotify credentials removed")
  end
end

function M.control(action)
  local active = provider()
  local method = action == "play" and "resume" or action
  if not active or not active[method] then
    util.notify("Unsupported playback action: " .. action, vim.log.levels.ERROR)
    return
  end
  active[method](active, function(err, message)
    util.notify(err or message or ("Playback: " .. action), err and vim.log.levels.ERROR or nil)
  end)
end

function M.now_playing()
  local active = provider()
  if not active then
    return
  end
  active:now_playing(function(err, item)
    if err then
      util.notify(err, vim.log.levels.ERROR)
    elseif item then
      util.notify(string.format("%s — %s", item.name, item.subtitle))
    else
      util.notify("Nothing is currently playing")
    end
  end)
end

function M.command(args)
  local words = vim.split(vim.trim(args or ""), "%s+")
  local command = words[1]
  if not command or command == "" or command == "search" then
    M.open()
  elseif command == "auth" then
    M.auth()
  elseif command == "logout" then
    M.logout()
  elseif command == "play" or command == "pause" or command == "next" or command == "previous" then
    M.control(command)
  elseif command == "now-playing" then
    M.now_playing()
  elseif command == "health" then
    vim.cmd.checkhealth("jam")
  else
    util.notify("Unknown Jam command: " .. command, vim.log.levels.ERROR)
  end
end

function M.complete(arg_lead)
  local commands = {
    "search",
    "auth",
    "logout",
    "play",
    "pause",
    "next",
    "previous",
    "now-playing",
    "health",
  }
  return vim.tbl_filter(function(command)
    return vim.startswith(command, arg_lead)
  end, commands)
end

return M
