-- wezterm-media: System-wide Now Playing status bar and media controls
-- https://github.com/KevinTCoughlin/wezterm-media
-- SPDX-License-Identifier: MIT

local wezterm = require("wezterm")
local utils = require("plugin.lib")

local M = {}

-- Default configuration
local defaults = {
  scroll_speed = 3,
  scroll_width = 35,
  update_interval = 150,
  eq_style = "wave",
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
}

-- Get plugin directory
local function get_plugin_dir()
  -- When loaded via wezterm.plugin.require, this file is at plugin/init.lua
  local info = debug.getinfo(1, "S")
  local path = info.source:match("@?(.*)")
  return path:match("(.*/)")  .. "../helpers"
end

-- Query now playing info via helper
local function get_now_playing(helper_dir)
  local helper_path = helper_dir .. "/nowplaying"
  local success, output = utils.safe_run({ helper_path })
  if not success or not output then 
    return nil 
  end

  local result = output:gsub("^%s*(.-)%s*$", "%1")
  if result == "" then 
    return nil 
  end

  local title, artist, playing, bundle_id = result:match("^([^|]*)|([^|]*)|([^|]*)|(.*)$")
  if not title or title == "" then 
    return nil 
  end

  local is_playing = playing == "true"
  local track = artist ~= "" and (title .. " — " .. artist) or title
  return { track = track, is_playing = is_playing, bundle_id = bundle_id }
end

-- Get icon for app
local function get_app_icon(bundle_id)
  return app_icons[bundle_id] or default_icon
end

-- Build status bar elements
function M.get_status_elements(opts)
  opts = opts or {}
  local helper_dir = opts.helper_dir or get_plugin_dir()
  local config = opts.config or defaults
  local eq_frames = eq_styles[config.eq_style] or eq_styles.wave

  local now_playing = get_now_playing(helper_dir)
  if not now_playing then
    return {}
  end

  local track = now_playing.track
  local is_playing = now_playing.is_playing
  local media = get_app_icon(now_playing.bundle_id)

  -- Reset scroll position on track change
  if track ~= state.last_track then
    state.last_track = track
    state.position = 0
  end

  -- Scrolling marquee
  local display = track
  if #track > config.scroll_width then
    local padding = "  ·  "
    local scroll = track .. padding .. track
    display = scroll:sub(state.position + 1, state.position + config.scroll_width)
    state.position = (state.position + config.scroll_speed) % (#track + #padding)
  end

  -- Animate equalizer
  local eq = is_playing and eq_frames[state.eq_frame] or "⏸"
  if is_playing then
    state.eq_frame = (state.eq_frame % #eq_frames) + 1
  end

  return {
    { Foreground = { Color = media.color } },
    { Text = media.icon .. " " },
    { Foreground = { Color = media.color } },
    { Text = eq .. "  " },
    { Foreground = { Color = "#c0caf5" } },
    { Text = display },
  }
end

-- Apply configuration to wezterm config
function M.apply_to_config(config, opts)
  opts = opts or {}
  local merged = {}
  for k, v in pairs(defaults) do merged[k] = v end
  for k, v in pairs(opts) do merged[k] = v end

  -- Merge key config
  if opts.keys ~= false then
    merged.keys = {}
    for k, v in pairs(defaults.keys) do merged.keys[k] = v end
    if type(opts.keys) == "table" then
      for k, v in pairs(opts.keys) do merged.keys[k] = v end
    end
  end

  local helper_dir = get_plugin_dir()

  -- Set status update interval
  config.status_update_interval = merged.update_interval

  -- Register status bar handler
  wezterm.on("update-status", function(window, pane)
    local elements = M.get_status_elements({
      helper_dir = helper_dir,
      config = merged,
    })
    if #elements > 0 then
      window:set_right_status(wezterm.format(elements))
    end
  end)

  -- Add key bindings
  if merged.keys then
    config.keys = config.keys or {}

    if merged.keys.play_pause then
      table.insert(config.keys, {
        key = merged.keys.play_pause,
        mods = merged.keys.mods,
        action = wezterm.action_callback(function()
          utils.safe_run({ helper_dir .. "/mediactl", "togglePlayPause" })
        end),
      })
    end

    if merged.keys.next_track then
      table.insert(config.keys, {
        key = merged.keys.next_track,
        mods = merged.keys.mods,
        action = wezterm.action_callback(function()
          utils.safe_run({ helper_dir .. "/mediactl", "next" })
        end),
      })
    end

    if merged.keys.prev_track then
      table.insert(config.keys, {
        key = merged.keys.prev_track,
        mods = merged.keys.mods,
        action = wezterm.action_callback(function()
          utils.safe_run({ helper_dir .. "/mediactl", "previous" })
        end),
      })
    end

    if merged.keys.vol_up then
      table.insert(config.keys, {
        key = merged.keys.vol_up,
        mods = merged.keys.mods,
        action = wezterm.action_callback(function()
          utils.safe_run({
            "osascript", "-e",
            "set volume output volume ((output volume of (get volume settings)) + 10)"
          })
        end),
      })
    end

    if merged.keys.vol_down then
      table.insert(config.keys, {
        key = merged.keys.vol_down,
        mods = merged.keys.mods,
        action = wezterm.action_callback(function()
          utils.safe_run({
            "osascript", "-e",
            "set volume output volume ((output volume of (get volume settings)) - 10)"
          })
        end),
      })
    end
  end

  return merged
end

return M
