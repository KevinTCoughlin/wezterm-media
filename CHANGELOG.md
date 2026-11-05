# Changelog

## Unreleased

- Add a watch mode: one long-lived `nowplaying --watch` process refreshes a
  cache file and the status bar only reads it, so macOS 26 no longer
  interprets the Swift helper on every tick. `refresh_interval` sets how often
  it queries; `helper_mode = "oneshot"` keeps the old per-query behavior.
- Fix `mediactl` media key codes (16/17/18, per `ev_keymap.h`); the previous
  values did not map to any media key.
- Add wezterm-apple-music options: `skip_handler`, `show_controls`,
  `show_volume`, `show_app_icon`, `show_date`, `date_format`, `separator`,
  `colors`, `scroll_padding`.
- Add `setup_keys(config, mods, opts)` with the apple-music Leader bindings,
  and `get_elements` as an alias of `get_status_elements`.
- `get_status_elements` accepts the table returned by `apply_to_config`.

- Resolve internal Lua modules relative to `plugin/init.lua`, matching the
  actual WezTerm plugin loader environment.
- Run the Swift helper interpreted on macOS 26+ to retain MediaRemote access;
  cache an optimized binary on earlier supported releases.
- Preserve UTF-8 while scrolling and clear stale status output.
- Add platform guards, process error reporting, tests, and CI.
- Correct the media-control command contract.
