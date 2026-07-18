local http = require("jam.http")
local util = require("jam.util")

local Spotify = {}
Spotify.__index = Spotify

Spotify.capabilities = {
  search = true,
  playback = true,
  queue = true,
  playlists = true,
  album_tracks = true,
  artist_top_tracks = true,
  show_episodes = true,
  library = true,
  artwork = true,
}

local API_URL = "https://api.spotify.com/v1"

local function image_url(images)
  return images and images[1] and images[1].url or nil
end

local function artists(items)
  local names = {}
  for _, artist in ipairs(items or {}) do
    table.insert(names, artist.name)
  end
  return table.concat(names, ", ")
end

local function subtitle(item, kind)
  if kind == "track" or kind == "album" then
    return artists(item.artists)
  elseif kind == "artist" then
    return "Artist"
  elseif kind == "playlist" then
    local owner = item.owner and item.owner.display_name
    return owner and ("Playlist by " .. owner) or "Playlist"
  elseif kind == "show" then
    return item.publisher or "Podcast"
  elseif kind == "episode" then
    return item.show and item.show.name or "Podcast episode"
  end
  return kind
end

local function normalize(item, kind)
  local album = item.album
  return {
    id = item.id,
    uri = item.uri,
    kind = kind,
    name = item.name,
    subtitle = subtitle(item, kind),
    album = album and album.name or (kind == "album" and item.name or nil),
    podcast = item.show and item.show.name or (kind == "show" and item.name or nil),
    duration_ms = item.duration_ms,
    release_date = item.release_date or (album and album.release_date),
    explicit = item.explicit,
    popularity = item.popularity,
    followers = item.followers and item.followers.total,
    genres = item.genres,
    publisher = item.publisher or (item.show and item.show.publisher),
    total_episodes = item.total_episodes or (item.show and item.show.total_episodes),
    languages = item.languages,
    description = item.description,
    total_tracks = item.total_tracks or (album and album.total_tracks),
    album_type = item.album_type or (album and album.album_type),
    progress_ms = item.resume_point and item.resume_point.resume_position_ms,
    fully_played = item.resume_point and item.resume_point.fully_played,
    disc_number = item.disc_number,
    track_number = item.track_number,
    image_url = image_url((album and album.images) or item.images),
    raw = item,
  }
end

function Spotify.new(config, auth)
  return setmetatable({ config = config, auth = auth }, Spotify)
end

function Spotify:_request(opts, callback)
  self.auth:get_access_token(function(auth_err, token)
    if auth_err then
      callback(auth_err)
      return
    end
    opts.headers = vim.tbl_extend("force", opts.headers or {}, {
      Authorization = "Bearer " .. token,
    })
    http.request(opts, callback)
  end)
end

function Spotify:search(query, options, callback)
  if not query or vim.trim(query) == "" then
    callback(nil, {})
    return
  end
  options = options or {}
  query = vim.trim(query)
  local prefix, filtered_query = query:match("^([aAtTsSpPeE]):%s*(.*)$")
  local type_by_prefix = {
    a = "album",
    t = "artist",
    s = "track",
    p = "show",
    e = "episode",
  }
  local types = options.types or { "track", "album", "artist", "playlist", "show", "episode" }
  if prefix then
    query = vim.trim(filtered_query)
    types = { type_by_prefix[prefix:lower()] }
    if query == "" then
      callback(nil, {})
      return
    end
  end
  local url = API_URL
    .. "/search?"
    .. util.query({
      q = query,
      type = table.concat(types, ","),
      limit = options.limit or 30,
    })

  return self:_request({ url = url }, function(err, response)
    if err then
      callback(err)
      return
    end
    local results = {}
    local plural = {
      track = "tracks",
      album = "albums",
      artist = "artists",
      playlist = "playlists",
      show = "shows",
      episode = "episodes",
    }
    for _, kind in ipairs(types) do
      local group = response[plural[kind]]
      if type(group) == "table" then
        for _, item in ipairs(group.items or {}) do
          if item then
            table.insert(results, normalize(item, kind))
          end
        end
      end
    end
    callback(nil, results)
  end)
end

function Spotify:album_tracks(album, callback)
  if not album or not album.id then
    callback("A Spotify album ID is required")
    return
  end

  local tracks = {}
  local function fetch(url)
    self:_request({ url = url }, function(err, response)
      if err then
        callback(err)
        return
      end
      for _, item in ipairs((response or {}).items or {}) do
        if item then
          local track = normalize(item, "track")
          track.album = album.name
          track.image_url = album.image_url
          table.insert(tracks, track)
        end
      end
      if response and type(response.next) == "string" and response.next ~= "" then
        fetch(response.next)
      else
        callback(nil, tracks)
      end
    end)
  end

  fetch(API_URL .. "/albums/" .. util.urlencode(album.id) .. "/tracks?limit=50")
