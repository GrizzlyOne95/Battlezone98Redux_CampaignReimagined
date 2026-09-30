# Operation Livewire: arrival / material prototype

This is the first playable source slice of the [showcase design](SHIM_EXU_SHOWCASE_DESIGN.md).
Launch `sxshow.bzn` in single player after blessing and deploying the new files.
The automatic film lasts 65 simulation seconds and hands control back for free play.
This checkpoint has host validation; it has not been deployed or observed in the game.

## What is implemented

| Film time | Visible action | Implementation |
| --- | --- | --- |
| 0–25 s | Approach a lunar outpost with a moving scout | `sx_arrive` camera path; one unarmed scout follows `sx_convoy_route` |
| 25–31 s | Orbit two identical scouts in their original materials | `sx_mat_a` camera path; capture every subentity assignment |
| 31–55 s | One scout becomes cyan with a slow emissive pulse | Clone source materials into `SX/Livewire/`; swap only the service scout; verify assignments and the control twin |
| 55–65 s | Return the service scout to its baseline | Restore the captured material names; finish the camera tour |
| After 65 s | Inspect, replay, compare, reset, or save/load | Console hooks, independent API/visual results, safe free-play load |

The prototype reuses the shipped `crsetup` lunar terrain and outpost. Its new text BZN
removes the seven hostile setup turrets, preserves the other 32 authored objects,
and adds six prefixed paths. Terrain remains `TerrainName = crsetup`; no duplicate
HG2, MAT, LGT, or TRN is introduced. The script builds exactly three owned `avfigh`
fixtures. It leaves the original player and outpost under normal stock control.
The final Mars setting and the later environment, AI tuning, chunks, filters,
radio, radar/HUD, command replacement, options/autosave, and multiplayer exhibits
remain in the design backlog. This slice does not certify those APIs.

The overlay uses the campaign's existing `CRBZoneOverlayFont`, pixel metrics,
resolution-aware layout, and three text rows. Native UI/pause menus hide it and
freeze the scene clock. Ordinary objectives also carry the controls. No stock HUD
visibility or saved user option is changed.

## Controls and results

Enter these in the stock game console:

| Command | Action |
| --- | --- |
| `sx tour` | Replay the entire film |
| `sx materials` | Replay only the 40-second material scene |
| `sx skip` or the native camera cancel control | End the film and restore originals |
| `sx service` | Apply the cyan comparison in free play |
| `sx baseline` | Restore original assignments |
| `sx visual pass` / `sx visual fail` | Record the operator's observation while the service variant is active |
| `sx report` | Print the results as `[SXSHOW]` log lines |
| `sx reset` | Restore and rebuild only the three owned fixtures, then replay |

`PASS` for materials means API assignment readback matched and the control twin
retained its original names. It does not prove a rendered cyan/glow appearance.
`Visual PENDING` stays separate until an operator records an observation. New
replays and loads invalidate that observation. Overlay creation also stays
`PENDING` in the machine report; its acceptance needs an on-screen check. Tour `PASS` means the authored camera
sequence completed; individual feature results can still be `BLOCKED` or `FAIL`.

Missing native EXU, its stub, unavailable APIs, render readiness timeout, and
partial native failures are reported instead of counted as supported features.
The stock camera tour can still run when the material exhibit is blocked.
Cancelled tours and assignment/pulse failures restore surviving fixtures. Deleted
fixtures block the exhibit until reset. A failed restoration retains the fixtures
instead of deleting them. Clone names are reused across replays and resets.

Save data contains primitive results, original material-name arrays, three game
handles, and a diagnostic scene snapshot. Load always ends the film and returns
to free play. It rebinds handles and restores saved baselines, retrying briefly
when render entities are not ready; it never resumes camera cues. This prototype
opts out of network games before creating overlays, cameras, or scripted fixtures.
That opt-out is a guard, not multiplayer qualification.

## Build and test from the canonical checkout

Use `%USERPROFILE%\Documents\GIT\Campaign-Reimagined` on
`agent/shim-exu-showcase`, preserving any unrelated local changes. This checkpoint
intentionally leaves `Shipping/shipping.lock.json` unchanged: the source files
were authored through GitHub without access to that checkout. They will not be
installed by the lock-based deploy until they are blessed there.

From the canonical repository root:

```powershell
lua Tools/Test-SXShowcase.lua Scripts
python Tools/Test-SXShowcaseAssets.py
.\Manage-CampaignFiles.ps1 -bless
git diff -- Shipping/shipping.lock.json
python Tools/Validate-CampaignRepository.py
.\Manage-CampaignFiles.ps1 -deploy
```

Use a Lua 5.1 interpreter for the first command when available. Bless should add
exactly these six runtime files, with no removals or unrelated membership changes:

- `Config/sxshow.ini` → `sxshow.ini`
- `Missions/sxshow.bzn` → `sxshow.bzn`
- `Scripts/sxshow.lua` → `sxshow.lua`
- `Scripts/SXDirector.lua` → `SXDirector.lua`
- `Scripts/SXMaterials.lua` → `SXMaterials.lua`
- `Scripts/SXOverlay.lua` → `SXOverlay.lua`

Review and commit the generated lock diff before deployment. The existing campaign
assets and native sibling deployment must be present; do not bless a partial source
tree. Use the GOG development target from [AGENTS.md](../AGENTS.md), not Steam's
Workshop cache. `Docs` and `Tools` are authoring files and are not runtime payload.

For game launches, use OpenShim's documented harness: dot-source
`reverse_engineering/BZRHarness.ps1`, serialize launches through its mutex,
set `BZR_FORCE_WINDOWED=1`, launch the deployed `sxshow.bzn`, and stop with
`Stop-BZRGame -Id` for the process you launched. Follow the current harness
instructions for executable/launch arguments; do not force-kill the game.

## Verification at this checkpoint

- `Tools/Test-SXShowcase.lua`: 47 host checks cover cue thresholds and hitches,
  cancellation, native API/stub gates, exact assignment readback, rollback,
  clone reuse, overlay recreation/menu/resolution handling, delayed load,
  readiness timeout, deleted fixtures, repeated reset, and network opt-out.
- `Tools/Test-SXShowcaseAssets.py`: 93 checks cover native text counts/IDs, preservation
  of setup objects/paths, path bindings and terrain bounds, shipped dependencies,
  and flattened runtime-name collisions.
- Repository Lua/filename/case checks were applied to the changed source files.
  The host run used Lua 5.3 (`texlua`); Lua 5.1 execution remains unverified.
- Native game loading, camera framing/speeds, terrain clearance, cyan/emissive
  shader visibility, font legibility, real handle remapping, and repeated
  mission entry remain unverified. Windows/GOG, Windows/Steam, Proton, and
  Wine lanes remain unverified. No release or Workshop qualification is claimed.

First in-game acceptance: watch the full film, cancel each scene, check the cyan
scout against the baseline twin, record visual results, restore, reset three times,
resize/open menus, and load a save made while the variant is active. Adjust camera
paths and fixture clearance after observing this small slice before adding the
next exhibit.
