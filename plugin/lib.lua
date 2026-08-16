local wezterm = require("wezterm")
local M = {}

function M.safe_run(command)
  if type(command) ~= "table" or type(command[1]) ~= "string" or command[1] == "" then
    error("safe_run() requires a non-empty argument array")
  end

  local success, stdout, stderr = wezterm.run_child_process(command)
  if os.getenv("WEZTERM_DEBUG") == "1" then
    wezterm.log_error(string.format(
      "[DEBUG] %s exited with success=%s",
      command[1],
      tostring(success)
    ))
  end
  return success, stdout, stderr
end

return M
