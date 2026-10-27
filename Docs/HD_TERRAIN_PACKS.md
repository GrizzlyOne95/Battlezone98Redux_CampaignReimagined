# Independent HD terrain packs

The nine stock planet families have independent 1K diffuse, RGB XYZ normal,
specular and emissive tiles built with the Modding Toolbox. Atlas image pixels
are not used as source art. Original materials, atlases and mission terrain
remain the fallback.

The owner accepted the nine-world surface/lighting/sky pass on 2026-10-21.
Its reviewed textures are now canonical; Moon additionally uses accepted Poly
Haven regolith, authored crater height and fine detail. See
[WORLD_ART_PROMOTION.md](WORLD_ART_PROMOTION.md) for the integration record.

## Adjusting geometric relief

Edit `Config/cr_terrain_hd.json`: each world material has a
`microReliefScale` near the start of its entry. Moon (`MN_DETAIL_ATLAS`) starts
at **2.5**; Mars, Venus, Io, Europa, Titan, Achilles, Ganymede and Elysium
start at **1.0**. Use the material table below to locate a world.

`1.0` is the original depth; `2.0` doubles it; `3.0` triples it; `0.0`
flattens geometric micro relief. Values must be within **0..4**. The normal
baseline is 0.25 meters, so Moon's 2.5 gives a 0.625-meter amplitude. Total
amplitude is capped at the existing one-meter displacement envelope even
with diagnostic baseline overrides. Pack rebuilding preserves these values.

Deploy the edited config and restart the game to see a change; texture
repainting, DDS regeneration and recompiling OpenShim are unnecessary.
Both **HD Terrain Tiles** and **Terrain Micro Detail** must be enabled with
DX11 Enhanced, and the selected pack must successfully load. The scale does
not enable either option. It scales the existing procedural geometric relief;
the D/N/S/E packs still do not supply texture-authored geometry height maps.
Collision and gameplay heights are unchanged. A live preview can opt in with
`Tools/Test-MarsHdTerrainLive.ps1 -MicroRelief` alongside the existing HD args.

An opt-in [Moon crater prototype](MOON_CRATER_DISPLACEMENT.md) now substitutes
an explicit height texture for that noise in a local preview bundle. Its recipe
and PNG authoring flow retain the same per-world depth control. The shipping
pack now includes the accepted crater height; it requires the normal HD tiles
and Terrain Micro Detail options to render that geometry.

Windows/GOG Moon trial (2026-10-20, PID 56724) confirmed factor 4,
`displacement=0.625`, matching bounds on 144 meshes, 243,200 domain shader
invocations and `hdMaterialMask=7` on a rasterized native draw. All 82 passes,
144 streams/bounds and 135 staged files were restored. The new wide-view
screenshot was inspected; local evidence is
`Local/TerrainHD/run-20261020-160941`. Other worlds' art scales remain at the
baseline; their live visual tuning and Steam/Proton/Wine remain unverified.

| World | Material | Physical tiles | DDS resources |
| --- | --- | ---: | ---: |
| Moon | MN_DETAIL_ATLAS | 11 | 44 |
| Mars | MA_DETAIL_ATLAS | 18 | 72 |
| Venus | VE_DETAIL_ATLAS | 13 | 52 |
| Io | IO_DETAIL_ATLAS | 19 | 76 |
| Europa | EU_DETAIL_ATLAS | 16 | 64 |
| Titan | TI_DETAIL_ATLAS | 13 | 52 |
| Achilles | AC_DETAIL_ATLAS | 19 | 76 |
| Ganymede | GA_DETAIL_ATLAS | 22 | 88 |
| Elysium | EL_DETAIL_ATLAS | 20 | 80 |

The table is the DDS form. Moon, Mars, Venus, Io, Europa, Titan and Achilles now
ship OpenShim paint bindings instead (`Tools/Merge-TerrainPaintPacks.py`, packs
from OpenShim `scripts/terrain-packs/build-world-packs.sh`), and their crhd tile
DDS files are retired; Ganymede and Elysium keep the DDS packs. Mars switched on
2026-10-25 (misn04-06, CR and stock maps).

Each material retains exact original D/N/S/E resource guards and CSV rectangles.
Only the active material's arrays are built. The nine packs do not imply nine
sets of arrays resident at once. The 32-bit process RAM cost is a live measured
quantity; file sizes and GPU array estimates are not process RAM estimates.

## Enable

