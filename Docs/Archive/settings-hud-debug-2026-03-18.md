# Settings And HUD Debug Notes - 2026-03-18

## Summary

This pass focused on mission-editor hangs triggered by changing settings from the PDA menu in `misn04`.

## What Was Fixed

- General PDA settings changes no longer force the old inline redraw path that was hanging the game.
- PDA menu changes now queue a deferred overlay refresh instead of rebuilding the overlay during the same input action.
- Generic settings application was narrowed so simple PDA-only settings do not reapply unrelated systems.
- The legacy scrap/pilot HUD sprite bridge was disabled from Lua after native logging showed it was probing live HUD sprite memory and failing.
- Scrap/pilot legacy mode now prefers top-left placement APIs and currently uses a stable virtual HUD anchor intended to sit beside the stock command menu.

## Key Evidence

- `BZLogger.txt` showed successful config saves followed by hangs before the old live-refresh path completed.
- `winmm_shim.log` showed HUD bridge failures while toggling scrap/pilot layout:
  - `Failed discovering sprite rect table in live process memory`
  - `Failed reading live rect entry for sprite 'scrap_panel'`
  - `Failed reading live rect entry for sprite 'pilot_panel'`

## Current Behavior

- `PDA Size` now applies without hanging.
- Scrap/pilot layout toggles no longer hang after the sprite bridge was disabled.
- Legacy scrap/pilot layout still needs visual tuning if the current top-left anchor is not yet matching the desired stock-adjacent placement on all setups.
- `Radar Size` and `Lighting Mode` are intended to apply during a live mission; if either fails to update immediately, treat that as a regression in the hot-swap path rather than expected behavior.

## Follow-Up

- Verify the current legacy scrap/pilot anchor against the desired command-menu-relative placement across different HUD scales and resolutions.
- Verify that `Radar Size` and `Lighting Mode` apply correctly immediately in a live mission and still persist on the next mission load.
- If live refresh for radar or lighting is needed again, reintroduce it only after isolating the native-side hang source.
