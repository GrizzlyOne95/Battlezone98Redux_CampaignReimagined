# Moon dust and crater material candidate

The first crater height prototype displaced an unrelated rocky diffuse/normal
surface. This candidate replaces Moon's type-0 ground with quieter dust and
coherent crater bowls, worn rims and small overlapping impacts. The same authored
height controls geometry and the floor/rim colour differences. Existing rock,
paving, base emissives and their placement masks are retained; ground-to-rock
and paving transitions are regenerated from the independent source recipe.
No atlas pixels are used as image sources. Native map/collision files stay intact.

`Tools/TerrainHD/Moon/regolith.json` is the editable art recipe. Ground tiles
remain 1024px, the signed height lookup 1024px and the detail texture 2048px.
Maximum nominal depth remains 0.625 m (`microReliefScale: 2.5`). Ground normals
are linear RGB XYZ derived from an independent 4 mm dust microheight field,
with negative U/V gradients in the engine's audited tangent convention.
The normal map does **not** also contain the large crater slope: OpenShim's
domain shader already computes that from the displaced geometry. Encoding it
twice would exaggerate rim shading. The runtime normal is precompensated for
the current Enhanced shader's 2.1x normal sharpening. A separate reference PNG
shows macro crater normals for inspection; it is not bound as the pixel normal.

## Detail texture and generated detail normal

The earlier CR preview selected stock `mn_detail.dds`, rather than the quieter
HD addon detail. Its mean is near neutral but its contrast is high. Enhanced
SM4 samples the DetailMap at 8x and 32x and derives a normal from its luminance
central differences, using strength 2.2 and a 0.55 multiplier for the near layer.
There is no separate Moon detail-normal texture bound in this path.

The candidate authors a neutral grayscale periodic dust field for that same
slot. After BC1 compression its mean is 0.49944 and standard deviation 0.01862;
stock detail measures 0.50453 / 0.14567. At mip zero, the shader's single-layer
central-difference formula gives 95th-percentile normal tilt of 3.60 degrees
versus stock's 44.65 degrees (maximum 10.25 versus 70.47). These are input
texture diagnostics, **not** final combined world-space angles: filtering,
mips, both frequency layers, the main normal and terrain basis affect the draw.
The gradient sign agrees with the independently tested height-normal encoder.
There is no added texture slot or separate detail-normal allocation.

## Rebuild and preview

Requires NumPy, Pillow and SciPy plus the trusted local HD material cache and
the Toolbox checkout containing `battlezone/terrain/hd_tiles.py`. Source material
loading and transitions use the existing saved recipe; DDS, mip generation and
portable DNSE packaging use the shared Toolbox, not a new image codec.

```powershell
python Tools/Build-MoonRegolith.py `
  --source-build '<saved HD source build>' `
  --toolbox '../Battlezone98_Modding_Toolbox-hd-terrain-authoring' `
  --openshim '../BZR-OpenShim-moon-relief-depth' `
  --output Local/TerrainHD/Regolith01 `
  --compare-detail '<game>/BZ_ASSETS/pc/textures/TerrainTextures/Detail/mn_detail.dds'

./Tools/Test-MarsHdTerrainLive.ps1 `
  -OpenShimRepo ../BZR-OpenShim-moon-relief-depth `
  -TileDirectory Local/TerrainHD/Regolith01/bundle -World moon `
  -Hd -MicroRelief -GroundView -SettingsOnly -MeasureMemory `
  -DetailTexture Local/TerrainHD/Regolith01/bundle/resources/crhd_moon_regolith_detail.dds
```

Use a fresh output folder for each art revision. The builder writes retained
DNSE masters, a Toolbox bundle, signed R32 height, detail DDS, reference PNGs
and `regolith_report.json` under ignored `Local/`. Outputs are procedural and
reproducible; no AI-generated bitmap is used. The preview's `-DetailTexture`
temporarily changes the material alias and restores the original file/hash.
Source shipping DDS, shipping manifest and Workshop package are not promoted.
Off Enhanced, the existing stock-atlas fallback remains the production path;
this candidate does not introduce a new native rendering mode.

## Evidence and limits

Windows/GOG 2.2.301 DX11 PID 69036 used ordinary terrain settings without the
diagnostic tessellation flag. Capture:
`Local/TerrainHD/run-20261020-170308/trial.png`. The inspected image shows
smoother dust and distinct crater bowls/rims. Logs confirm the new 2048px detail
texture, signed R32 height texture and 0.625 m native displacement. All 1,478
height binding scopes, 144 streams/bounds, 82 native passes and 138 staged files
were restored. Four focused normal/morphology/determinism checks pass; the
Toolbox validates the DNSE mapping, formats and complete mip chains.

Median private commit was 363,896,832 bytes (347.04 MiB), lifetime peak
516,259,840 bytes (492.34 MiB), and largest free VA block 2,144,116,736 bytes
(2,044.79 MiB). This short run is not an isolated RAM-overhead A/B. The art
retains the existing slot count, sizes and formats; the detail replaces the
previous detail slot rather than adding a second texture.

This is a visual candidate, not a release. Crater repetition remains visible,
rock/dust distribution needs review across a wider map, and distant terrain
shading is unchanged. Device/profile transitions, long sessions and
Steam/Proton/Wine remain unverified for the new art. A later live game was left
running; no additional launch or shutdown was attempted against it.
