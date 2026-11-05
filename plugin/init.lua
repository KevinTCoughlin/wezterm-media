-- wezterm-media: System-wide Now Playing status bar and media controls
-- https://github.com/KevinTCoughlin/wezterm-media
-- SPDX-License-Identifier: MIT

local wezterm = require("wezterm")
local source = debug.getinfo(1, "S").source:gsub("^@", "")
local plugin_dir = assert(source:match("^(.*[/\\])"), "unable to determine plugin directory")
local utils = dofile(plugin_dir .. "lib.lua")

local M = {}

-- Default configuration
local defaults = {
  scroll_speed = 3,
  scroll_width = 35,
  scroll_padding = "  ·  ",
  update_interval = 500,   -- ms between status redraws (animation speed)
  refresh_interval = 1,    -- seconds between Now Playing queries
  helper_mode = "watch",   -- "watch": one long-lived helper; "oneshot": run per refresh
  eq_style = "wave",
  skip_handler = false,    -- true: don't register update-status (compose it yourself)
  show_app_icon = true,
  show_controls = false,
  show_volume = false,
  show_date = false,
  date_format = "%a %b %-d %H:%M",
  separator = "  │  ",
  colors = {
    eq = nil,              -- nil: use the app's color
    track = "#c0caf5",
    controls = "#7dcfff",
    play = "#9ece6a",
    pause = "#f7768e",
    volume = "#bb9af7",
    date = "#565f89",
  },
  keys = {
    mods = "OPT|SHIFT",
    play_pause = "Space",
    next_track = "n",
    prev_track = "p",
    vol_up = "=",
    vol_down = "-",
  },
}

-- Equalizer animation frames
local eq_styles = {
  wave = { "∿∿∿", "∾∿∿", "∿∾∿", "∿∿∾" },
  thin = { "▏▎▍", "▎▍▌", "▍▌▋", "▌▋▊", "▋▊▉", "▊▉▊", "▉▊▋", "▊▋▌", "▋▌▍", "▌▍▎", "▍▎▏", "▎▏▎" },
  classic = { "▁▃▅", "▂▅▃", "▃▂▅", "▅▃▂", "▃▅▃", "▂▃▅" },
  dots = { "●○●", "○●○", "●●○", "○●●", "●○○", "○○●" },
  mini = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" },
}

local icons = {
  prev = "󰒮",
  play = "󰐊",
  pause = "󰏤",
  next = "󰒭",
  vol_mute = "󰖁",
  vol_low = "󰕿",
  vol_med = "󰖀",
  vol_high = "󰕾",
}

-- App bundle ID to icon/color mapping
local app_icons = {
  ["com.apple.Music"] = { icon = "󰎆", color = "#7aa2f7" },
  ["com.apple.TV"] = { icon = "󰕼", color = "#f7768e" },
  ["com.apple.podcasts"] = { icon = "󰦔", color = "#e0af68" },
  ["com.spotify.client"] = { icon = "󰓇", color = "#1DB954" },
  ["com.google.Chrome"] = { icon = "󰖟", color = "#9ece6a" },
  ["org.mozilla.firefox"] = { icon = "󰖟", color = "#9ece6a" },
  ["com.apple.Safari"] = { icon = "󰖟", color = "#9ece6a" },
  ["com.microsoft.edgemac"] = { icon = "󰖟", color = "#9ece6a" },
  ["com.brave.Browser"] = { icon = "󰖟", color = "#9ece6a" },
  ["company.thebrowser.Browser"] = { icon = "󰖟", color = "#9ece6a" }, -- Arc
}

local default_icon = { icon = "󰝚", color = "#bb9af7" }

-- Internal state
local state = {
  position = 0,
  last_track = "",
  eq_frame = 1,
  now_playing = nil,
  queried_at = nil,
  heartbeat_at = nil,
  spawned_at = nil,
  volume = nil,
  volume_at = nil,
}
local warned_unsupported = false
local helper_error_reported = false

local function default_helper_dir()
  return plugin_dir .. "../helpers"
