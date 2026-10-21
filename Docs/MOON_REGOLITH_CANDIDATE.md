# Moon dust and crater material candidate

The current revision preserves Moon's authored HD ground and detail texture,
with two distinct crater layouts, worn bowls, fresh rims and overlapping
impacts. Dust softens crater floors and sparse patches instead of replacing the
whole ground. Raised rims locally soften competing rock normals and brighten
the material slightly so the displaced shape reads against the busy HD surface.
The builder verifies byte-identical HD pixels outside these local masks before
DDS conversion and records the untouched fraction for both ground variants.
Existing rock, paving, base emissives and placement masks remain; transitions
are regenerated from the independent source recipe. No atlas pixels are used
as image sources. Native map/collision and canonical shipping art stay intact.

The first dust revision (`Regolith01`) replaced too much HD ground detail and
was rejected by the owner. Its live screenshot and metrics below are historical
evidence only. `Regolith03` is the corrected candidate with normalized source
references for comparing the exported normals.

`Tools/TerrainHD/Moon/regolith.json` is the editable art recipe. Ground tiles
remain 1024px, the signed height lookup 1024px and the detail texture 2048px.
Maximum nominal depth remains 0.625 m (`microReliefScale: 2.5`). Existing
source-height-validated HD RGB XYZ normals are preserved outside local dust/rim masks.
Within it, slope-space blending softens them toward an independent 4 mm dust
microheight normal with negative U/V gradients in the audited tangent convention.
The normal map does **not** also contain the new large crater slope: OpenShim's
domain shader already computes that from the displaced geometry. Encoding it
twice would exaggerate rim shading. Only the added dust normal is precompensated
for the current Enhanced shader's 2.1x normal sharpening; original HD normals
retain their existing calibration. A separate reference PNG
shows macro crater normals for inspection; it is not bound as the pixel normal.

## Detail texture and generated detail normal

The earlier CR preview selected stock `mn_detail.dds`, rather than the quieter
HD addon detail. Its mean is near neutral but its contrast is high. Enhanced
SM4 samples the DetailMap at 8x and 32x and derives a normal from its luminance
central differences, using strength 2.2 and a 0.55 multiplier for the near layer.
There is no separate Moon detail-normal texture bound in this path.

The current candidate copies the authored HD `ST_MOON_DETAIL.dds` byte-for-byte,
including its existing mip chain. It does not replace it with procedural grain
or flatten its contrast. `--detail-source` can select another reviewed HD detail;
the default reads the trusted saved source build's staged Moon detail. The report
records matching source/output SHA-256 and a luminance/gradient audit.

For context, rejected `Regolith01` used a generic dust detail with mean 0.49944,
standard deviation 0.01862 and mip-zero single-layer p95 tilt 3.60 degrees, versus
stock 0.50453 / 0.14567 / 44.65 degrees. Those figures do not describe the current
restored HD detail. Gradient audits are input-texture diagnostics, **not** final
combined world-space angles: filtering, mips, both frequency layers, the main
normal and terrain basis affect the draw. There is no new texture slot or
separate detail-normal allocation.

## Rebuild and preview

Requires NumPy, Pillow and SciPy plus the trusted local HD material cache and
the Toolbox checkout containing `battlezone/terrain/hd_tiles.py`. Source material
loading and transitions use the existing saved recipe; DDS, mip generation and
portable DNSE packaging use the shared Toolbox, not a new image codec.

```powershell
python Tools/Build-MoonRegolith.py `
  --source-build '<saved HD source build>' `
  --toolbox '../Battlezone98_Modding_Toolbox-hd-terrain-authoring' `
  --openshim '../BZR-OpenShim-terrain-world-controls' `
  --output Local/TerrainHD/CraterVariety02 `
  --compare-detail '<game>/BZ_ASSETS/pc/textures/TerrainTextures/Detail/mn_detail.dds'

./Tools/Test-MarsHdTerrainLive.ps1 `
  -OpenShimRepo ../BZR-OpenShim-terrain-world-controls `
  -TileDirectory Local/TerrainHD/CraterVariety02/bundle -World moon `
  -Hd -MicroRelief -GroundView -SettingsOnly -MeasureMemory `
  -DetailTexture Local/TerrainHD/CraterVariety02/bundle/resources/crhd_moon_regolith_detail.dds