Use the native HD development build from
[OpenShim #520](https://github.com/GrizzlyOne95/Battlezone98Redux_Shim/pull/520),
with the authored files installed by CR. In the game-root `openshim.ini`:

```ini
[Terrain]
TerrainHdEnabled=1
TerrainHdManifest=mods/3686673790/cr_terrain_hd.json
```

The path above is the normal GOG development layout. Use the actual registered
mod path or an explicit absolute manifest path on other installations. Restart
the game after changing the selection. Both the option and DX11 Enhanced are
required; Redux, Retro and HD disabled retain ordinary atlas rendering. This
work does not globally enable the option or publish a Workshop update.

## Edit and rebuild

`Tools/TerrainHD/<World>/authoring.json` is a portable Toolbox recipe using the
checked-in DDS resources as canonical inputs. The recipe, layout and sanitized
provenance can be moved with the assets. Rebuilding preserves canonical DDS
bytes, including every mip. The Toolbox owns image codecs, mip generation,
manifest authoring and bundle validation; CR owns the content recipe.

```powershell
$env:PYTHONPATH = '<Toolbox checkout with HD terrain tooling>'
python -m bztoolbox terrain hd-tiles build Tools/TerrainHD/Venus/authoring.json `
  --out Local/TerrainHD/VenusEdited
python -m bztoolbox terrain hd-tiles check Local/TerrainHD/VenusEdited
```

To regenerate independent PNG masters from the trusted saved source recipe
behind `addon/stock_terrain_hd` and build all worlds:

```powershell
$env:BZ_TOOLBOX_DIR = '<Toolbox checkout with HD terrain tooling>'
python Tools/Build-AllHdTerrain.py --source-build <saved-source-build> `
  --install-source-assets
```

`--worlds venus io` selects a subset. The shared builder also supports
`--world`, `--sources` and `--output`; existing source/output folders are reused
to preserve art edits. Use new folders when changing source policy. Source
generation never rebuilds or downloads missing material caches. It stops before
the saved recipe's atlas packing. `--install-source-assets` updates CR source,
merges material entries without deleting other packs, and never deploys the game.
New runtime membership must be reviewed through `Manage-CampaignFiles.ps1 -bless`.

The source caches and full editable PNG bundle remain ignored under
`Local/TerrainHD`. Normal/specular inputs remain independently supplied or
geometry-authored; diffuse brightness is not used as height or reflectance.

## Subtle base emissives

`Tools/TerrainHD/base_emissives.json` controls each world's base type, RGB
intensity and sparse UV rectangles. Coordinates are normalized source-material
UVs. These accents are authored before variants and transitions, so rotations,
paving footprints and blend masks carry them with the base material.

The default maximum is 32/255 in the authored sRGB emissive texture. Existing
base emissive sources are retained at 10% gain. Added strips occupy less than
0.5% of the source tile; most surfaces remain unlit. Achilles uses especially
small warm markers on its base/dirt surface. Natural ground is not given a
blanket glow. Io lava and other non-base emissives keep their source recipe.
The JSON is deterministic geometric mask authoring, not an albedo threshold.

Original `black.dds` guards are preserved where the ordinary material has no
emissive atlas. The native HD array replaces that guarded input only while the
HD material is active. No shader fork is required.

## Normal validation and limits

Keep the audited source Y conversion. Omit the saved recipe's empirical Moon,
Mars and Ganymede XY reversals that oppose authored heights. Europa's supplied
Snowy Rock 21 normal requires its own XY correction after Y conversion to agree
with its independent height. This correction is applied to the source before
variants and blends, and is recorded separately from historical overrides.

```powershell
python Tools/Validate-HdTerrainPacks.py --source-build <saved-source-build>
python Tools/Test-HdTerrainPacks.py
```

Each world's `pack_validation.json` records runtime DDS hashes, source-height
correlations where height exists, emitted normal-vector/mip checks, emissive
coverage and the analytical projected shader-basis test. Supplied materials
without an independent height reference remain explicitly unqualified for
absolute relief polarity. Nonpositive Z samples in supplied maps are inventoried
instead of silently reauthoring the material. Native binding/draw captures and
final lighting are separate evidence; no per-pixel GPU vector readback is claimed.

The earlier Moon/Mars/Venus reports and screenshots describe their recorded
pre-emissive trials. Their D/N/S source evidence remains useful, but their old
resource counts and memory values do not qualify a newly added E channel.

## Reversible previews

```powershell
powershell.exe -NoProfile -File Tools/Test-MarsHdTerrainLive.ps1 -World venus `
  -OpenShimRepo <OpenShim-HD-checkout> -HarnessRepo <OpenShim-harness-checkout> `
  -TileDirectory Local/TerrainHD/VenusHd1024 -Hd -WideView -BaseView -MeasureMemory
```

`-World` accepts all nine names. `-BaseView` uses an existing solid base area;
if the selected map has none, it paints a 5x5 base swatch in the temporary MAT
copy only. Source mission files and terrain heights are unchanged.
Omit `-BaseView` for the authored starting
position. Omit `-Hd` for the same camera's ordinary atlas RAM baseline, or use
`-RenderProfile Redux -Hd` for the profile gate. Every launch uses the shared
machine-wide harness lock, windowed mode and graceful owned-process shutdown.
Temporary files are restored and hash-checked.

Campaign worlds use temporary player-only copies of their CR mission terrains.
Ganymede and Elysium extract stock `evolve_3`/`evolve_1` companions with the
Toolbox ZFS reader into ignored evidence folders; game binaries/maps are not
committed. The selecting material and CSV are staged together into a registered
resource folder. Shader/IBL dependencies are made available there before CR
wrappers are parsed. These previews do not qualify campaign gameplay, co-op,
long-session RAM, Windows/Steam or Proton/Wine.

## Recorded live result

The updated Moon pack passed on Windows/GOG with all four HD channels active
(`hdMaterialMask=7`), 144 mesh streams and 82 material passes restored. The
short player-only fixture used **349.95 MiB settled private RAM**, peaked at
**481.99 MiB**, and retained a **2,044.79 MiB largest free VA block**. Every
temporary file was restored. See `Tools/TerrainHD/native_validation.json` and
ignored `Local/TerrainHD/run-20261020-145335/trial.png`.

The updated other eight packs have passed source/bundle/rebuild checks but
remain unverified in game. A separate benchmark retained the shared game lock;
the queued all-world preview was cancelled before deployment rather than
interrupting it. Their live RAM and stock-atlas deltas are therefore unmeasured.
The sequential preview helper above remains available for those checks.
