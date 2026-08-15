# Changelog

## 2026-08-15

Covers everything since the 2026-08-06 Workshop upload.

### Destruction Chunks
- Buildings and vehicles now break apart into their real modelled pieces in many
  places that previously threw generic rock debris. The number of visible pieces
  falling back to a generic placeholder dropped from 177 to 62.
- Fixed the Hadean relic buildings, whose models name their pieces after
  modelling-tool nodes rather than the names the game asks for. The correct
  mapping was recovered by matching each Redux piece against the original
  Battlezone geometry of the same building.
- Fixed the NSDF hangar, which shipped every piece under a duplicate bone name
  and so exploded entirely into placeholders.
- Added the missing Black Dog storage bay and second barracks pieces, and the
  NSDF/Black Dog landing pad piece whose model bone carries a stray underscore.
- Black Dog buildings now use their own textures when they shatter instead of
  borrowing the NSDF equivalents.
- Chunk pieces keep the shading the artists authored. A toolchain change had
  started rebuilding normals from scratch, which shades blocky debris as though
  it were smooth.
- Interior caps are generated for the new pieces, so freshly broken chunks read
  as solid rather than hollow shells.

### AutoSave
- The AutoSave button on the load screen now names the mission it will restore
  instead of just reading "AutoSave". This works without EXU installed.
- Career statistics no longer file every autosave-resumed session under a single
  bogus mission.

### Rendering (DX11 Enhanced)
- Static image-based lighting across base and terrain shaders, with a neutral
  reference asset set.
- Legacy-PBR lighting for base and terrain, with terrain tuning that preserves
  emissive surfaces across level-of-detail changes.
- Atmospheric rendering pass, and an experimental linear-light colour path.
- PDA and EXU overlays render correctly on DX11: programmable overlay and font
  materials, a tint shader, and a corrected panel vertex input layout.
- Added a DX11 shader validator and wired it into CI, plus a colour-space audit
  and runtime probe.

### Missions
- Scripted enemies in missions 02B, 03, 04 and 05 are kept out of the general AI
  pool, including across save and load.
- Restored Mission 04's fallback defender position and fixed an overlay call left
  behind by an ownership refactor.

### Multiplayer and Engine
- Lobby name panel: clicks register, long names truncate correctly, and renaming
  applies at connect time.
- Ogre runtime resolver and an animation/render overhead profiler for diagnosing
  performance.
- HD terrain path and semantic terrain streaming, opt-in.
- `openshim.ini` is now an exhaustive configuration reference and runtime feature
  gates are driven from it rather than environment variables.
- Observational network instrumentation for diagnosing multiplayer issues; it
  records nothing without being explicitly enabled and redacts identities.

### Housekeeping
- Retired legacy scripts, hardened the campaign runtime, and defined the
  project's actual scope in the README.
- Workshop publishing is automated and the capped chunk-mesh tree is routed
  through deploy correctly.

## 2026-07-16

### PDA Navigation and Readability
- Reorganized the PDA into `COMBAT`, `RECORDS`, `LOGISTICS`, and `SYSTEM` groups with short contextual sub-tabs.
- Reordered pages around player workflow while retaining all seven views and their existing controls.
- Streamlined the unit, target, career, command, queue, and loadout readouts; weapon details now use an Up/Down inspection cursor instead of expanding every hardpoint at once.
- Split Settings into focused `Interface`, `Lighting`, `Audio & Alerts`, `Assistance`, `Saves`, and `System` categories while preserving continuous Up/Down navigation through every option.

### AutoSave Notice
- Extended the `Autosaving...` notice to five seconds and moved its dedicated EXU overlay to the bottom center of the screen.

## 2026-07-13

### Neutral Hit Reticle
- Restored the persistent PDA `NEUTRAL ONLY` hit-reticle option now that OpenShim reads the Redux GameObject team through the correct `+0x18` interface subobject.
- Saved mode `2` values are preserved and applied again instead of being migrated back to `DEFAULT`.

## 2026-07-12

### Empty Craft Running Lights
- Added a persistent `Empty Craft Lights` PDA setting. By default, valid craft without a pilot now use an Ogre material variant with emissive lighting disabled; enabling the setting restores normal emissive running lights on empty craft.
- The runtime visual pass uses `IsAliveAndPilot()` and reapplies the occupied emissive variant when a pilot enters the craft.
- Added an optional persistent `Light Pulse` PDA setting. In enhanced lighting mode, occupied/emissive material variants now use a slow 2.4-second shader intensity pulse while empty variants remain black.
- Added a persistent `Star Twinkle` PDA setting. The dedicated `STARS.MAP` pass now uses the campaign Ogre sky shader and gives star cells independent, time-driven brightness variation without per-frame Lua updates.

## 2026-03-24

### Mission Startup Hang Fix
- Fixed a mission-start hang that reproduced on `misn02b.bzn /edit` after `Game Simulation Initialized` completed.
- Root cause: startup still had two blocking `bzfile` read paths. `PersistentConfig` could scan the live `bzlogger.txt` stream while the game was still writing it, and `CareerStats` could open a missing `career_stats.cfg` as a zombie handle and then hang on the first read.
- `PersistentConfig` now relies on `exu.GetSteam64()` for Steam identification and keeps the `bzlogger.txt` fallback disabled until a non-blocking reader exists.
- `CareerStats` now checks file existence before opening `career_stats.cfg`, which avoids the zombie-handle read hang while preserving normal stats loads when the file is present.

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
