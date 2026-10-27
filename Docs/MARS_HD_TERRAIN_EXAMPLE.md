# Mars HD source-tile example

This prototype renders CR `misn04` using independent diffuse, normal and specular
tiles. Map heights, tile choices, rotations and gameplay data stay native.
It needs the matching OpenShim development build and **DX11 Enhanced**. Redux
and Retro use the ordinary atlas; no HD arrays are allocated in those profiles.
The tile option and an authored pack are both required. EXU is not required
for the pack or its ordinary preview.

## One-command authoring and preview

From this CR worktree, in **Windows PowerShell 5.1**:

```powershell
$os = "$HOME\Documents\GIT\BZR-OpenShim-hd-terrain-example"
$harness = "$HOME\Documents\GIT\BZR-OpenShim"
powershell.exe -NoProfile -File Tools/New-MarsHdTerrainExample.ps1 `
  -OpenShimRepo $os -HarnessRepo $harness -TileSize 1024 -Preview -MeasureMemory
```

The command generates the pack, prepares its runtime mapping, validates its
DDS files and runs a reversible GOG preview. No capture/bind round trip or
hand-written native ID list is needed. Default output is ignored
`Local/TerrainHD/MarsHeightMatched1024`. Use `-OutputDirectory` for another location,
`-SourceBuild` for another saved recipe location, and `-TileSize 512/1024/2048`
for size. Changing size requires another output directory. Omit `-Preview`
to prepare art without launching the game.

Edit the independent `*_d.dds`, `*_n.dds` and `*_s.dds` images, keeping their
formats/dimensions and mip chains consistent within each channel. Rerunning
the command preserves existing art edits and refreshes only the runtime
manifest before validating/previewing. The contact sheet and `source_tiles.json`
record the generated source recipe/provenance. Generated artwork is not added
to the shipping lock or Workshop package.

Older packs without `normalPolarity: source-height-matched` are rejected when
rebinding: their chunky gravel still has the saved recipe's reversed relief.
Generate into a new `-OutputDirectory` to keep existing art edits intact.

The source is **the saved build behind `addon/stock_terrain_hd`**, visual
revision 6, normally at GOG `output/stock_world_texture_survey_20261014`.
Python needs NumPy/Pillow and that build's existing Toolbox/mask/BC1 helpers.
The saved recipe is executable Python: use a trusted local source build.
Missing cached materials are errors; the adapter never downloads/rebuilds them.

`Build-MarsHdTileSources.py` intercepts the recipe before packing, reusing its
independent source channels, normal corrections, palette and transition masks.
Generation runs at the requested tile size, including true 2K source/mask
sampling. No atlas image pixels are read. Mars uses BZCC `pluto7.tga` and
`Metal2.tga` plus UE Tank Game ChunkyMartianGravel, MarsGravel and
MartianBarrensRocky, with their independent normal/reflectance inputs. Specular
retains the recipe's conversion to the existing shader's intensity convention.
Normals/specular are not synthesized from diffuse. Output is 18 D/N/S/E sets:
BC1 color/specular/emissive, lossless RGB24 normals with renormalized mips.
The black Mars emissive maps retain the native black material binding.

Mars export retains the audited source green-channel conversion and omits the
later empirical XY reversal. Independent source height confirms the corrected
chunky-gravel slopes; its solid variants and all blends are regenerated from
that corrected source. Sand and mountain normal polarity remains unchanged.
Metal base and vent sources supply normals but no independent height map, so
their absolute relief polarity is not established by this check.

The 1K before/after check is recorded in
`Tools/TerrainHD/Mars/normal_validation.json`: chunky gravel changes from
approximately -0.669/-0.659 to +0.669/+0.659 correlation with the authored height
slopes. Exactly seven gravel solid/transition normal files change. All 54 D/S/E
files and the other 11 normals remain byte-identical against the same-resolution
control. All 198 normal mip levels pass the vector-length check. The report also
records 16 existing nonpositive-Z texels in unchanged metal/base-related maps;
this gravel correction does not reauthor those sources.

Recheck a generated pack with the independent source height files:

```powershell
python Tools/Validate-MarsHdNormals.py --source-build <saved-source-build> `
  --export Local/TerrainHD/MarsHeightMatched1024 `
  --out Local/TerrainHD/mars-normal-validation.json
