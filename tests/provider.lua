local http = require("jam.http")
local Spotify = require("jam.providers.spotify")
local util = require("jam.util")

local requests = {}
http.request = function(opts, callback)
  table.insert(requests, opts)
  if #requests == 1 then
    callback(nil, {
      items = {
        {
          id = "track-one",
          uri = "spotify:track:one",
          name = "First Track",
          artists = { { name = "Test Artist" } },
          duration_ms = 61000,
          disc_number = 1,
          track_number = 1,
        },
      },
      next = "https://api.spotify.com/v1/albums/test-album/tracks?limit=50&offset=50",
    })
  else
    callback(nil, {
      items = {
        {
          id = "track-two",
          uri = "spotify:track:two",
          name = "Second Track",
          artists = { { name = "Test Artist" } },
          duration_ms = 122000,
          disc_number = 2,
          track_number = 1,
        },
      },
      next = vim.NIL,
    })
  end
end

local auth = {
  get_access_token = function(_, callback)
    callback(nil, "test-token")
  end,
}
local provider = Spotify.new({}, auth)
local callback_error
local album_tracks
provider:album_tracks({
  id = "test-album",
  name = "Test Album",
  image_url = "https://example.com/artwork.jpg",
}, function(err, tracks)
  callback_error = err
  album_tracks = tracks
end)

