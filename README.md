# wezterm-media

System-wide Now Playing status bar and media controls for [WezTerm](https://wezfurlong.org/wezterm/) on macOS.

![Demo](https://github.com/KevinTCoughlin/wezterm-media/raw/main/demo.gif)

## Features

- **Now Playing display** in WezTerm status bar with animated equalizer
- **System-wide media detection** - works with Apple Music, Spotify, browsers, and any app using MediaRemote
- **Media controls** via keyboard shortcuts - play/pause, next, previous, volume
- **App-aware icons** - different icons for music apps, browsers, podcasts, etc.
- **Scrolling marquee** for long track names
- **Configurable** - animation speed, equalizer style, display width

## Requirements

- macOS 14+ (Sonoma or later)
- Swift runtime (included with macOS)
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
  scroll_speed = 3,        -- 1-5, characters to scroll per tick
  scroll_width = 35,       -- visible characters for track name
  update_interval = 150,   -- milliseconds between updates
  eq_style = "wave",       -- "wave", "thin", "classic", "dots", "mini"

  -- Key bindings (set to false to disable)
  keys = {
    mods = "OPT|SHIFT",    -- modifier keys
    play_pause = "Space",  -- Opt+Shift+Space
    next_track = "n",      -- Opt+Shift+n
    prev_track = "p",      -- Opt+Shift+p
    vol_up = "=",          -- Opt+Shift+=
    vol_down = "-",        -- Opt+Shift+-
  },
})
```

### Standalone Helpers

The helpers can be used independently:

```bash
# Query now playing info
~/.config/wezterm/plugins/wezterm-media/helpers/nowplaying
# Output: Song Title|Artist Name|true|com.spotify.client

# Control playback
~/.config/wezterm/plugins/wezterm-media/helpers/mediactl togglePlayPause
~/.config/wezterm/plugins/wezterm-media/helpers/mediactl next
~/.config/wezterm/plugins/wezterm-media/helpers/mediactl previous
```

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

The MediaRemote framework is the same API that Control Center and the notch media widget use, ensuring compatibility with all media apps.

## Troubleshooting

### No output from nowplaying helper

- Ensure media is actually playing (check Control Center)
- Some apps don't register with MediaRemote until playback starts
- The helper must be run as a script (not compiled) on macOS 26+

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
- [wezterm-battery](https://github.com/KevinTCoughlin/wezterm-battery) - Battery status for WezTerm