end

function Spotify:artist_top_tracks(artist, callback)
  if not artist or not artist.id then
    callback("A Spotify artist ID is required")
    return
  end

  self:_request({
    url = API_URL .. "/artists/" .. util.urlencode(artist.id) .. "/top-tracks",
  }, function(err, response)
    if err then
      callback(err)
      return
    end
    local tracks = {}
    for index, item in ipairs((response or {}).tracks or {}) do
      if item then
        local track = normalize(item, "track")
        track.list_position = index
        table.insert(tracks, track)
      end
    end
    callback(nil, tracks)
  end)
end

function Spotify:show_episodes(show, callback)
  if not show or not show.id then
    callback("A Spotify podcast ID is required")
    return
  end

  local episodes = {}
  local function fetch(url)
    self:_request({ url = url }, function(err, response)
      if err then
        callback(err)
        return
      end
      for _, item in ipairs((response or {}).items or {}) do
        if item then
          local episode = normalize(item, "episode")
          episode.subtitle = show.name
          episode.podcast = show.name
          episode.publisher = show.publisher
          episode.image_url = episode.image_url or show.image_url
          episode.list_position = #episodes + 1
          table.insert(episodes, episode)
        end
      end
      if response and type(response.next) == "string" and response.next ~= "" then
        fetch(response.next)
      else
        callback(nil, episodes)
      end
    end)
  end

  fetch(API_URL .. "/shows/" .. util.urlencode(show.id) .. "/episodes?limit=50")
end

function Spotify:play(item, callback)
  local body
  if item.kind == "track" or item.kind == "episode" then
    body = { uris = { item.uri } }
  else
    body = { context_uri = item.uri }
  end
  self:_request({
    method = "PUT",
    url = API_URL .. "/me/player/play",
    headers = { ["Content-Type"] = "application/json" },
    body = vim.json.encode(body),
  }, function(err)
    local lower_error = err and err:lower() or ""
    local no_device = lower_error:find("device not found", 1, true)
      or lower_error:find("no active device", 1, true)
    if no_device then
      local opened, open_err = util.open_url(item.uri)
      if opened then
        callback(nil, "Opened Spotify; select the track again when the app is ready")
      else
        callback("Could not open Spotify: " .. tostring(open_err))
      end
      return
    end
    callback(err)
  end)
end

function Spotify:pause(callback)
  self:_request({ url = API_URL .. "/me/player" }, function(err, state)
    if err then
      callback(err)
      return
    end
    if type(state) ~= "table" or not state.device then
      callback("No active Spotify playback")
      return
    end
    if not state.is_playing then
      callback(nil, "Playback is already paused")
      return
    end
    self:_request({ method = "PUT", url = API_URL .. "/me/player/pause" }, function(pause_err)
      callback(pause_err, pause_err and nil or "Playback paused")
    end)
  end)
end

function Spotify:resume(callback)
  self:_request({ url = API_URL .. "/me/player" }, function(err, state)
    if err then
      callback(err)
      return
    end
    if type(state) ~= "table" or not state.device then
      callback("No active Spotify playback")
      return
    end
    if state.is_playing then
      callback(nil, "Playback is already playing")
      return
    end
    self:_request({ method = "PUT", url = API_URL .. "/me/player/play" }, function(play_err)
      callback(play_err, play_err and nil or "Playback resumed")
    end)
  end)
end

function Spotify:next(callback)
  self:_request({ method = "POST", url = API_URL .. "/me/player/next" }, function(err)
    callback(err)
  end)
end

function Spotify:previous(callback)
  self:_request({ method = "POST", url = API_URL .. "/me/player/previous" }, function(err)
    callback(err)
  end)
end

function Spotify:add_to_queue(item, callback)
  self:_request({
    method = "POST",
    url = API_URL .. "/me/player/queue?" .. util.query({ uri = item.uri }),
  }, function(err)
    callback(err)
  end)
end

function Spotify:now_playing(callback)
  self:_request({ url = API_URL .. "/me/player/currently-playing" }, function(err, response)
    if err or not response or not response.item then
      callback(err, nil)
      return
    end
    callback(nil, normalize(response.item, "track"))
  end)
end

function Spotify:devices(callback)
  self:_request({ url = API_URL .. "/me/player/devices" }, function(err, response)
    callback(err, response and response.devices or {})
  end)
end

return Spotify