```

Use `--baseline <matching-old-export>` to verify the seven-file-only change;
both packs must use the same source recipe and generation size. This checker
uses NumPy/Pillow/SciPy and the Toolbox selected by `BZ_TOOLBOX_DIR`.

The corrected live Windows/GOG capture is
`Local/TerrainHD/run-20261020-143222/trial.png` (PID 63044, OpenShim `4386558ee`).
It confirmed 18 slices, 320 native mesh streams, 82 passes and an actual D/N/S
draw (`hdMaterialMask=3`, 469,144 pixel-shader invocations). All streams, passes
and 131 temporary game files were restored. The captured OpenShim log SHA-256
is `451e8909d3884ddad75c7e6e367f9890a205cda224cf314df8a3b5c89b5be6be`.
This is separate native binding/draw evidence, not per-pixel normal readback;
Steam/Proton/Wine were not exercised by this trial.

## Runtime mapping and fallback

`cr_mars_hd.json` uses OpenShim v2 `tileRects`: source aliases map CSV rectangle
metadata to 18 physical slices. OpenShim compares those rectangles with the
running engine's native tile table. CSV row order is never treated as a native
ID. Unknown/ambiguous used rectangles fail closed. The selected material and
original diffuse/normal/specular resource names remain exact identity guards.
The example's controlled `CRHD_MARS_EXAMPLE` material makes those names known
without a capture. A different material still needs its own accurate guards.

The helper stages CR's actual `misn04` terrain companions, a small camera Lua,
`native_layout.csv`, the selecting material and CR IBL wrappers. Selecting
scripts go into the already enabled `addon/stock_terrain_hd` resource directory
(override with `-ResourceDirectory` for another enabled mod). An arbitrary new
addon subdirectory is not automatically parsed. DDS names are Ogre resource
names and must live in a registered resource directory.

The helper deploys the complete OpenShim load chain, launches windowed through
`BZRHarness`, refuses another running game, captures without activating the
window, closes only its owned game gracefully, and restores changed files by
hash. Evidence is printed under `Local/TerrainHD/run-*`: screenshot, native
capture, logs, memory report and restoration ledger.

For a persistent private pack, install DDS images in the mod's registered
resource directory and select the manifest:

```ini
[Terrain]
TerrainHdEnabled = 1
TerrainHdManifest = path/to/cr_mars_hd.json
```

Restart after changing the tile option. Effective DX11 Enhanced activates the
pack; leaving Enhanced restores the ordinary atlas and native streams, and
returning rearms native discovery. Filename case must be preserved for future
Proton/Wine qualification. Existing INI terrain keys override environment
variables, so the trial helper changes and restores the INI explicitly.

Diagnostic capture-based binding remains optional:
`Build-MarsHdTileSources.py --bind-existing --output <pack> --capture <native.json> --atlas-csv <loaded.csv>`.
This retains the captured material/channel guards and generates `sliceRemap`.
Do not guess another map's material resources from its planet name.

## 32-bit application RAM

Same mission, Enhanced profile, camera and factor-1 diagnostic draw path;
private commit is the process RAM budget, not GPU VRAM. Values are MiB, medians
of five post-load samples; peak private commit is the OS lifetime high-water
mark, including loading. The probe also records peak working set, occupied VA,
GPU counters and a full read-only 32-bit `VirtualQueryEx` scan.

| Configuration | Settled private RAM | Peak private RAM | Peak occupied VA | Settled free VA |
|---|---:|---:|---:|---:|
| Ordinary atlas | 353 | 430 | 1,068 | 3,040 |
| HD 1K D/N/S | 443 | 612 | 1,280 | 2,936 |
| HD 2K D/N/S | 442 | 883 | 1,546 | 2,910 |

The first HD implementation used about 527 MiB settled. GPU-default native
semantic buffers saved about **85 MiB**, leaving roughly **88–90 MiB** additional
settled private RAM (roughly 90 MiB in the final fresh A/B). The semantic
payload is still 80.4 MiB over 320 meshes;
it has no Ogre shadow buffer or persistent CPU mapping. Full terrain rebuilds
can upload it again through `UpdateSubresource`. Tile resolution affects the
loading peak much more than the settled process RAM. The 1K default has a
substantially smaller measured loading peak than 2K.

The tested x86 GOG executable is large-address-aware on 64-bit Windows; the
probe reads the PE flag rather than assuming a 2/4 GiB limit. The largest free
address block was about 2,045 MiB in all three fresh runs. Free VA includes
fragmented holes and does not predict the largest future allocation. These
short trials do not qualify complex co-op missions, long sessions or repeated
save/load. No binary flags or executable bytes were changed.

Evidence: local `run-20261020-132505` (atlas PID 13348),
`run-20261020-133006` (1K PID 61980), `run-20261020-133056` (2K PID 10228).
The optional `-ProfileCycle` test on `Test-MarsHdTerrainLive.ps1` uses the
installed EXU profile API only as a test driver (`-ExuDll` overrides its local
CR DLL path). Normal authoring does not acquire an EXU dependency.

Repeated profile changes initially accumulated about 90 MiB private commit per
HD reload. Using Ogre's native copy/release exports corrected retained handoffs.
The three-cycle regression (`run-20261020-131930`, PID 55196) returned to 359.9,
360.6 and 361.3 MiB in Redux; after the final HD resume it settled at 447.3 MiB.
Every retired native stream reported one binding-owned reference before removal,
with 320/320 streams and 82 passes restored per cycle. Run
`-ProfileCycle -ProfileCycles 3 -MeasureMemory` to repeat this integration test.
It is a short regression check, not a long-session leak proof.

## Validation and limits

The Win32 Release build and all 111 OpenShim CTests pass. Source adapter tests
cover the no-packing boundary, true 2K generation, native rectangle mapping,
no-capture manifest preparation and ambiguity rejection. Both real source
packs have 72 complete DDS files: 1K has 11 levels, 2K has 12. Specialized PS4
ordinary, shadow, PSSM v2 and IBL compilation passed in the initial prototype.

The 2K GPU-default-buffer run rendered exact diffuse/normal/specular arrays on
native terrain (`hdTiles=1 hdMaterialMask=3`), with UV parity on 320 meshes,
82 passes restored, 320 streams restored and 130 temporary files restored by
hash. Its screenshot was inspected. The original accepted 1K screenshot is
`Local/TerrainHD/run-20261020-113113/trial.png`.
The final startup-Redux trial (`run-20261020-133145`, PID 18404) retained the
atlas with no HD array/material allocation and restored all 130 staged files.

Broader seam/rotation art tuning, editor/rebuild lifecycle, campaign memory
stress and Steam/Proton/Wine remain unqualified. The authoring adapter uses
portable Python; the live/memory helper targets Windows/GOG. No Workshop
publication or shipping-lock change is part of the prototype.
