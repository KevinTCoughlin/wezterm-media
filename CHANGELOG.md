# Changelog

## Unreleased

- Resolve internal Lua modules relative to `plugin/init.lua`, matching the
  actual WezTerm plugin loader environment.
- Run the Swift helper interpreted on macOS 26+ to retain MediaRemote access;
  cache an optimized binary on earlier supported releases.
- Preserve UTF-8 while scrolling and clear stale status output.
- Add platform guards, process error reporting, tests, and CI.
- Correct the media-control command contract.
