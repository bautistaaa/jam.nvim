local M = {}

function M.notify(message, level)
  vim.schedule(function()
    vim.notify(message, level or vim.log.levels.INFO, { title = "jam.nvim" })
  end)
end

function M.urlencode(value)
  return (
    tostring(value):gsub("\n", "\r\n"):gsub("([^%w%-%.%_%~])", function(char)
      return string.format("%%%02X", string.byte(char))
    end)
  )
end

function M.query(params)
  local parts = {}
  for key, value in pairs(params) do
    if value ~= nil then
      table.insert(parts, M.urlencode(key) .. "=" .. M.urlencode(value))
    end
  end
  table.sort(parts)
  return table.concat(parts, "&")
end

function M.base64url(value)
  return vim.base64.encode(value):gsub("%+", "-"):gsub("/", "_"):gsub("=", "")
end

function M.executable(name)
  return vim.fn.executable(name) == 1
end

function M.open_url(url)
  if vim.ui.open then
    local _, err = vim.ui.open(url)
    return err == nil, err
  end

  local command
  if vim.fn.has("mac") == 1 then
    command = { "open", url }
  elseif vim.fn.has("win32") == 1 then
    command = { "cmd.exe", "/c", "start", "", url }
  else
    command = { "xdg-open", url }
  end
  vim.system(command, { detach = true })
  return true
end

return M
