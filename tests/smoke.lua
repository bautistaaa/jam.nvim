local jam = require("jam")
local util = require("jam.util")

local values = jam.setup({
  providers = {
    spotify = {
      client_id = "test-client-id",
    },
  },
})

assert(values.provider == "spotify")
assert(values.providers.spotify.client_id == "test-client-id")
assert(util.urlencode("Daft Punk & friends") == "Daft%20Punk%20%26%20friends")
assert(util.base64url("jam") == "amFt")

local provider = require("jam.providers").get("spotify", values)
assert(provider.capabilities.search)
assert(provider.capabilities.playback)
assert(provider.capabilities.album_tracks)
assert(provider.capabilities.artist_top_tracks)
assert(provider.capabilities.show_episodes)
assert(provider.capabilities.playlist_items)
assert(provider.capabilities.artwork)

assert(vim.fn.exists(":Jam") == 2)
assert(vim.tbl_contains(jam.complete("p"), "play"))
assert(vim.tbl_contains(jam.complete("p"), "pause"))
assert(vim.tbl_contains(jam.complete("n"), "next"))
assert(vim.tbl_contains(jam.complete("n"), "now-playing"))
assert(require("telescope").extensions.jam ~= nil)

print("jam.nvim smoke tests passed")
