# wezterm-media

System-wide Now Playing status bar and media controls for [WezTerm](https://wezfurlong.org/wezterm/) on macOS.

## Features

- **Now Playing display** in WezTerm status bar with animated equalizer
- **System-wide media detection** - works with Apple Music, Spotify, browsers, and any app using MediaRemote
- **Media controls** via keyboard shortcuts - play/pause, next, previous, volume
- **App-aware icons** - different icons for music apps, browsers, podcasts, etc.
- **Scrolling marquee** for long track names
- **Configurable** - animation speed, equalizer style, display width, colors, optional controls/volume/date
- **Composable** - `skip_handler` lets it share the status bar with other plugins

## Requirements

- macOS 14+ (Sonoma or later)
- Xcode Command Line Tools (`xcrun swift`/`swiftc`)
- WezTerm terminal
- [Nerd Font](https://www.nerdfonts.com/) for icons

## Installation

### Using WezTerm Plugin Manager

Add to your `wezterm.lua`:

```lua
local wezterm = require("wezterm")
local media = wezterm.plugin.require("https://github.com/KevinTCoughlin/wezterm-media")
```

### Manual Installation

```bash
git clone https://github.com/KevinTCoughlin/wezterm-media ~/.config/wezterm/plugins/wezterm-media
chmod +x ~/.config/wezterm/plugins/wezterm-media/helpers/*
```

## Usage

### Basic Setup

```lua
local wezterm = require("wezterm")
local config = wezterm.config_builder()

-- Load plugin
local media = wezterm.plugin.require("https://github.com/KevinTCoughlin/wezterm-media")

-- Apply with default settings
media.apply_to_config(config)

return config
```

### With Custom Configuration

```lua
local media = wezterm.plugin.require("https://github.com/KevinTCoughlin/wezterm-media")

media.apply_to_config(config, {
  -- Display settings
  scroll_speed = 3,          -- 1-5, characters to scroll per tick
  scroll_width = 35,         -- visible characters for track name
  scroll_padding = "  ·  ",  -- gap between repeats of a scrolling title
  update_interval = 500,     -- ms between redraws / animation frames (minimum: 250)
  refresh_interval = 1,      -- seconds between Now Playing queries
  eq_style = "wave",         -- "wave", "thin", "classic", "dots", "mini"

  -- Optional elements
  show_app_icon = true,      -- app icon (Music, Spotify, browser, ...)
  show_controls = false,     -- 󰒮 󰏤 󰒭 indicators
  show_volume = false,       -- system output volume icon
  show_date = false,         -- date/time after the media block
  date_format = "%a %b %-d %H:%M",
  separator = "  │  ",       -- between media and date

  -- Colors (any field can be overridden; eq defaults to the app's color)
  colors = {
    track = "#c0caf5", controls = "#7dcfff", play = "#9ece6a",
    pause = "#f7768e", volume = "#bb9af7", date = "#565f89",
  },

  -- Key bindings (set keys = false to disable)
  keys = {
    mods = "OPT|SHIFT",      -- modifier keys
    play_pause = "Space",    -- Opt+Shift+Space
    next_track = "n",        -- Opt+Shift+n
    prev_track = "p",        -- Opt+Shift+p
    vol_up = "=",            -- Opt+Shift+=
    vol_down = "-",          -- Opt+Shift+-
  },
})
```

### Sharing the Status Bar with Other Plugins

By default the plugin owns `update-status` and sets the right status. To
combine it with other elements, pass `skip_handler = true` and build the bar
yourself:

```lua
local media_opts = media.apply_to_config(config, { skip_handler = true, keys = false })
media.setup_keys(config, "LEADER", media_opts) -- LEADER m / > / < / + / _

wezterm.on("update-status", function(window, pane)
  local elements = media.get_status_elements(media_opts)
  -- append your own elements here
  window:set_right_status(wezterm.format(elements))
end)
```

`setup_keys(config, mods, opts)` adds `mods+m` play/pause, `mods+Shift+>`
next, `mods+Shift+<` previous, `mods+Shift++` volume up and `mods+Shift+_`
volume down.

### Standalone Helpers

The plugin starts a single `nowplaying --watch` process that refreshes a cache
file in `~/Library/Caches/wezterm-media` every `refresh_interval` seconds; each
status tick only reads that file. The watcher exits about 30 seconds after
WezTerm stops touching its heartbeat file. Set `helper_mode = "oneshot"` to run
the helper once per refresh instead.

The helpers can be used independently. On macOS 14 and 15, `nowplaying`
compiles an optimized binary into `~/Library/Caches/wezterm-media` and reuses
it. On macOS 26 and later it runs as a Swift script because unsigned compiled
clients cannot reliably access MediaRemote there.

```bash
# Query now playing info
~/.config/wezterm/plugins/wezterm-media/helpers/nowplaying
# Output: Song Title|Artist Name|true|com.spotify.client

# Keep a cache file fresh (what the plugin runs)
~/.config/wezterm/plugins/wezterm-media/helpers/nowplaying --watch /tmp/np.out /tmp/np.heartbeat 1

# Control playback
~/.config/wezterm/plugins/wezterm-media/helpers/mediactl togglePlayPause
~/.config/wezterm/plugins/wezterm-media/helpers/mediactl next
~/.config/wezterm/plugins/wezterm-media/helpers/mediactl previous
```

## Migrating from wezterm-apple-music

[wezterm-apple-music](https://github.com/KevinTCoughlin/wezterm-apple-music)
is archived. wezterm-media covers the same features for any Now Playing app.

| wezterm-apple-music | wezterm-media |
|---|---|
| `require("plugins.apple-media")` | `wezterm.plugin.require("https://github.com/KevinTCoughlin/wezterm-media")` |
| `apply_to_config(config, { skip_handler = true })` | same; also pass `keys = false` if you use `setup_keys` |
| `get_elements(opts)` | `get_status_elements(opts)` (`get_elements` still works) |
| `setup_keys(config, "LEADER")` | `setup_keys(config, "LEADER", opts)` |
| `eq_style` default `"thin"` | default `"wave"`; set `eq_style = "thin"` to keep the old look |
| `show_controls`, `show_volume`, `show_date` default on | default off; enable them explicitly |
| `show_app_icon`, `date_format`, `colors`, `scroll_padding` | same names |
| Volume keys change the app's volume | Volume keys change system output volume |
| Controls go to Music/Podcasts/TV via AppleScript | Media keys go to whichever app macOS routes them to |

## Equalizer Styles

| Style | Preview |
|-------|---------|
| `wave` | ∿∿∿ ∾∿∿ ∿∾∿ |
| `thin` | ▏▎▍ ▎▍▌ ▍▌▋ |
| `classic` | ▁▃▅ ▂▅▃ ▃▂▅ |
| `dots` | ●○● ○●○ ●●○ |
| `mini` | ⠋ ⠙ ⠹ ⠸ |

## Supported Apps

Works with any app that uses macOS MediaRemote framework:

| App | Icon |
|-----|------|
| Apple Music | 󰎆 |
| Spotify | 󰓇 |
| Apple Podcasts | 󰦔 |
| Apple TV | 󰕼 |
| Chrome, Firefox, Safari, Arc | 󰖟 |
| Other apps | 󰝚 |

## How It Works

This plugin uses macOS's private MediaRemote framework to:

1. **Query Now Playing info** - The `nowplaying` helper uses `MRMediaRemoteGetNowPlayingInfo` to get currently playing track info from any app
2. **Send media commands** - The `mediactl` helper simulates media key events (play/pause, next, previous) via CGEvent

MediaRemote is a private macOS framework. Apple can change it without notice,
so compatibility cannot be guaranteed across future macOS releases.

## Troubleshooting

### No output from nowplaying helper

- Ensure media is actually playing (check Control Center)
- Some apps don't register with MediaRemote until playback starts
- Run `xcode-select --install` if the helper reports that `xcrun`, `swift`, or
  `swiftc` is unavailable
- On macOS 14 or 15, remove `~/Library/Caches/wezterm-media/nowplaying` to
  force a rebuild

### Media controls not working

- Grant accessibility permissions to WezTerm in System Preferences > Privacy & Security > Accessibility
- Some apps may not respond to simulated media keys

## License

MIT License - See [LICENSE](LICENSE) for details.

## Contributing

Contributions welcome! Please open an issue or PR.

## Author

Kevin T. Coughlin ([@kevintcoughlin](https://github.com/KevinTCoughlin))

## Related Projects

- [wezterm-ollama](https://github.com/KevinTCoughlin/wezterm-ollama) - Ollama integration for WezTerm
