local util = require("jam.util")
local http = require("jam.http")

local probe = vim.uv.new_tcp()
assert(probe:bind("127.0.0.1", 0))
local port = assert(probe:getsockname()).port
probe:close()

util.open_url = function()
  return true
end
http.form = function()
  error("token exchange must not run for a rejected callback")
end

local finished = false
local callback_error
local auth = require("jam.auth.spotify").new({
  client_id = "test-client-id",
  redirect_uri = string.format("http://127.0.0.1:%d/callback", port),
  scopes = {},
})

auth:login(function(err)
  callback_error = err
  finished = true
end)

vim.defer_fn(function()
  vim.system({
    "curl",
    "--fail",
    "--silent",
    string.format("http://127.0.0.1:%d/callback?state=invalid", port),
  })
end, 50)

assert(
  vim.wait(3000, function()
    return finished
  end),
  "OAuth callback server timed out"
)
assert(callback_error:find("invalid OAuth callback", 1, true))

print("jam.nvim OAuth callback test passed")
