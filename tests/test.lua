local root = arg[1] or "."
local handlers = {}
local calls = {}
local helper_output = "Café 東京|Björk|true|com.spotify.client"

local wezterm = {
  target_triple = "aarch64-apple-darwin",
  action_callback = function(callback) return callback end,
  format = function(elements) return elements end,
  log_error = function() end,
  on = function(name, callback) handlers[name] = callback end,
  run_child_process = function(command)
    table.insert(calls, command)
    return true, helper_output, ""
  end,
}

package.preload.wezterm = function() return wezterm end
package.path = "/nonexistent/?.lua"

local media = assert(loadfile(root .. "/plugin/init.lua"))()
local config = {}
local merged = media.apply_to_config(config, {
  helper_dir = "/fixture",
  scroll_width = 5,
  keys = false,
})
assert(merged.update_interval == 500, "unexpected default update interval")
assert(config.keys == nil, "keys=false must disable media bindings")

local status
local window = {
  set_right_status = function(_, value) status = value end,
}
handlers["update-status"](window, {})
assert(calls[1][1] == "/fixture/nowplaying", "custom helper directory was ignored")
assert(type(status) == "table" and #status > 0, "expected formatted media status")
for _, element in ipairs(status) do
  if type(element) == "table" and element.Text then
    assert(utf8.len(element.Text), "status contains invalid UTF-8")
  end
end

helper_output = ""
handlers["update-status"](window, {})
assert(status == "", "empty helper output must clear stale status")

wezterm.target_triple = "x86_64-unknown-linux-gnu"
local process_count = #calls
handlers["update-status"](window, {})
assert(status == "", "unsupported platforms must keep status empty")
assert(#calls == process_count, "unsupported platforms must not run helpers")
print("ok")