end

-- Must match CACHE_ROOT in helpers/nowplaying.
local function default_cache_dir()
  local base = os.getenv("XDG_CACHE_HOME")
  if not base or base == "" then
    base = (os.getenv("HOME") or "") .. "/Library/Caches"
  end
  return base .. "/wezterm-media"
end

local function is_macos()
  return type(wezterm.target_triple) == "string"
    and wezterm.target_triple:find("apple%-darwin") ~= nil
end

local function utf8_len(value)
  local _, count = value:gsub("[^\128-\191]", "")
  return count
end

local function utf8_sub(value, first, last)
  local start_byte = utf8.offset(value, first)
  if not start_byte then return "" end
  local end_byte = utf8.offset(value, last + 1)
  return value:sub(start_byte, end_byte and (end_byte - 1) or -1)
end

local function copy(tbl)
  local out = {}
  for k, v in pairs(tbl) do out[k] = v end
  return out
end

-- Merge user options over defaults. `colors` and `keys` merge per field;
-- `keys = false` disables the default bindings.
local function merge_opts(opts)
  opts = opts or {}
  local merged = copy(defaults)
  for k, v in pairs(opts) do merged[k] = v end

  merged.colors = copy(defaults.colors)
  if type(opts.colors) == "table" then
    for k, v in pairs(opts.colors) do merged.colors[k] = v end
  end

  if opts.keys == false then
    merged.keys = false
  else
    merged.keys = copy(defaults.keys)
    if type(opts.keys) == "table" then
      for k, v in pairs(opts.keys) do merged.keys[k] = v end
    end
  end

  merged.update_interval = math.max(250, tonumber(merged.update_interval) or defaults.update_interval)
  merged.scroll_width = math.max(1, math.floor(tonumber(merged.scroll_width) or defaults.scroll_width))
  merged.scroll_speed = math.max(1, math.floor(tonumber(merged.scroll_speed) or defaults.scroll_speed))
  merged.refresh_interval = math.max(0, tonumber(merged.refresh_interval) or defaults.refresh_interval)
  merged.helper_dir = merged.helper_dir or default_helper_dir()
  merged.cache_dir = merged.cache_dir or default_cache_dir()
  merged._wezterm_media_merged = true
  return merged
end

local function parse_now_playing(output)
  local result = (output or ""):gsub("^%s*(.-)%s*$", "%1")
  if result == "" then return nil end

  local title, artist, playing, bundle_id = result:match("^([^|]*)|([^|]*)|([^|]*)|(.*)$")
  if not title or title == "" then return nil end

  local track = artist ~= "" and (title .. " — " .. artist) or title
  return { track = track, is_playing = playing == "true", bundle_id = bundle_id }
end

-- One-shot mode: run the helper at most once per refresh_interval.
local function query_oneshot(cfg, now)
  if state.queried_at and now - state.queried_at < cfg.refresh_interval then
    return state.now_playing
  end
  state.queried_at = now

  local success, output, stderr = utils.safe_run({ cfg.helper_dir .. "/nowplaying" })
  if not success or not output then
    if not helper_error_reported and stderr and stderr ~= "" then
      wezterm.log_error("nowplaying helper failed: " .. stderr)
      helper_error_reported = true
    end
    state.now_playing = nil
    return nil
  end
  helper_error_reported = false
  state.now_playing = parse_now_playing(output)
  return state.now_playing
end

