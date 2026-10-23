# Changelog

## 1.0.1 — 2026-10-23
- Fix: small stutters when mounting/dismounting, respawning, etc. The full object scan now runs
  once per world; later events only re-apply to the places already found (cheap). Bursts of
  events are collapsed into a single apply. `Ctrl+F7` still forces a full scan.

## 1.0.0 — 2026-10-22
- First release: unlocks the Handy Gnat (`bBuildModeAvailable`) in Relaxed, Normal and Hard.
- Runtime UE4SS Lua mod, matches options by name (survives preset reordering in game updates).
- `Ctrl+F7` re-apply, `Ctrl+F6` free camera (optional).
