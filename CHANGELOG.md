# Changelog

## 2026-03-08

### AI and Mission Fixes
- Fixed `aiCore` enemy-team selection so neutral `team 0` is no longer chosen as a primary enemy target set.
- Stopped misn04 CCA AI from fixating on neutral geysers during base assault behavior.
- Updated scripted mission control flow so player-team (`team 1`) command wrappers default to priority `0` and no longer steal unit control.
- Fixed misn04 player wingman scripted patrol and retreat orders to use commandable priorities.
- Fixed wingman auto-repair command restore priority so restored orders do not come back as uncommandable for player-owned units.

### Player Howitzer Improvements
- Added player howitzer range-assist behavior: attack orders issued against out-of-range targets now move the unit into firing position and resume attack automatically.
- Reworked the howitzer assist to use the currently equipped weapon and live weapon mask instead of a fixed hardcoded range.
- Added ODF-driven range probing for active weapons with fallbacks for direct range fields, projectile travel distance, and ballistic estimation.
- Fixed the helper ordering bug that caused `aiCore.lua` to error when loading before the `aiCore` table was initialized.

### PDA / Weapon HUD
- Moved the weapon details HUD into a right-side, vertically centered PDA-style panel.
- Added screen/aspect-aware panel sizing using EXU resolution helpers when available.
- Added player speed readout in meters per second.
- Added target closure rate and ETA when a valid hostile target is selected.
- Rebound the PDA / weapon HUD toggle from `Ctrl+S` to `Y`.
- Updated the in-game help overlay to match the new `Y` binding.

### Verification
- `luac -p _Source/Scripts/aiCore.lua`
- `luac -p _Source/Scripts/misn04.lua`
- `luac -p _Source/Scripts/PersistentConfig.lua`
