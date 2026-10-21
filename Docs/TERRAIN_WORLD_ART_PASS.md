# Palette-preserving world surface and atmosphere pass

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

## Lighting and smooth horizons

`Scripts/CRWorldArt.lua` contains each world's ambient, diffuse and specular
gains. These are modest scalar changes, preserving the authored light's RGB
balance instead of adding a replacement tint. Environment applies them after
weather composition and before its renderer writes. CRWeather applies the same
table only when it owns the standalone atmosphere path. There is still one
atmosphere writer; fog limits, day/night timing and sensor/gameplay effects are
unchanged. Unknown worlds retain their existing light.

Atmospheric CR maps now select short unique `CRSKYMA/VE/TI/AC.MAP` sky aliases,
preserving their original textures and native vertex palette. The new CR-owned
sky programs blend the low sky continuously toward the renderer's actual fog
colour, using a smooth elevation band. This avoids depending on conflicting
stock-named material overrides. Fourteen TRNs change only `SkyTexture`.
Airless-world skies retain their existing materials and sharp terrain silhouettes.
The horizon treatment does not add a generic atmosphere to every world.

Mission 17's cloud deck now pins depth just inside the far plane and fades into
fog near the horizon, using the pattern already present in Mission 18. Its alpha
approaches opaque fog at the low edge so the original sky cannot show through
as a contrasting stripe. Weather domes also use an angular horizon fade rather
than applying depth fog to the entire distant dome; fog-disabled space domes
retain their original appearance.

`horizonBlend` in `CR_skyhorizon.program` and `CR_skydome.program` controls the
lower/upper elevation sine and strength. Native skies start at 0.005 to 0.12
(approximately 0.3 to 6.9 degrees); cloud/dome defaults use 0.015 to 0.14.
Each `Materials/crart_<world>.material` overrides the upper limit separately:
Mars 0.15, Venus 0.20, Titan 0.22 and Achilles 0.14. These broaden the matching
band while retaining the original sky texture and colour above it.
SM4, SM3 and GLSL versions share the same contract. No OpenShim renderer fork
or extra sky texture is introduced.

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
retention, unchanged E and normal-slope sign. The lighting table passes 38
checks. Existing atmosphere integration passes 93 checks and Mission 17 jungle
logic passes 236. All 12 changed HLSL sky vertex/fragment variants compile in
SM3/SM4; owned program references resolve. Live evidence and visual findings
are recorded as the per-world review completes.

The shipping lock adds only four sky materials, five sky program/source files
and the lighting data module. Existing sibling-supplied payloads were restored
to this worktree before blessing, retaining their manifest hashes and all
previous shipping members. This pass does not update native binaries, publish
Workshop content or claim Steam/Proton/Wine qualification.
