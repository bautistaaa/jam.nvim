# jam.nvim

Search Spotify and control playback from a Telescope picker without leaving Neovim.

> [!NOTE]
> jam.nvim is an early preview. Spotify is the first provider, and support for
> additional music services is planned as their official APIs allow.

## Features

- Live Spotify search for music, playlists, podcasts, and episodes
- Drill-down for album tracks, artist top tracks, podcast episodes, and playlist items
- Play, pause, skip, go back, and add tracks or episodes to the queue
- OAuth Authorization Code flow with PKCE—no client secret in your config
- Album-art previews through `image.nvim` or `chafa`, with automatic detection
- Contextual metadata for artists, albums, tracks, podcasts, and episodes
- `:Jam` and `:Telescope jam` entry points
- Health diagnostics with `:checkhealth jam`

## Requirements

Required:

- Neovim 0.10+
- [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim)
- `curl` for Spotify API requests
- `openssl` for PKCE authentication
- A Spotify account and [application client ID](#create-a-spotify-application)
- Spotify Premium and an active Spotify Connect device for playback control

Run `:checkhealth jam` after installation to verify these dependencies and your
configuration.

### Album artwork dependencies

Album artwork requires an optional renderer. Without one, the preview shows the
image URL as text.

- Install [`chafa`](https://hpjansson.org/chafa/) for a portable, full-color
  character-art preview
  (`brew install chafa` on macOS or `sudo apt install chafa` on Debian/Ubuntu).
- Or install [image.nvim](https://github.com/3rd/image.nvim) and use a compatible
  terminal such as Kitty or WezTerm.

`chafa` is the simplest cross-terminal option. Run `:checkhealth jam` to see
which artwork backend jam.nvim detected.

## Installation

### lazy.nvim

```lua
{
  "bautistaaa/jam.nvim",
  dependencies = {
    "nvim-telescope/telescope.nvim",
    -- Optional, for high-resolution artwork:
    -- { "3rd/image.nvim", opts = {} },
  },
  cmd = { "Jam" },
  opts = {
    providers = {
      spotify = {
        client_id = vim.env.SPOTIFY_CLIENT_ID,
      },
    },
  },
}
```

### Native `vim.pack`

```lua
vim.pack.add({
  "https://github.com/nvim-telescope/telescope.nvim",
  "https://github.com/bautistaaa/jam.nvim",
})

require("jam").setup({
  providers = {
    spotify = { client_id = vim.env.SPOTIFY_CLIENT_ID },
  },
})
```

### mini.deps

```lua
local add = MiniDeps.add
add({ source = "nvim-telescope/telescope.nvim" })
add({ source = "bautistaaa/jam.nvim" })
```

### packer.nvim

```lua
use({
  "bautistaaa/jam.nvim",
  requires = { "nvim-telescope/telescope.nvim" },
  config = function()
    require("jam").setup({
      providers = {
        spotify = { client_id = vim.env.SPOTIFY_CLIENT_ID },
      },
    })
  end,
})
```

### vim-plug

```vim
Plug 'nvim-telescope/telescope.nvim'
Plug 'bautistaaa/jam.nvim'
```

Then call `require("jam").setup(...)` from your Lua config.

## Spotify setup

### Create a Spotify application

1. Sign in to the [Spotify Developer Dashboard](https://developer.spotify.com/dashboard).
2. Select **Create app**.
3. Enter an app name and description. A website is not required for local use.
4. Add this exact redirect URI:

   ```text
   http://127.0.0.1:8765/callback
   ```

5. Select **Web API** when Spotify asks which APIs or SDKs the app will use,
   accept the terms, and save the app.
6. Open the app's settings and copy its **Client ID**. jam.nvim does not need
   the client secret; never put the secret in your Neovim configuration.

### Connect jam.nvim

1. Put the client ID in your shell environment:

   ```sh
   export SPOTIFY_CLIENT_ID="your-client-id"
   ```

   Add that line to `~/.zshrc`, `~/.bashrc`, or the equivalent for your shell,
   then start Neovim from a new terminal.
2. Run `:checkhealth jam` and resolve any reported errors.
3. Run `:Jam auth spotify` and finish authorization in the browser.
4. Open Spotify and play something once so Spotify Connect marks the selected
   device as active.
5. Run `:Jam`, enter a search, and press `<CR>` to play a result.

Tokens are stored with `0600` permissions under Neovim's data directory. Run
`:Jam logout` to remove them.

### Troubleshooting

- **`Device not found`**: jam.nvim opens the selected item in Spotify. Once the
  app is ready, select the item again. If needed, manually play a track once so
  the Web API considers the device active.
- **Artwork URL instead of an image**: Install `chafa`, or configure `image.nvim`
  in a compatible terminal, then reopen the picker.
- **Client ID is not configured**: Confirm `:echo $SPOTIFY_CLIENT_ID` prints your
  client ID. Restart Neovim from a new terminal after changing your shell
  configuration.
- **OAuth redirect errors**: Confirm the redirect URI in Spotify is exactly
  `http://127.0.0.1:8765/callback`.

## Usage

```vim
:Jam                    " Open search
:Jam search             " Open search
:Jam auth spotify       " Connect Spotify
:Jam play
:Jam pause
:Jam next
:Jam previous
:Jam now-playing
:Jam logout
:Jam health
:Telescope jam
```

Search filters:

| Prefix | Searches |
| --- | --- |
| `a:` | Albums |
| `t:` | Artists |
| `s:` | Songs/tracks |
| `l:` | Playlists |
| `p:` | Podcasts |
| `e:` | Podcast episodes |

For example, `a:Abbey Road`, `t:BTS`, `s:One More Night`, `l:Discover Weekly`,
`p:Radiolab`, or `e:Black Holes`. Queries without a prefix search all supported
item types.

Picker mappings:

| Mapping | Action |
| --- | --- |
| `<CR>` | Open a collection or play the selected track/episode |
| `<C-q>` | Add selection to queue |
| `<C-p>` | Pause playback |
| `<Esc>` | Return from a collection to the original search |

Selecting an album opens its tracks in disc and track order. Selecting an artist
opens their top tracks, selecting a podcast opens its episodes, and selecting a
playlist opens its items when Spotify allows it. Spotify Development Mode only
returns playlist contents for playlists you own or collaborate on; for other
playlists, jam.nvim plays the playlist instead. Press `<Esc>` in any collection
view to return to the same search query.

## Configuration

```lua
require("jam").setup({
  provider = "spotify",
  search = {
    debounce_ms = 250,
    limit = 30,
    types = { "track", "album", "artist", "playlist", "show", "episode" },
  },
  artwork = {
    enabled = true,
    backend = "auto", -- auto, image, chafa, text, or none
    width = 38,
    height = 16,
    cache = true,
  },
  picker = {
    layout_strategy = "flex",
  },
  providers = {
    spotify = {
      client_id = vim.env.SPOTIFY_CLIENT_ID,
      redirect_uri = "http://127.0.0.1:8765/callback",
    },
  },
})
```

## Provider roadmap

Provider adapters declare capabilities and implement the common search and
playback interface. The Telescope UI does not call Spotify-specific endpoints,
so additional providers can expose only the capabilities their APIs support.

Spotify is currently the only implemented provider. More providers are planned,
but no specific service or timeline is promised: authentication, catalog access,
and playback controls vary significantly between platforms, and some services
do not offer an official public playback API. Future adapters may therefore
support search, opening items in a native app, or playback controls in different
combinations.