-- Watch mode: a single `nowplaying --watch` process keeps a cache file
-- fresh; each tick only reads that file. The heartbeat file tells the
-- watcher WezTerm is still around; it exits on its own once we stop touching it.
local function query_watch(cfg, now)
  local interval = math.max(0.25, cfg.refresh_interval)
  local output_path = cfg.cache_dir .. "/nowplaying.out"
  local heartbeat_path = cfg.cache_dir .. "/nowplaying.heartbeat"

  if not state.heartbeat_at or now - state.heartbeat_at >= 5 then
    local beat = io.open(heartbeat_path, "w")
    if beat then
      beat:write(tostring(now))
      beat:close()
      state.heartbeat_at = now
    end
  end

  local stamp, payload
  local file = io.open(output_path, "r")
  if file then
    stamp = tonumber(file:read("l"))
    payload = file:read("l")
    file:close()
  end

  if stamp and now - stamp <= math.max(5, interval * 3) then
    return parse_now_playing(payload)
  end

  -- Missing or stale: (re)start the watcher, at most every 10 seconds.
  if not state.spawned_at or now - state.spawned_at >= 10 then
    state.spawned_at = now
    wezterm.background_child_process({
      cfg.helper_dir .. "/nowplaying", "--watch", output_path, heartbeat_path, tostring(interval),
    })
  end
  return nil
end

local function get_now_playing(cfg)
  if not is_macos() then
    if not warned_unsupported then
      wezterm.log_error("wezterm-media is only supported on macOS")
      warned_unsupported = true
    end
    return nil
  end

  local now = os.time()
  if cfg.helper_mode == "oneshot" then
    return query_oneshot(cfg, now)
  end
  return query_watch(cfg, now)
end

-- System output volume (0-100), refreshed at most every 5 seconds.
local function get_volume(cfg)
  local now = os.time()
  if state.volume_at and now - state.volume_at < math.max(5, cfg.refresh_interval) then
    return state.volume
  end
  state.volume_at = now
  local ok, out = utils.safe_run({
    "osascript",
    "-e", "set s to get volume settings",
    "-e", "if output muted of s then return 0",
    "-e", "return output volume of s",
  })
  state.volume = ok and tonumber((out or ""):match("%d+")) or nil
  return state.volume
end

local function volume_icon(volume)
  if volume == 0 then return icons.vol_mute end
  if volume <= 33 then return icons.vol_low end
  if volume <= 66 then return icons.vol_med end
  return icons.vol_high
end

local function get_app_icon(bundle_id)
  return app_icons[bundle_id] or default_icon
end

local function run_command(command, label)
  local ok, _, err = utils.safe_run(command)
  if not ok then
    wezterm.log_error(label .. " failed: " .. (err or "unknown error"))
  end
end

local function volume_command(delta)
  return {
    "osascript", "-e",
    string.format("set volume output volume ((output volume of (get volume settings)) %s %d)",
      delta < 0 and "-" or "+", math.abs(delta)),
  }
end

