# Changelog

## 2026-03-16

### Subtitle Overlay Migration
- Ported mission subtitles from the legacy subtitle DLL path to the built-in EXU/Ogre overlay runtime, while keeping the old DLL submission path as a fallback.
- Reworked subtitle rendering to use PDA-style overlay panels/materials instead of the previous shell-style subtitle window.
- Wired subtitle pause/suspension, opacity, and font scaling to the same persistent PDA settings used by the rest of the HUD.

### Target Page and Weapon Selection
- Updated the PDA `TARGET` page to use `exu.GetSelectedWeaponMask()` so it shows the player's currently selected weapons instead of collapsing to the top weapon slot.
- Added per-weapon in-range markers against the current target using the selected-weapon mask path.

### AutoSave HUD
- Moved the `Autosaving...` notification to a compact bottom-left overlay layout.
- Added an immediate mission-start autosave trigger when autosave is enabled so the overlay can be verified without waiting for the interval timer.

### HUD Settings
- Added a persistent `Radar Size` PDA setting backed by `exu.GetRadarSizeScale()` / `exu.SetRadarSizeScale()`.
- Reapply the saved radar size automatically if the stock HUD scaling menu overwrites the live radar layout scale.

### Verification
- `luac -p _Source/Scripts/ScriptSubtitles.lua`
- `luac -p _Source/Scripts/PersistentConfig.lua`
- `luac -p _Source/Scripts/AutoSave.lua`

## 2026-03-09

### PDA / Weapon HUD Expansion
- Reworked the weapon HUD into a multi-page PDA with `STATS`, `TARGET`, `SETTINGS`, and `PRESETS` pages.
- Moved the PDA panel to the left-middle of the screen and scaled it from EXU HUD/UI scale, screen aspect, and user size presets.
- Added PDA settings for text size, window size, and HUD color presets (`dark green`, `green`, `blue`, `white`).
- Added page navigation on `[` and `]`, plus arrow-key editing for `SETTINGS` and `PRESETS`.
- Added stock menu sound effects for PDA page changes and interactive settings changes.
- Updated the in-game help text to document the new PDA controls.

### Targeting and Weapon Data
- Added reticle-aware aim fallback so the PDA updates immediately from `GetReticleObject()` or `GetReticlePos()` when there is no explicit target lock.
- Added a dedicated `TARGET` page with unit name, target distance, closure/ETA, speed, ammo, hull, and hardpoint summaries.
- Improved weapon stat extraction to read `CannonClass` timing/range fields and ordnance damage correctly for cases like `gtminis2.odf`.
- Added cached ODF-driven weapon stats for range, damage, DPS, shot delay, shot speed, and ballistic detection.
- Added elevation-adjusted ballistic range estimation so mortar-style weapons show a more realistic effective range versus uphill or downhill targets.

### Unit Presets
- Added a `PRESETS` PDA page that inspects live recycler/factory build lists and armory upgrade pools.
- Added persistent per-unit, per-slot loadout presets sourced from actual armory powerups and mapped back to weapon ODFs.
- New player-built units now receive preset weapons on creation and charge a positive-only scrap surcharge when the preset is applied.
- Preset application is now gated by nearby production structure proximity so mission-spawned allied units are far less likely to be modified accidentally.
- Added `Armory not available` handling when no valid armory exists.

### Subtitle Runtime
- Bundled an updated `subtitles.dll` with channelized subtitle layout support used by the PDA window.

### Verification
- `luac -p _Source/Scripts/PersistentConfig.lua`

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
