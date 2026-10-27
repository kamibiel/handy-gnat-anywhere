# Changelog

## 1.0.2 — 2026-10-27
- Fix: freezes of several seconds (up to ~7 s in big worlds). The mod no longer walks every object
  in the game: it goes straight to the 19 places that hold the game mode settings — the game's
  default objects, the running GameInstance, and the world's active preset (reached through the
  mode manager's `GameModeSettings`). Measured: ~130 ms once when entering a world, instead of ~7 s.
- After applying, the log shows the game's own answer (`IsBuildModeAvailable`).
- Also unlocks the Custom game mode preset.
- `Ctrl+F7` re-applies; `Ctrl+Shift+F7` forces the old full scan as a last resort (it also
  remembers what it finds in `HandyGnatAnywhere_targets.txt` next to the game's exe).

## 1.0.1 — 2026-10-23
- Fix: small stutters when mounting/dismounting, respawning, etc. The full object scan now runs
  once per world; later events only re-apply to the places already found (cheap). Bursts of
  events are collapsed into a single apply. `Ctrl+F7` still forces a full scan.

## 1.0.0 — 2026-10-22
- First release: unlocks the Handy Gnat (`bBuildModeAvailable`) in Relaxed, Normal and Hard.
- Runtime UE4SS Lua mod, matches options by name (survives preset reordering in game updates).
- `Ctrl+F7` re-apply, `Ctrl+F6` free camera (optional).