-- Build status bar elements.
-- Accepts the table returned by apply_to_config(), a plain options table,
-- or the older { config = ..., helper_dir = ... } form.
function M.get_status_elements(opts)
  opts = opts or {}
  local cfg = opts.config or opts
  if not cfg._wezterm_media_merged then
    cfg = merge_opts(cfg)
  end
  if opts.config and opts.helper_dir then
    cfg = copy(cfg)
    cfg.helper_dir = opts.helper_dir
  end

  local colors = cfg.colors
  local elements = {}
  local now_playing = get_now_playing(cfg)

  if now_playing then
    local track = now_playing.track
    local is_playing = now_playing.is_playing
    local app = get_app_icon(now_playing.bundle_id)
    local eq_frames = eq_styles[cfg.eq_style] or eq_styles.wave

    -- Reset scroll position on track change
    if track ~= state.last_track then
      state.last_track = track
      state.position = 0
    end

    -- Scrolling marquee
    local display = track
    local track_length = utf8_len(track)
    local padding = cfg.scroll_padding
    if track_length > cfg.scroll_width then
      local scroll = track .. padding .. track
      display = utf8_sub(scroll, state.position + 1, state.position + cfg.scroll_width)
      state.position = (state.position + cfg.scroll_speed)
        % (track_length + utf8_len(padding))
    end

    -- Animate equalizer
    local eq = is_playing and eq_frames[state.eq_frame] or "⏸"
    if is_playing then
      state.eq_frame = (state.eq_frame % #eq_frames) + 1
    end

    if cfg.show_app_icon then
      table.insert(elements, { Foreground = { Color = app.color } })
      table.insert(elements, { Text = app.icon .. " " })
    end

    table.insert(elements, { Foreground = { Color = colors.eq or app.color } })
    table.insert(elements, { Text = eq .. "  " })

    if cfg.show_controls then
      table.insert(elements, { Foreground = { Color = colors.controls } })
      table.insert(elements, { Text = icons.prev .. " " })
      table.insert(elements, { Foreground = { Color = is_playing and colors.pause or colors.play } })
      table.insert(elements, { Text = (is_playing and icons.pause or icons.play) .. " " })
      table.insert(elements, { Foreground = { Color = colors.controls } })
      table.insert(elements, { Text = icons.next .. "  " })
    end

    table.insert(elements, { Foreground = { Color = colors.track } })
    table.insert(elements, { Text = display })

    if cfg.show_volume then
      local volume = get_volume(cfg)
      if volume then
        table.insert(elements, { Foreground = { Color = colors.volume } })
        table.insert(elements, { Text = "  " .. volume_icon(volume) })
      end
    end

    if cfg.show_date then
      table.insert(elements, { Foreground = { Color = colors.date } })
      table.insert(elements, { Text = cfg.separator })
    end
  end

  if cfg.show_date then
    table.insert(elements, { Foreground = { Color = colors.date } })
    table.insert(elements, { Text = wezterm.strftime(cfg.date_format) })
  end

  return elements
end

-- Alias for configs migrating from wezterm-apple-music.
M.get_elements = M.get_status_elements

-- Apply configuration to wezterm config
function M.apply_to_config(config, opts)
  local merged = merge_opts(opts)

  config.status_update_interval = merged.update_interval

  if not merged.skip_handler then
    wezterm.on("update-status", function(window, pane)
      local elements = M.get_status_elements(merged)
      window:set_right_status(#elements > 0 and wezterm.format(elements) or "")
    end)
  end

  if merged.keys then
    config.keys = config.keys or {}
    local helper_dir = merged.helper_dir
    local k = merged.keys

    local bindings = {
      { key = k.play_pause, cmd = { helper_dir .. "/mediactl", "togglePlayPause" }, label = "play/pause" },
      { key = k.next_track, cmd = { helper_dir .. "/mediactl", "next" }, label = "next track" },
      { key = k.prev_track, cmd = { helper_dir .. "/mediactl", "previous" }, label = "previous track" },
      { key = k.vol_up, cmd = volume_command(10), label = "volume up" },
      { key = k.vol_down, cmd = volume_command(-10), label = "volume down" },
    }
    for _, b in ipairs(bindings) do
      if b.key then
        table.insert(config.keys, {
          key = b.key,
          mods = k.mods,
          action = wezterm.action_callback(function()
            run_command(b.cmd, b.label)
          end),
        })
      end
    end
  end

  return merged
end

-- Leader-style bindings matching wezterm-apple-music:
-- <mods> m play/pause, > next, < previous, + volume up, _ volume down.
-- `opts` may be the table returned by apply_to_config().
function M.setup_keys(config, mods, opts)
  mods = mods or "LEADER"
  local helper_dir = (opts and opts.helper_dir) or default_helper_dir()
  config.keys = config.keys or {}

  local bindings = {
    { key = "m", cmd = { helper_dir .. "/mediactl", "togglePlayPause" }, label = "play/pause" },
    { key = ">", shift = true, cmd = { helper_dir .. "/mediactl", "next" }, label = "next track" },
    { key = "<", shift = true, cmd = { helper_dir .. "/mediactl", "previous" }, label = "previous track" },
    { key = "+", shift = true, cmd = volume_command(10), label = "volume up" },
    { key = "_", shift = true, cmd = volume_command(-10), label = "volume down" },
  }
  for _, b in ipairs(bindings) do
    table.insert(config.keys, {
      key = b.key,
      mods = b.shift and (mods .. "|SHIFT") or mods,
      action = wezterm.action_callback(function()
        run_command(b.cmd, b.label)
      end),
    })
  end
end

return M