```

Use a fresh output folder for each art revision. The builder writes retained
DNSE masters, original HD ground references, dust mask, a Toolbox bundle,
signed R32 height, copied HD detail DDS, reference PNGs and `regolith_report.json`
under ignored `Local/`. Procedural height/dust authoring augments the retained
HD art; no AI-generated bitmap is used. The preview's `-DetailTexture`
temporarily changes the material alias and restores the original file/hash.
Source shipping DDS, shipping manifest and Workshop package are not promoted.
Off Enhanced, the existing stock-atlas fallback remains the production path;
this candidate does not introduce a new native rendering mode.

## Crater variety controls

Edit `Tools/TerrainHD/Moon/regolith.json` and rebuild into a fresh output folder.
The main `craters` list authors ground A; `variants.MN00SC0.MAP.craters` authors
an independent ground C layout, rather than rotating A. Transitions retain their
source placement masks and flat paving/border guards. HD rock art still follows
the original source rotations; the independent height and local dust agree.

| Per-crater value | Effect |
| --- | --- |
| `center` | Tile UV position, `[0,1]` across the 20 m tile |
| `radiusMeters`, `depth` | Radius and fraction of the world displacement amplitude |
| `floorRadius` | Flat floor as a fraction of radius, 0 to 0.6; zero retains the older curved bowl |
| `rimHeight`, `rimWidth` | Rim height relative to crater depth (0 to 0.6) and width relative to radius (0.05 to 0.5) |
| `aspect`, `rotationDegrees` | Two axis multipliers (0.7 to 1.4) and orientation for elliptical bowls |
| `rimBreakup`, `phase` | Angular erosion strength (0 to 1) and pattern phase in radians |

The current layouts mix 0.8 to 3.4 m radii, broad worn bowls and sharper fresh
impacts. Overlapping heights add, clipped to signed unit range. Very small
impacts are poorly resolved by the existing factor-4 tessellation, so prefer
these meter-scale forms instead of adding submeter noise.

`rimNormalSoftening` controls local rock-normal suppression (currently 0.65);
`rimAlbedoGain` controls subtle rim material brightening (0.12). Neither bakes a
directional light. The original HD detail DDS is still copied byte-for-byte;
the large crater normal comes from geometry only. Overall depth remains
`microReliefScale` in `Config/cr_terrain_hd.json`, currently 2.5 / 0.625 m.

`CraterVariety01` ran in windowed Windows/GOG DX11 as PID 10464. Its inspected
capture, `Local/TerrainHD/run-20261020-184311/trial.png`, shows clearer bowls and
raised rims while preserving the HD rocky surface. All 18,433 height binding
scopes, 144 streams/bounds, 82 material passes and 146 staged files restored.
Private commit was 373.09 MiB, lifetime peak 504.04 MiB, largest free VA block
2,044.79 MiB. Texture dimensions, formats and slots are unchanged; this short
sample is not an isolated RAM-overhead comparison. `CraterVariety02` adds
per-variant source references and automatic preservation assertions without
changing the authored pixels. This remains a local candidate for art review.
Its preservation assertions pass for all D/N/S/E channels, with 78.88% of
ground A and 78.37% of ground C entirely outside the local crater/dust masks.
All 46 resource files match the live-trial bundle byte-for-byte. The 44 DNSE
files remain 69,212,077 bytes in total; height and detail reuse existing slots.
Fourteen focused crater/material checks and repository invariants pass.

## Earlier restored HD revision checks

Six focused checks cover UV normal sign/sharpening, no duplicated macro crater
normal, neutral-detail interpretation, deterministic dust, byte-identical HD
pixels at zero coverage and normalized full-dust normal blending. The current
output's original ground references and SHA-256 values make the retained HD
source reviewable. The Toolbox validates all 44 DNSE resources and mip chains.
`Regolith03/masters/mn00sa0_d.png` retains the inspected restored HD rocky surface.
Its crater-height output remains identical to revision 1; only the localized
surface blend and restored HD detail change.

The corrected candidate's Windows/GOG DX11 ordinary-settings trial ran as
PID 55824. Capture: `Local/TerrainHD/run-20261020-181604/trial.png`. Inspection
confirms the HD rocky surface is back; the busy rock shading still reduces
the bowls' visual clarity compared with the rejected smooth dust trial.
The logs confirm all four 1024px HD channel arrays, the restored authored HD
detail texture, signed R32 height and 0.625 m native displacement. All 1,488
height binding scopes, 144 streams/bounds, 82 native passes and 139 staged files
were restored, and the game exited normally.

Median private commit was 363,130,880 bytes (346.31 MiB), lifetime peak
515,043,328 bytes (491.18 MiB), largest free VA block 2,144,116,736 bytes
(2,044.79 MiB). This is a short-run observation, not an isolated overhead A/B.
This capture establishes the corrected art loaded; final visual acceptance
and wider lifecycle/platform qualification remain open. Do not substitute
the previous revision's screenshot or RAM sample for this candidate.

## Earlier rejected dust revision evidence

Windows/GOG 2.2.301 DX11 PID 69036 used ordinary terrain settings without the
diagnostic tessellation flag. Capture:
`Local/TerrainHD/run-20261020-170308/trial.png`. The inspected image shows
smoother dust and distinct crater bowls/rims. Logs confirm the new 2048px detail
texture, signed R32 height texture and 0.625 m native displacement. All 1,478
height binding scopes, 144 streams/bounds, 82 native passes and 138 staged files
were restored. The owner subsequently rejected the loss of the HD rocky surface.

Median private commit was 363,896,832 bytes (347.04 MiB), lifetime peak
516,259,840 bytes (492.34 MiB), and largest free VA block 2,144,116,736 bytes
(2,044.79 MiB). This short run is not an isolated RAM-overhead A/B. The art
retains the existing slot count, sizes and formats; the detail replaces the
previous detail slot rather than adding a second texture.

This is a visual candidate, not a release. Tiling can still be visible,
rock/dust distribution needs review across a wider map, and distant terrain
shading is unchanged. Device/profile transitions, long sessions and
Steam/Proton/Wine remain unverified for the new art.
