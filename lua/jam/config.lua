local M = {}

M.defaults = {
  provider = "spotify",
  search = {
    debounce_ms = 250,
    limit = 30,
    types = { "track", "album", "artist", "playlist", "show", "episode" },
  },
  artwork = {
    enabled = true,
    backend = "auto",
    width = 38,
    height = 16,
    cache = true,
  },
  picker = {
    layout_strategy = "flex",
    layout_config = {
      width = 0.9,
      height = 0.8,
      horizontal = {
        preview_width = 0.45,
      },
      vertical = {
        preview_height = 0.45,
      },
    },
  },
  providers = {
    spotify = {
      client_id = nil,
      redirect_uri = "http://127.0.0.1:8765/callback",
      scopes = {
        "user-read-playback-state",
        "user-modify-playback-state",
        "user-library-read",
        "user-read-recently-played",
        "playlist-read-private",
      },
    },
  },
}

M.values = vim.deepcopy(M.defaults)

function M.setup(opts)
  opts = opts or {}
  vim.validate("opts", opts, "table")
  M.values = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), opts)
  return M.values
end

return M
