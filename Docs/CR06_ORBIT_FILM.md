# misn06 orbital insert (Lincoln Mayday)

Prototype cutscene for Escape from Mars. Stock misn06 ships the Lincoln Mayday voice lines
(`misn0625` "under attack", `misn0626` "Mayday... our engines are--") with no picture. This branch
adds a short orbital shot under that VO: the NSDF carrier Lincoln (`cr06lin`) runs from two CCA
cruisers (`cr06dst`), takes gunfire and breaks up as the last line cuts out.

Stacked on `agent/mars-rocket` (CR #228), which owns the launch film and the `cr06rok` rocket.

## Files

| File | Role |
| --- | --- |
| `Scripts/CR06OrbitFilm.lua` | Film: staging, ship motion, gunfire, blasts, scene override and cleanup. |
| `Scripts/misn06.lua` | `CR orbit film` blocks: API table, `Begin` on the restored vob4 cue, `Update`, `Stop` on Start/Load/Succeed/Fail. Atmosphere updates pause while the film runs. |
| `ODF/cr06lin.odf`, `ODF/cr06dst.odf` + `Assets/ModelFixes/cr06{lin,dst}.{mesh,geo,sdf}` | Capital ships (inert props). |
| `Materials/cr06lin.material`, `cr06dst.material`, `Assets/Textures/cr06{n,c}*` | Hull materials and baked textures. |
| `Materials/cr06_orbit.material`, `cr06_orbit.particle.payload` | Starfield dome, bolt/exhaust materials, gunfire, blast, burn and vent particles. |
| `Assets/Textures/cr06star.dds`, `cr06void.dds` | Starfield; 4x4 transparent black used to blank stock sky layers. |
| `Tools/CR06CapitalShips/` | Blender generators (`build_nsdf.py`, `build_cca.py`, `shipkit.py`, `texgen.py`) and `export_cr.py`, which re-exports a built ship under its CR name with native GEO/SDF. |
| `Tools/Test-Misn06OrbitLive.ps1` | Co-op harness scenario (see below). |

## How the shot works

- Runs on the authority only; guests keep the ground view. Everything is local and removed at the end.
- The fleet is staged 5 km above the launch pad. Far clip drops to 3 km, so terrain is culled and only
  the starfield sky box (`CR06/StarBox`, 0.2x far) and the ships draw.
- Anywhere no sky geometry draws, the viewport clear shows, and the engine repaints it in the TRN sky
  colour every frame (the brown band in early takes). The box closes every direction. If the box is
  refused, the fallback is the `CR06/Starfield` dome plus an upward-facing floor plane, which still
  leaves a band at the horizon. Sky geometry past about half the far clip is culled, so keep it close.
- Fog, ambient, sun direction and clip are re-asserted every frame; the Mars atmosphere director is paused.
- The stock sky is not an Ogre sky: `misn06.trn` `SkyTexture=mars.map` is a camera-relative ceiling quad,
  `[Clouds]` draws `acloud2.map` layers, and `SunTexture=sun.0` is a sprite. The engine binds materials
  named after the textures in upper case (`MARS.MAP`, `ACLOUD2.MAP`, `ACLOUD.MAP`), so the film retextures
  the ceiling to the starfield and the clouds to `cr06void.dds`, then restores each to its own name.
  `exu.MaterialExists` reports false for these materials, so the setter's result decides; `SUN.0` never
  resolves.
- Blast and burn particles use the additive `CR06/Exhaust`, which ignores alpha: their faders fade RGB.
  Stock `MakeExplosion` (`xbldxpl`) is used for the big hits only; its flat flash sprite is large.
- Ends on the VO climax (15.6 s) or a 24 s hard stop if audio is missing.

## Live test

Never on the live GOG folder: stage an isolated content folder with
`BZR_CAMPAIGN_RUNTIME_DIR=<folder> .\Manage-CampaignFiles.ps1 -deploy`, then

```
Run-BZRCoopMission.ps1 -Mission misn06 -CampaignContent <folder> -Clients 2 -MapListY 207 -MuteClients `
    -Scenario Tools\Test-Misn06OrbitLive.ps1 -RunName <name>
```

The scenario pulls the launch and Mayday timers forward, waits for the real vob4 cue to start the film,
checks every actor, takes shots at t=3/7/11/15/17 s, and checks that no ship, light or override survives.

Harness note: with the desktop idle or the user remote, game windows can take the foreground despite
`OPENSHIM_NEVER_ACTIVATE`; the foreground watchdog then posts `WM_CLOSE` after three steals and the lobby
step fails with "No visible window". Run with `BZR_NO_FOREGROUND_WATCHDOG=1` and no other game running.

## Open items

- Co-op guests do not see the shot.
- The CR carrier competing design (`crncarr`, CR #237) is separate and was archived out of the repository on 2026-10-21; this film uses `cr06lin` only.