assert(not callback_error, callback_error)
assert(#requests == 2)
assert(requests[1].url:find("/albums/test%-album/tracks%?limit=50"))
assert(requests[2].url:find("offset=50", 1, true))
assert(requests[1].headers.Authorization == "Bearer test-token")
assert(#album_tracks == 2)
assert(album_tracks[1].kind == "track")
assert(album_tracks[1].album == "Test Album")
assert(album_tracks[1].image_url == "https://example.com/artwork.jpg")
assert(album_tracks[1].track_number == 1)
assert(album_tracks[2].disc_number == 2)

local artist_request
http.request = function(opts, callback)
  artist_request = opts
  callback(nil, {
    tracks = {
      {
        id = "top-track",
        uri = "spotify:track:top",
        name = "Top Track",
        artists = { { name = "Test Artist" } },
        album = {
          name = "Popular Album",
          images = { { url = "https://example.com/top-track.jpg" } },
        },
        duration_ms = 180000,
      },
    },
  })
end

local top_tracks
provider:artist_top_tracks({
  id = "test-artist",
  name = "Test Artist",
}, function(err, tracks)
  callback_error = err
  top_tracks = tracks
end)

assert(not callback_error, callback_error)
assert(artist_request.url:find("/artists/test%-artist/top%-tracks"))
assert(#top_tracks == 1)
assert(top_tracks[1].name == "Top Track")
assert(top_tracks[1].album == "Popular Album")
assert(top_tracks[1].list_position == 1)

local show_requests = {}
http.request = function(opts, callback)
  table.insert(show_requests, opts)
  if #show_requests == 1 then
    callback(nil, {
      items = {
        {
          id = "episode-one",
          uri = "spotify:episode:one",
          name = "First Episode",
          duration_ms = 1200000,
          images = { { url = "https://example.com/episode-one.jpg" } },
          resume_point = {
            fully_played = true,
            resume_position_ms = 1200000,
          },
        },
      },
      next = "https://api.spotify.com/v1/shows/test-show/episodes?limit=50&offset=50",
    })
  else
    callback(nil, {
      items = {
        {
          id = "episode-two",
          uri = "spotify:episode:two",
          name = "Second Episode",
          duration_ms = 1800000,
        },
      },
      next = vim.NIL,
    })
  end
end

local episodes
provider:show_episodes({
  id = "test-show",
  name = "Test Podcast",
  publisher = "Test Publisher",
  image_url = "https://example.com/show.jpg",
}, function(err, items)
  callback_error = err
  episodes = items
end)

assert(not callback_error, callback_error)
assert(#show_requests == 2)
assert(show_requests[1].url:find("/shows/test%-show/episodes%?limit=50"))
assert(#episodes == 2)
assert(episodes[1].kind == "episode")
assert(episodes[1].podcast == "Test Podcast")
assert(episodes[1].publisher == "Test Publisher")
assert(episodes[1].fully_played == true)
assert(episodes[1].list_position == 1)
assert(episodes[2].image_url == "https://example.com/show.jpg")
assert(episodes[2].list_position == 2)

local playlist_requests = {}
http.request = function(opts, callback)
  table.insert(playlist_requests, opts)
  if #playlist_requests == 1 then
    callback(nil, {
      items = {
        {
          item = {
            id = "playlist-track-one",
            uri = "spotify:track:playlist-one",
            type = "track",
            name = "Playlist Track",
            artists = { { name = "Playlist Artist" } },
            album = {
              name = "Playlist Album",
              images = { { url = "https://example.com/playlist-track.jpg" } },
            },
            duration_ms = 200000,
          },
        },
        {
          track = {
            id = "legacy-track",
            uri = "spotify:track:legacy",
            name = "Legacy Track Field",
            artists = { { name = "Legacy Artist" } },
            duration_ms = 180000,
          },
        },
        {
          item = nil,
        },
      },
      next = "https://api.spotify.com/v1/playlists/test-playlist/items?limit=50&offset=50",
    })
  else
    callback(nil, {
      items = {
        {
          item = {
            id = "playlist-episode-one",
            uri = "spotify:episode:playlist-one",
            type = "episode",
            name = "Playlist Episode",
            show = { name = "Playlist Podcast" },
            duration_ms = 2400000,
          },
        },
      },
      next = vim.NIL,
    })
  end
end

local playlist_items
provider:playlist_items({
  id = "test-playlist",
  name = "Test Playlist",
  image_url = "https://example.com/playlist.jpg",
}, function(err, items)
  callback_error = err
  playlist_items = items
end)

assert(not callback_error, callback_error)
assert(#playlist_requests == 2)
assert(playlist_requests[1].url:find("/playlists/test%-playlist/items%?"))
assert(playlist_requests[1].url:find("additional_types=track%2Cepisode", 1, true))
assert(#playlist_items == 3)
assert(playlist_items[1].kind == "track")
assert(playlist_items[1].name == "Playlist Track")
assert(playlist_items[1].list_position == 1)
assert(playlist_items[2].kind == "track")
assert(playlist_items[2].name == "Legacy Track Field")
assert(playlist_items[2].image_url == "https://example.com/playlist.jpg")
assert(playlist_items[3].kind == "episode")
assert(playlist_items[3].podcast == "Playlist Podcast")
assert(playlist_items[3].list_position == 3)

for _, filter in ipairs({
  { query = "a: Test Album", expected_type = "album" },
  { query = "t: Test Artist", expected_type = "artist" },
  { query = "s: Test Song", expected_type = "track" },
  { query = "p: Test Podcast", expected_type = "show" },
  { query = "e: Test Episode", expected_type = "episode" },
  { query = "l: Test Playlist", expected_type = "playlist" },
}) do
  local search_request
  http.request = function(opts, callback)
    search_request = opts
    callback(nil, {})
  end
  provider:search(filter.query, {}, function(err)
    callback_error = err
  end)
  assert(not callback_error, callback_error)
  assert(search_request.url:find("type=" .. filter.expected_type, 1, true))
  assert(search_request.url:find("q=" .. util.urlencode(filter.query:sub(4)), 1, true))
end

local metadata_results
http.request = function(_, callback)
  callback(nil, {
    artists = {
      items = {
        {
          id = "metadata-artist",
          uri = "spotify:artist:metadata",
          name = "Metadata Artist",
          followers = { total = 1234567 },
          popularity = 88,
          genres = { "pop", "rock" },
        },
      },
    },
    shows = {
      items = {
        {
          id = "metadata-show",
          uri = "spotify:show:metadata",
          name = "Metadata Podcast",
          publisher = "Metadata Publisher",
          total_episodes = 42,
          languages = { "en" },
          description = "A test podcast.",
        },
      },
    },
  })
end
provider:search("metadata", { types = { "artist", "show" } }, function(err, results)
  callback_error = err
  metadata_results = results
end)
assert(not callback_error, callback_error)
assert(metadata_results[1].followers == 1234567)
assert(metadata_results[1].popularity == 88)
assert(metadata_results[1].genres[1] == "pop")
assert(metadata_results[2].publisher == "Metadata Publisher")
assert(metadata_results[2].total_episodes == 42)

local interleaved_request
local interleaved_results
http.request = function(opts, callback)
  interleaved_request = opts
  callback(nil, {
    tracks = {
      items = {
        { id = "t1", uri = "spotify:track:t1", name = "Track One", artists = {} },
        { id = "t2", uri = "spotify:track:t2", name = "Track Two", artists = {} },
      },
    },
    albums = {
      items = {
        { id = "a1", uri = "spotify:album:a1", name = "Album One", artists = {} },
      },
    },
    playlists = {
      items = {
        {
          id = "p1",
          uri = "spotify:playlist:p1",
          name = "Playlist One",
          owner = { display_name = "Owner" },
        },
      },
    },
  })
end
provider:search("mixed", {
  types = { "track", "album", "playlist" },
  limit = 30,
}, function(err, results)
  callback_error = err
  interleaved_results = results
end)
assert(not callback_error, callback_error)
assert(interleaved_request.url:find("limit=10", 1, true))
assert(#interleaved_results == 4)
assert(interleaved_results[1].kind == "track")
assert(interleaved_results[2].kind == "album")
assert(interleaved_results[3].kind == "playlist")
assert(interleaved_results[4].kind == "track")
assert(interleaved_results[3].name == "Playlist One")

local playback_error
local episode_play_request
http.request = function(opts, callback)
  episode_play_request = opts
  callback(nil)
end
provider:play({
  kind = "episode",
  uri = "spotify:episode:test-episode",
}, function(err)
  playback_error = err
end)
assert(not playback_error, playback_error)
assert(vim.json.decode(episode_play_request.body).uris[1] == "spotify:episode:test-episode")

local opened_uri
http.request = function(_, callback)
  callback("HTTP 404: Device not found")
end
util.open_url = function(uri)
  opened_uri = uri
  return true
end

local playback_message
provider:play({
  kind = "track",
  uri = "spotify:track:test-track",
}, function(err, message)
  playback_error = err
  playback_message = message
end)

assert(not playback_error, playback_error)
assert(opened_uri == "spotify:track:test-track")
assert(playback_message:find("Opened Spotify", 1, true))

http.request = function(_, callback)
  callback(nil, "raw-spotify-response-id")
end
local queue_error
local queue_message
provider:add_to_queue({ uri = "spotify:track:test-track" }, function(err, message)
  queue_error = err
  queue_message = message
end)
assert(not queue_error, queue_error)
assert(queue_message == nil)

local pause_requests = 0
http.request = function(_, callback)
  pause_requests = pause_requests + 1
  callback(nil, {
    device = { id = "test-device" },
    is_playing = false,
  })
end

local pause_error
local pause_message
provider:pause(function(err, message)
  pause_error = err
  pause_message = message
end)

assert(not pause_error, pause_error)
assert(pause_requests == 1)
assert(pause_message == "Playback is already paused")

local resume_requests = 0
http.request = function(_, callback)
  resume_requests = resume_requests + 1
  if resume_requests == 1 then
    callback(nil, {
      device = { id = "test-device" },
      is_playing = false,
    })
  else
    callback(nil, "raw-spotify-response-id")
  end
end

local resume_error
local resume_message
provider:resume(function(err, message)
  resume_error = err
  resume_message = message
end)

assert(not resume_error, resume_error)
assert(resume_requests == 2)
assert(resume_message == "Playback resumed")

print("jam.nvim provider tests passed")
