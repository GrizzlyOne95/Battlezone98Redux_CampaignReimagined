# Poly Haven Moon material trial

This opt-in candidate replaces the main regolith with photographed Poly Haven
material while retaining the varied 0.625 m crater geometry from the previous
Moon candidate. Existing rock outcrops, paving, base emissives and transition
masks remain. Canonical shipping assets and the previous HD candidate are
preserved. No shader changes, runtime dependency or extra texture slot is needed.

## Sources and conversion

- [Moon Meteor 02](https://polyhaven.com/a/moon_meteor_02): diffuse, DX normal,
  displacement and roughness, 2K PNG. Six repeats across a 20 m terrain tile
  give an effective 3.333 m scan width versus the source's listed 3.2 m. The
  small scale adjustment permits integer seamless repeats rather than stretching
  one scan across the entire tile.
- [Moon Dusted 01](https://polyhaven.com/a/moon_dusted_01): the same four maps.
  Fifty repeats across the terrain tile retain its approximately 0.4 m width.
  Prefiltering keeps these fine grains from aliasing when reduced to 1024px.
  Its displacement also supplies the 2048px DetailMap, with six repeats across
  the shader's 2.5 m detail period: effective scan width 0.417 m at the 8x layer.
  The existing 32x layer supplies finer grain; its normal scale remains tunable.

Both assets are [CC0](https://polyhaven.com/license), photographed from prepared
lunar-regolith surfaces at Spaceport Rostock's laboratory. They are not scans
captured on the Moon. Credits: Greg Zaal and Rico Cilliers (photography), Jenelle
van Heerden (Meteor processing and Dusted photography), Dario Barresi (Dusted
processing). `Tools/TerrainHD/Moon/polyhaven.json` pins all eight download URLs,
SHA-256 hashes, license and editable conversion values. Large source/runtime
images stay outside Git, under ignored `Local/TerrainHD`.

Normals are checked against each asset's independent displacement, never
inferred from diffuse. Both supplied DX maps already agree with negative image
U/V height gradients: Meteor correlations 0.912 / 0.925; Dusted 0.997 / 0.997.
No extra channel flip is applied. Inconclusive correlation fails the build.
Integer repeats use periodic prefiltering; normals are filtered in slope space,
renormalized and compensated for Enhanced's existing 2.1x sharpening.

Poly Haven displacement supplies fine-normal validation and the detail field.
The separate large authored craters supply geometry and its domain normal; their
slope is not duplicated in the pixel normal. The resulting fine impact pits
are normal detail, not individually tessellated holes or collision geometry.
Detail comes from height, with neutral mean 0.5 and target standard deviation
0.035; albedo lighting is not used as a height map.

The shader consumes legacy specular, not a metallic/roughness map. This trial
maps roughness to a low neutral specular range (10 to 34), using
`minimum + range * (1-roughness)^2`. This is a deliberately matte dielectric
approximation, not exact reproduction of Poly Haven's PBR material. Diffuse
retains photographed variation with an editable cool-neutral mean. AO is not
baked into diffuse. Natural regolith stays nonemissive; existing base accents
remain in their original source material.

## Build and adjust

Requires Python with NumPy, Pillow and SciPy, the saved independent HD source
recipe/cache, and the Toolbox checkout containing `battlezone/terrain/hd_tiles.py`.

```powershell
python Tools/Build-MoonPolyHaven.py --download `
  --source-build '<saved HD source build>' `
  --toolbox ../Battlezone98_Modding_Toolbox-hd-terrain-authoring `
  --openshim ../BZR-OpenShim-terrain-world-controls `
  --output Local/TerrainHD/PolyHaven01

powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File Tools/Test-MarsHdTerrainLive.ps1 `
  -OpenShimRepo ../BZR-OpenShim-terrain-world-controls `
  -TileDirectory Local/TerrainHD/PolyHaven01/terrain/bundle -World moon `
  -Hd -MicroRelief -GroundView -SettingsOnly -MeasureMemory `
  -DetailTexture Local/TerrainHD/PolyHaven01/terrain/bundle/resources/crhd_moon_regolith_detail.dds
```

The download switch only fetches missing hash-pinned files. Changed cached
sources are rejected, not overwritten. Use `--sources` to select an existing
source folder and `--settings` to select an edited conversion recipe. Always
choose a fresh output folder. Downloading is an authoring operation; the game
never accesses Poly Haven or requires their tools.

Adjust the main/floor material's `targetMean`, `normalStrength` and integer
`repeats` in `polyhaven.json`. `detail.heightContrast` adjusts the height-derived
grain. Crater shapes remain in `regolith.json`; per-world geometry depth and
detail contrast/normal strength remain in `Config/cr_terrain_hd.json`.
The wrapper uses the existing Moon builder and shared Toolbox DDS/mip packer.
Its ground/dust overrides are explicit; ordinary Moon builds retain their
previous source selection.

The bundle contains the same 44 DNSE resources (11 tiles, 1024px), a 1024px R32
height lookup and a 2048px BC1 detail texture. Off DX11 Enhanced, the existing
stock-atlas fallback remains. This candidate does not change map/collision files
or promote generated assets into the shipping manifest.

## Qualification

The initial `PolyHaven01` build passes source hashes, both independent normal
audits, local-mask preservation assertions against the selected Poly Haven
material, and Toolbox validation of all 44 DNSE resources/mips. Four focused
conversion checks cover per-axis normal polarity, inconclusive-source rejection,
periodic filtering/scale and matte specular conversion. Existing Moon checks
remain applicable. Detail input has mean 0.5000, standard deviation 0.03502 and
single-layer p95 normal tilt 5.24 degrees before runtime combination/filtering.
All 18 focused conversion/crater/material checks and CR repository invariants
pass. The signed height, rock-only tile and all emissive DDS resources match
the previous HD candidate byte-for-byte. DNSE output remains 69,212,077 bytes;
the new detail DDS has a complete 12-level chain (2,796,344 bytes, 16 bytes more
than the previous source's 10-level chain).

Live visual acceptance, 32-bit process memory and wider platform/lifecycle
qualification must be recorded from an actual trial. Matching dimensions and
texture slots do not establish measured process RAM overhead. Do not substitute
the earlier HD-rock candidate's screenshot or memory values for this surface.

The 2026-10-20 GOG attempt (`Local/TerrainHD/run-20261020-190311`) waited behind
another harness's active game sessions. It never reached deployment or launched
a game. Its queued preview shell was stopped before any game-file backups or
mutations, leaving those other games alone. No new in-game screenshot or process
memory measurement is claimed. Rerun the preview command when the harness is free.
