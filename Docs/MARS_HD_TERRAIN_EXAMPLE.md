# Mars HD source-tile example

This local prototype uses CR's `misn04` terrain with independent 1024-pixel
diffuse, normal and specular tile arrays in OpenShim's experimental v2 HD
terrain path. Map heights, tile choices, rotations and gameplay data remain
native. It needs the matching OpenShim development build; EXU is not required
by this terrain bench.

The artwork comes from **the source build behind `addon/stock_terrain_hd`**,
visual revision 6. `Build-MarsHdTileSources.py` runs that trusted local recipe
to the end of tile generation and substitutes a tile writer for its packing
stage. It reads cached, separate material channels and reuses the recipe's
normal corrections, variations and transition masks. No rendered atlas is
cropped or sampled to make these textures. The source addon/build is retained.

Mars uses BZCC `pluto7.tga` and `Metal2.tga`, plus UE Tank Game
`ChunkyMartianGravel_albedo.png`, `MarsGravel_albedo.png` and
`MartianBarrensRocky_albedo.png`, with their independent normal/reflectance
inputs. Original source provenance is preserved in `source_tiles.json`.
The legacy shader consumes specular intensity, so the recipe's documented
conversion from authored roughness/gloss is retained. Normal/specular maps
are not synthesized from diffuse.

## Export the source tiles

From CR, use Python with NumPy/Pillow and the original build's local
dependencies (including its Toolbox/masks/BC1 helpers):

```powershell
$source = 'C:\Program Files (x86)\GOG Galaxy\Games\Battlezone 98 Redux\output\stock_world_texture_survey_20261014'
$tiles = "$PWD\Local\TerrainHD\MarsSourceTiles"
python Tools/Build-MarsHdTileSources.py --source-build $source --output $tiles
python Tools/Test-MarsHdTileSources.py
python Tools/Test-MarsHdTileSources.py --export $tiles
```

Choose a new output directory. The exporter refuses to rebuild/download missing
source materials and fails if the saved generation/packing boundary changes.
This adapts that saved local build; it does not replace its source recipe.
The recipe is Python code: use only a trusted source build.

Output: 18 D/N/S/E tile sets with full DDS mip chains, a contact sheet, source
hashes and normal correction metadata. Normals use lossless RGB24 DDS and
renormalized mips; other maps use BC1. Mars emissive maps are intentionally
black and keep the native black binding. Generated art/provenance stays under
ignored `Local/`; these tools do not add it to the Workshop package or public
OpenShim repository.

## Bind and run on CR terrain

Native tile IDs are not CSV row numbers. First capture the running renderer's
table and channel identities. The helper stages CR's actual `misn04` terrain
companions and a simple camera Lua driver in the GOG addon root. It temporarily
selects `CRHD_MARS_EXAMPLE`, which imports CR's Enhanced terrain base, and uses
`native_layout.csv` exported from the source recipe's stock alias metadata.
It stages the selecting material and CR IBL wrappers in the enabled
`addon/stock_terrain_hd` resource directory (override with `-ResourceDirectory`
for another enabled mod). It deploys the complete OpenShim build and launches
through `BZRHarness`. It refuses another
active game, captures without activating the window, closes its own game
gracefully and restores changed files with hash checks.

Run in a fresh **Windows PowerShell 5.1** child process:

```powershell
$os = "$HOME\Documents\GIT\BZR-OpenShim-hd-terrain-example"
$harness = "$HOME\Documents\GIT\BZR-OpenShim"
powershell.exe -NoProfile -File Tools/Test-MarsHdTerrainLive.ps1 `
  -OpenShimRepo $os -HarnessRepo $harness -TileDirectory $tiles
```

The printed evidence folder under `Local/TerrainHD/run-*` contains `native.json`,
game logs, a screenshot and a restoration ledger. A successful baseline run
automatically binds the exported tiles to that native capture. Then run HD:

```powershell
powershell.exe -NoProfile -File Tools/Test-MarsHdTerrainLive.ps1 `
  -OpenShimRepo $os -HarnessRepo $harness -TileDirectory $tiles -Hd
```

Only CSV alias/rectangle metadata is used. Every used native ID must resolve
to a generated source alias or binding fails. `cr_mars_hd.json` guards the
exact diffuse/normal/specular resources from that capture and maps 256 native
IDs to 18 physical slices. The HD helper requires rasterized native terrain
with the exact arrays bound and material/stream restoration on exit.
For a different map/material, `--bind-existing --capture ... --atlas-csv ...`
can bind an already exported pack with the CSV that actually loaded. Keep the
guarded material/channel identities from that capture.

For a persistent private mod, place DDS files in its registered Ogre resource
directory, select the manifest with `[Terrain] TerrainHdManifest`, enable
`TerrainHdEnabled=1` and restart in DX11. The manifest path may be absolute;
DDS filenames are resource names. Recapture if material/CSV precedence changes.
Preserve filename case for future Proton/Wine qualification.

## Current acceptance

Source export/DDS checks pass: 72 ordinary 1024-pixel files with 11 mips each.
OpenShim's Win32 Release build, all 111 CTests and specialized PS4 ordinary,
shadow, PSSM v2 and IBL compilation pass. GOG DX11 PID 44572 rendered the pack on
CR `misn04` with the CR Enhanced/IBL base. All 320 meshes passed native UV parity;
82 material passes installed/restored. A visible native draw reported
`hdTiles=1 hdMaterialMask=3` and 12,172 pixel invocations. All 320 streams, three
arrays and 57 programs were restored/released; all 130 temporary files passed
restoration hashes. The screenshot was inspected at
`Local/TerrainHD/run-20261020-113113/trial.png`; the ready local pack is
`Local/TerrainHD/MarsHdSourceExample`.

Broader seams/rotations, art tuning, performance and Steam/Proton/Wine remain
unqualified. Authoring uses portable Python; this helper targets Windows/GOG.
No Workshop publication or shipping-lock change is part of the prototype.
