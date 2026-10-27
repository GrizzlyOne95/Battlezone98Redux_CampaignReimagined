# Palette-preserving world surface and atmosphere pass

Accepted by the owner on 2026-10-21. The reviewed textures are promoted by the
integration described in [WORLD_ART_PROMOTION.md](WORLD_ART_PROMOTION.md).
The candidate/build language below records the original review procedure.

This candidate retains each world's original visual identity while refining
material structure, scale, highlights and lighting. Original rusty Mars,
ochre Venus, volcanic red/yellow Io, blue Europa, amber Titan, warm brown/cream
Ganymede, green Achilles and gray Elysium remain recognizable. The Moon keeps
the separate Poly Haven regolith/crater candidate. This is a reviewable art
pass, not a replacement of every planet with a neutral scientific palette.

## Surface authoring

`Tools/TerrainHD/world_surface_art.json` supplies explicit settings for all nine
worlds. Edits happen on independent source D/N/S/E before rotations, variants
and transition masks. Existing paving, lava and base emissive placements remain.
No atlas pixels are used as source art. The original stock tile previews are
used only for visual palette comparison.

| World | Candidate change |
| --- | --- |
| Moon | Reuse the Poly Haven dust, fine normal/detail and varied authored craters. |
| Mars | Small saturation/contrast changes, softer fine sediment and restrained dry specular. |
| Venus | Keep ochre/sulphur identity with slightly quieter, more matte hardened crust. |
| Io | Darker cooled crust and a localized pale sulphur-frost coverage field; preserve hot-pool emission. |
| Europa | Retain cold blues/whites with less saturated facets and softer granular normals. |
| Titan | Mix smaller repeated worn Moon stones into the rock material, retaining Titan's original RGB balance. |
| Ganymede | Mix qualified fractured-ice sources into light/dark terrain, retaining warm brown/cream colouring. |
| Achilles | Retain lush greens; separate softer forest-floor/canopy response from harder rock. |
| Elysium | Retain gray desolation, soften fine deposits and keep exposed rock sharper. |

Replacement material D is anchored to the destination material's channel means,
so borrowing ice or cobble structure does not import another world's palette.
Normals blend in slope space, retain their already qualified engine convention
and renormalize. No new normal is inferred from colour. Source references/hashes
are recorded in each source report and changed references invalidate reuse.
All existing E channels remain untouched by this pass; the shared base accent
authoring then runs as before. New natural emission is not generated.

```powershell
python Tools/Build-WorldArtCandidates.py `
  --source-build '<saved independent HD recipe/cache>' `
  --toolbox ../Battlezone98_Modding_Toolbox-hd-terrain-authoring `
  --moon-bundle ../Campaign-Reimagined-moon-polyhaven/Local/TerrainHD/PolyHaven01/terrain/bundle `
  --output Local/WorldArt/Revision01
```

The wrapper builds the other eight packs through the existing Toolbox pipeline
and copies the selected Moon bundle. Two independent builds can run at once;
game trials remain serialized. Use a fresh output folder for each art change.
No generated DDS/source PNG is committed or installed into canonical shipping
art by this command. Each portable world bundle retains its current CR runtime
detail/depth values. Source files and stock-atlas fallback remain available.

Generate the original/previous/candidate palette comparison with:

```powershell
python Tools/Build-WorldArtReview.py --source-build '<saved HD recipe/cache>' `
  --candidate-root Local/WorldArt/Revision01
```

This reads original stock previews only for the comparison sheet; they do not
enter the texture-authoring pipeline. It also produces a live capture sheet
from completed entries in `live_review.json` when that evidence is available.
The flat diffuse comparison cannot qualify lighting or the rendered horizon.

## Lighting and smooth horizons

`Scripts/CRWorldArt.lua` contains each world's ambient, diffuse and specular
gains. These are modest scalar changes, preserving the authored light's RGB
balance instead of adding a replacement tint. Environment applies them after
weather composition and before its renderer writes. CRWeather applies the same
table only when it owns the standalone atmosphere path. There is still one
atmosphere writer; fog limits, day/night timing and sensor/gameplay effects are
unchanged. Unknown worlds retain their existing light.

`CRWorldArt.InitializeSky` supplies a dome using the original Mars, Venus,
Titan, Achilles or Elysium sky texture. TRNs remain unchanged. The dome smoothly blends
its lower edge toward the current fog colour, retaining the texture above its
editable elevation band. It renders first with depth testing and no depth writes,
preserving scene geometry and transparent effects. Missing EXU/materials or an existing authored Ogre
sky leave native rendering alone. Moon, Io, Europa
and Ganymede retain airless silhouettes. Elysium keeps its fictional purple
atmospheric palette. Mission 6 uses the same dome; its orbital film swaps the sky out and
`Environment.RestoreArtSky` reinstalls it afterwards (see `CR06_ORBIT_FILM.md`).

Mission 17's cloud deck renders behind scene effects, pins depth just inside the far plane and
fades into fog near the horizon. Its alpha approaches opaque fog at the low
edge. The director recognizes Environment's owned baseline sky, so it can add
storm clouds while preserving unrelated authored sky ownership. Weather domes
use an angular fade instead of depth-fogging the entire dome. Fog-disabled
space domes retain their original appearance.

`horizonBlend` in each `Materials/crart_<world>.material` controls lower/upper
elevation sine and strength (`w` is reserved). Cloud/dome defaults live in
their `.program` files. The dome reconstructs the world view direction from its
projected draw; generated face-local Y is not assumed to be world-up. Run
`Tools/Update-WorldSkyProgramVersions.py` after shader edits: Ogre caches bytecode
by program name, so source hashes version the delegates. SM4, SM3 and GLSL share
the contract. No OpenShim renderer fork is introduced.

The owned world-sky SM4 delegate also matches Enhanced's ambient haze colour:
`fogAmbient` (`0.35`, `0.16`) in its program controls the ambient contribution
in linear space before output encoding. Without this, fully fogged terrain was
lighter than the plain sky fog and retained a straight colour seam. The delegate
is separate from ordinary weather/space sky shaders. Its unlit specular pass
colour carries the runtime profile flag; `CRWorldArt.UpdateSky` switches that
flag when Enhanced/Redux/Retro changes. SM3/GLSL retain native fog colour.

## Review and validation

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File Tools/Test-WorldArtLive.ps1 `
  -OpenShimRepo ../BZR-OpenShim-terrain-world-controls `
  -CandidateRoot Local/WorldArt/Revision01
```

