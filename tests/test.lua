local root = arg[1] or "."
local handlers = {}
local calls = {}
local background = {}
local helper_output = "Café 東京|Björk|true|com.spotify.client"

local wezterm = {
  target_triple = "aarch64-apple-darwin",
  action_callback = function(callback) return callback end,
  format = function(elements) return elements end,
  log_error = function() end,
  strftime = function() return "Wed Nov 4 21:00" end,
  on = function(name, callback) handlers[name] = callback end,
  run_child_process = function(command)
    table.insert(calls, command)
    if command[1] == "osascript" then
      return true, "42\n", ""
    end
    return true, helper_output, ""
  end,
  background_child_process = function(command)
    table.insert(background, command)
  end,
}

package.preload.wezterm = function() return wezterm end
package.path = "/nonexistent/?.lua"

local function load_plugin()
  handlers = {}
  return assert(loadfile(root .. "/plugin/init.lua"))()
end

local function texts(elements)
  local out = {}
  for _, element in ipairs(elements) do
    if type(element) == "table" and element.Text then
      assert(utf8.len(element.Text), "status contains invalid UTF-8")
      table.insert(out, element.Text)
    end
  end
  return table.concat(out)
end

local status
local window = {
  set_right_status = function(_, value) status = value end,
}

-- Oneshot mode: helper runs every refresh (0 = every tick).
local media = load_plugin()
local config = {}
local merged = media.apply_to_config(config, {
  helper_dir = "/fixture",
  helper_mode = "oneshot",
  refresh_interval = 0,
  scroll_width = 5,
  keys = false,
})
assert(merged.update_interval == 500, "unexpected default update interval")
assert(config.keys == nil, "keys=false must disable media bindings")

handlers["update-status"](window, {})
assert(calls[1][1] == "/fixture/nowplaying", "custom helper directory was ignored")
assert(type(status) == "table" and #status > 0, "expected formatted media status")
texts(status)

helper_output = ""
handlers["update-status"](window, {})
assert(status == "", "empty helper output must clear stale status")

wezterm.target_triple = "x86_64-unknown-linux-gnu"
local process_count = #calls
handlers["update-status"](window, {})
assert(status == "", "unsupported platforms must keep status empty")
assert(#calls == process_count, "unsupported platforms must not run helpers")
wezterm.target_triple = "aarch64-apple-darwin"

-- Oneshot mode throttles to refresh_interval.
media = load_plugin()
calls = {}
helper_output = "Song|Artist|true|com.apple.Music"
local throttled = media.apply_to_config({}, {
  helper_dir = "/fixture", helper_mode = "oneshot", refresh_interval = 60, keys = false,
})
media.get_status_elements(throttled)
media.get_status_elements(throttled)
assert(#calls == 1, "oneshot mode must not query more than once per refresh_interval")

-- Watch mode: reads the cache file and spawns one watcher when it is stale.
local cache_dir = os.tmpname()
os.remove(cache_dir)
assert(os.execute("mkdir -p '" .. cache_dir .. "'"))
local out_path = cache_dir .. "/nowplaying.out"

media = load_plugin()
calls = {}
background = {}
local watch = media.apply_to_config({}, {
  helper_dir = "/fixture", cache_dir = cache_dir, skip_handler = true, keys = false,
})
assert(handlers["update-status"] == nil, "skip_handler must not register update-status")

local first = media.get_status_elements(watch)
assert(#first == 0, "no cache file yet: status must be empty")
assert(#background == 1, "missing cache must start the watcher")
assert(background[1][1] == "/fixture/nowplaying" and background[1][2] == "--watch",
  "watcher must be started with --watch")
assert(background[1][3] == out_path, "watcher output path mismatch")
media.get_status_elements(watch)
assert(#background == 1, "watcher must not be respawned every tick")
local beat = io.open(cache_dir .. "/nowplaying.heartbeat", "r")
assert(beat, "heartbeat file must be written")
beat:close()

local file = assert(io.open(out_path, "w"))
file:write(os.time() .. "\nTrack|Band|false|com.apple.Music\n")
file:close()
local fresh = texts(media.get_status_elements(watch))
assert(fresh:find("Track — Band", 1, true), "fresh cache must be displayed")
assert(fresh:find("⏸", 1, true), "paused state must show ⏸")
assert(#calls == 0, "watch mode must not run the helper synchronously")

file = assert(io.open(out_path, "w"))
file:write((os.time() - 600) .. "\nOld|Song|true|x\n")
file:close()
assert(#media.get_status_elements(watch) == 0, "stale cache must not be displayed")

-- apple-music parity options.
media = load_plugin()
calls = {}
helper_output = "Long Title|Artist|true|com.apple.Music"
local full = media.apply_to_config({}, {
  helper_dir = "/fixture", helper_mode = "oneshot", refresh_interval = 0,
  skip_handler = true, keys = false,
  show_controls = true, show_volume = true, show_date = true, show_app_icon = false,
  colors = { track = "#ffffff" },
})
assert(full.colors.track == "#ffffff" and full.colors.date == "#565f89", "colors must merge per field")
local rendered = media.get_elements(full)
local text = texts(rendered)
assert(not text:find("󰎆", 1, true), "show_app_icon=false must hide the app icon")
assert(text:find("󰒮", 1, true) and text:find("󰏤", 1, true), "show_controls must render controls")
assert(text:find("󰖀", 1, true), "show_volume must render the volume icon for 42%")
assert(text:find("  │  Wed Nov 4 21:00", 1, true), "show_date must render separator and date")

helper_output = ""
assert(texts(media.get_status_elements(full)) == "Wed Nov 4 21:00",
  "date must still render when nothing is playing")

-- Plain options table (not from apply_to_config) is accepted too.
assert(type(media.get_status_elements({ helper_dir = "/fixture", helper_mode = "oneshot" })) == "table")

-- Keys.
media = load_plugin()
local keyed = {}
media.apply_to_config(keyed, { helper_dir = "/fixture", skip_handler = true })
assert(#keyed.keys == 5, "default keys must add five bindings")
assert(keyed.keys[1].key == "Space" and keyed.keys[1].mods == "OPT|SHIFT", "default play/pause binding")

local leader = {}
media.setup_keys(leader, "LEADER", { helper_dir = "/fixture" })
assert(#leader.keys == 5, "setup_keys must add five bindings")
assert(leader.keys[1].key == "m" and leader.keys[1].mods == "LEADER", "leader play/pause binding")
assert(leader.keys[2].key == ">" and leader.keys[2].mods == "LEADER|SHIFT", "leader next binding")
calls = {}
leader.keys[1].action()
assert(calls[1][1] == "/fixture/mediactl" and calls[1][2] == "togglePlayPause", "play/pause must call mediactl")

os.execute("rm -rf '" .. cache_dir .. "'")
print("ok")
