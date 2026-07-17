local http = require("jam.http")
local storage = require("jam.auth.storage")
local util = require("jam.util")

local SpotifyAuth = {}
SpotifyAuth.__index = SpotifyAuth

local AUTHORIZE_URL = "https://accounts.spotify.com/authorize"
local TOKEN_URL = "https://accounts.spotify.com/api/token"

local function random_urlsafe(bytes)
  local result = vim.system({ "openssl", "rand", tostring(bytes) }, { text = false }):wait()
  if result.code ~= 0 then
    return nil, "openssl could not generate secure random data"
  end
  return util.base64url(result.stdout)
end

local function challenge(verifier)
  local result = vim
    .system({ "openssl", "dgst", "-sha256", "-binary" }, { stdin = verifier, text = false })
    :wait()
  if result.code ~= 0 then
    return nil, "openssl could not generate the PKCE challenge"
  end
  return util.base64url(result.stdout)
end

local function parse_redirect(uri)
  local host, port, callback_path = uri:match("^http://([^:/]+):(%d+)(/.*)$")
  if not host then
    return nil, "redirect_uri must be an HTTP localhost URL with an explicit port"
  end
  if host ~= "127.0.0.1" and host ~= "localhost" then
    return nil, "redirect_uri host must be localhost or 127.0.0.1"
  end
  return {
    host = host,
    bind_host = host == "localhost" and "127.0.0.1" or host,
    port = tonumber(port),
    path = callback_path,
  }
end

function SpotifyAuth.new(config)
  return setmetatable({
    config = config,
    tokens = storage.load("spotify"),
    server = nil,
  }, SpotifyAuth)
end

function SpotifyAuth:_save_tokens(response)
  local previous = self.tokens or {}
  self.tokens = {
    access_token = response.access_token,
    refresh_token = response.refresh_token or previous.refresh_token,
    expires_at = os.time() + (response.expires_in or 3600),
    scope = response.scope or previous.scope,
  }
  storage.save("spotify", self.tokens)
end

function SpotifyAuth:_exchange(fields, callback)
  fields.client_id = self.config.client_id
  http.form(TOKEN_URL, fields, function(err, response)
    if err then
      callback(err)
      return
    end
    self:_save_tokens(response)
    callback(nil, self.tokens.access_token)
  end)
end

function SpotifyAuth:refresh(callback)
  if not self.tokens or not self.tokens.refresh_token then
    callback("Spotify authentication is required; run :Jam auth spotify")
    return
  end
  self:_exchange({
    grant_type = "refresh_token",
    refresh_token = self.tokens.refresh_token,
  }, callback)
end

function SpotifyAuth:get_access_token(callback)
  if
    self.tokens
    and self.tokens.access_token
    and (self.tokens.expires_at or 0) > os.time() + 30
  then
    callback(nil, self.tokens.access_token)
    return
  end
  self:refresh(callback)
end

function SpotifyAuth:logout()
  self.tokens = nil
  storage.clear("spotify")
end

function SpotifyAuth:login(callback)
  if not self.config.client_id or self.config.client_id == "" then
    callback("Set providers.spotify.client_id before authenticating")
    return
  end
  if not util.executable("openssl") then
    callback("openssl is required for secure Spotify PKCE authentication")
    return
  end

  local redirect, redirect_err = parse_redirect(self.config.redirect_uri)
  if not redirect then
    callback(redirect_err)
    return
  end
  local verifier, verifier_err = random_urlsafe(64)
  if not verifier then
    callback(verifier_err)
    return
  end
  local code_challenge, challenge_err = challenge(verifier)
  if not code_challenge then
    callback(challenge_err)
    return
  end
  local state = assert(random_urlsafe(24))

  local server = vim.uv.new_tcp()
  local ok, bind_err = server:bind(redirect.bind_host, redirect.port)
  if not ok then
    callback("Could not bind Spotify callback server: " .. tostring(bind_err))
    server:close()
    return
  end
  self.server = server

  server:listen(1, function(listen_err)
    if listen_err then
      server:close()
      self.server = nil
      vim.schedule(function()
        callback("Spotify callback server failed: " .. listen_err)
      end)
      return
    end
    local client = vim.uv.new_tcp()
    local accepted, accept_err = server:accept(client)
    if not accepted then
      client:close()
      server:close()
      self.server = nil
      vim.schedule(function()
        callback("Spotify callback connection failed: " .. tostring(accept_err))
      end)
      return
    end
    local request_data = ""
    client:read_start(function(read_err, data)
      if read_err then
        client:close()
        return
      end
      if not data then
        client:close()
        return
      end
      request_data = request_data .. data
      if not request_data:find("\r\n\r\n", 1, true) then
        return
      end
      client:read_stop()
      local target = request_data:match("^GET%s+([^%s]+)")
      local path, query_string = target and target:match("^([^?]+)%??(.*)$")
      local params = {}
      for key, value in (query_string or ""):gmatch("([^&=?]+)=([^&]*)") do
        params[key] = value:gsub("%%(%x%x)", function(hex)
          return string.char(tonumber(hex, 16))
        end)
      end
      local valid = path == redirect.path and params.state == state and params.code
      local body = valid and "Spotify connected. You can close this window."
        or "Spotify authentication failed. Return to Neovim for details."
      client:write(
        "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nConnection: close\r\nContent-Length: "
          .. #body
          .. "\r\n\r\n"
          .. body,
        function()
          client:shutdown()
          client:close()
        end
      )
      server:close()
      self.server = nil
      vim.schedule(function()
        if not valid then
          callback(params.error or "Spotify returned an invalid OAuth callback")
          return
        end
        self:_exchange({
          grant_type = "authorization_code",
          code = params.code,
          redirect_uri = self.config.redirect_uri,
          code_verifier = verifier,
        }, callback)
      end)
    end)
  end)

  local authorize_url = AUTHORIZE_URL
    .. "?"
    .. util.query({
      client_id = self.config.client_id,
      response_type = "code",
      redirect_uri = self.config.redirect_uri,
      code_challenge_method = "S256",
      code_challenge = code_challenge,
      state = state,
      scope = table.concat(self.config.scopes, " "),
    })
  local opened, open_err = util.open_url(authorize_url)
  if not opened then
    server:close()
    self.server = nil
    callback("Could not open Spotify authorization URL: " .. tostring(open_err))
  end
end

return SpotifyAuth