Each child uses the shared launch harness, a player-only terrain fixture and
the actual Environment/world-lighting code. It omits unrelated per-team vehicle
tint initialization. The fixture stages matching shader sources where resource
resolution can find them, uses explicit filesystem Lua search paths for long
module names, checks lighting initialization and owned shader errors, then
restores every staged file by hash. `-CloudDeck` tests the Mission 17 cloud
material on Achilles. This does not run the entire campaign weather director,
co-op mission logic or a complete mission lifecycle.

All nine bundles build and validate (44/72/52/76/64/52/76/88/80 DNSE resources).
The 140 non-Moon emissive DDS resources match their previous shipped inputs
byte-for-byte. No new texture dimensions/slots are added, and only the active
world's arrays are resident. Memory measurements must still come from the
32-bit game; summed pack sizes are not process RAM.
Four focused surface checks cover bounded palette changes, Ganymede hue
retention, unchanged E and normal-slope sign. Lighting and sky ownership pass 48
checks. Existing atmosphere integration passes 93 checks and Mission 17 jungle
logic passes 272. All nine HLSL sky vertex/fragment variants compile in
SM3/SM4; owned program references resolve. Live evidence and visual findings
are recorded as the per-world review completes.

The shipping lock adds only five sky materials and the lighting data module.
Existing sibling-supplied payloads were restored
to this worktree before blessing, retaining their manifest hashes and all
previous shipping members. This pass does not update native binaries, publish
Workshop content or claim Steam/Proton/Wine qualification.

Native sky material existence and a changed TRN value do not prove draw
selection: the native Mars scene reported no Ogre sky dome. A transparent
late dome also did not retain the original clouds behind it. Use the original
world texture on the owned dome and inspect a fresh capture. Earlier flat-fog
captures and those retaining the straight sky cutoff are rejected for horizon
qualification, even when their HD terrain/restoration checks pass.

The nine HD terrain/lighting checkpoints below have been visually inspected.
They use different maps and do not isolate this pass's RAM overhead. All retain
a largest free address-space block of approximately 2045 MiB in the 32-bit
process. The five atmospheric entries use the original sky art with ambient
haze matching, superseding the rejected cutoff/flat-fog revisions.

| World | Local TerrainHD evidence folder | Private MiB | Peak private MiB |
| --- | --- | ---: | ---: |
| Moon | run-20261020-214856 | 372.3 | 511.5 |
| Mars | run-20261020-222723 | 449.6 | 629.1 |
| Venus | run-20261020-223016 | 481.0 | 623.5 |
| Io | run-20261020-193107 | 483.6 | 614.5 |
| Europa | run-20261020-193200 | 483.1 | 642.8 |
| Titan | run-20261020-222630 | 501.6 | 655.7 |
| Ganymede | run-20261020-214522 | 478.2 | 669.9 |
| Achilles | run-20261020-222815 | 484.0 | 630.2 |
| Elysium | run-20261020-223143 | 482.2 | 616.6 |

The final separate world-sky delegate and all five material scripts load without
owned compiler/material errors in `run-20261020-223143` (Elysium). Earlier
calibration captures used the same opaque blend result via Ogre's default;
the unsupported `replace` keyword was then corrected to `one zero`, and the
harness now rejects these material errors explicitly. On Elysium, a former
sky/terrain step from `(72,63,72)` to `(78,70,78)` becomes `(78,70,78)` on both
sides of the measured join. Titan's former `(146,80,23)` to `(149,86,39)` step
likewise matches `(149,86,39)` on both sides after calibration.

`run-20261020-222756` validates a live Enhanced -> Redux -> Enhanced cycle:
the sky calibration switches at the effective profile transitions, OpenShim
restores the stock atlas, and HD arrays reinstall after Enhanced resumes.
This is a transition/restoration check; timing-based snapshot filenames are not
used for an isolated per-profile RAM comparison. All staged files restore.
The duplicate final cycle trial queued behind a separate benchmark was
cancelled before deployment; no game was stopped to make room.
