# Moon HD terrain

CR includes an opt-in 1K Moon terrain pack built with the Modding Toolbox's
`terrain hd-tiles` authoring workflow. It replaces diffuse, normal and specular
inputs for **MN_DETAIL_ATLAS**, used by `misn02b` and `misn03`. Native heights,
tile painting, rotations, missions and ordinary fallback atlases stay unchanged.

The 11 independent tiles have 33 runtime DDS resources with complete mip chains.
Normals use linear RGB XYZ, lossless RGB24 DDS. Diffuse/specular use opaque BC1.
Emissive remains the material's native `black.dds` binding. No EXU dependency is
introduced by the pack. Runtime support currently requires the OpenShim native
HD material pack development build ([#520](https://github.com/GrizzlyOne95/Battlezone98Redux_Shim/pull/520)).

## Enable

The managed CR deployment ships `Config/cr_terrain_hd.json` flat as
`cr_terrain_hd.json`, plus `Assets/Textures/crhd_moon_*.dds` flat as Ogre resources.
The matching stock-layout `mn_detail_atlas.csv` ships beside its selecting
material in the registered mod resource folder; a loose CSV in an unregistered
directory does not establish the engine's tile mapping.
Set OpenShim's manifest path to that deployed file and enable HD Terrain Tiles:

```ini
[Terrain]
TerrainHdEnabled=1
TerrainHdManifest=mods/3686673790/cr_terrain_hd.json
```

That relative path is the normal GOG development layout. On other layouts use
the actual installed mod path, or an absolute manifest path. Relative paths
resolve from the executable. This does not require modifying the mod's TRN or
material; exact guards already match the CR Moon material and its original
`moon_atlas_d/n/s.dds` resources.

Restart after changing the option or manifest. Effective DX11 Enhanced and the
authored pack/configuration are required. Disabling HD tiles or using Redux/
Retro retains the ordinary atlas. The source addition does not enable global
settings or replace anybody's existing manifest choice. Steam/Proton/Wine live
qualification remains separate from the Windows/GOG development preview.

## Rebuild or customize

The checked-in recipe uses the runtime DDS as portable input; larger editable
PNG masters and a full portable authoring bundle remain under ignored
`Local/TerrainHD/MoonHeightMatched1024` and `MoonBundle1024` on the author's machine.

With [Toolbox HD authoring](https://github.com/GrizzlyOne95/Battlezone98_Modding_Toolbox/pull/36)
installed, any checkout can rebuild an identical independent bundle:

```powershell
bztoolbox terrain hd-tiles build Tools/TerrainHD/Moon/authoring.json `
  --out Local/TerrainHD/MyMoonBundle
```

Edit the new bundle's `sources/` and recipe, then rebuild into another new
folder. For full generation from the saved independent HD source recipe:

```powershell
python Tools/Build-MoonHdTerrain.py --toolbox <Toolbox-checkout> `
  --source-build <stock_world_texture_survey_20261014> --install-source-assets
```

The CR adapter stops the trusted local recipe **before atlas packing** and
exports PNG images. The Toolbox performs discovery, DDS encoding, mip generation,
rectangle mapping and bundle validation. No atlas image pixels are read; no
materials are downloaded or rebuilt from missing caches. `--install-source-assets`
updates CR source only. Review changes and run `Manage-CampaignFiles.ps1 -bless`
before deployment. Source provenance and channel hashes are in
`Tools/TerrainHD/Moon/provenance.json`; private original paths are omitted.

## Normal validation and corrected polarity

The saved source recipe first flipped green for the game tangent convention,
then applied an empirical XY reversal to Moon ground and rock after an earlier
in-game concavity report. Independent source-height comparison now shows that
the second reversal inverted both slopes. The new Moon pack keeps the green
conversion and omits that later XY reversal. Original source caches, the
installed HD-atlas addon and the Mars prototype are not changed.

| Source | Evidence | Result |
| --- | --- | --- |
| StonyMoonGround | Supplied normal and independent authored height | Exported X/Y correlate +0.744/+0.744 with negative height gradients |
| LunarBarrens | Supplied normal and independent authored height | Exported X/Y correlate +0.836/+0.831 with negative height gradients |
| BZCC `pbintf02` paving | Supplied normal; mixed derivative/integrability check | Green flip supported; original relief polarity retained |

The old XY-reversed ground/rock exports have the opposite correlation signs.
Diffuse brightness, ambient occlusion and roughness are **not** used as height
evidence. Paving has no supplied independent height map, so its absolute relief
polarity is explicitly **unverified**, rather than claimed from integrability.

`Tools/Validate-MoonHdNormals.py` also checks:

- The actual Enhanced HLSL's RGB unpack, cross-product order and row-vector
  tangent transform. HD specialization must use local tile UVs for both normal
  sampling and basis derivatives.
- Twenty-four independently projected cases: three oblique cameras, four UV
  quarter turns and mirrored UVs. The mapped normal agrees with the geometric
  normal of displaced height (minimum cosine 0.9999999999999997).
- The saved recipe's four image/normal rotations against independently rotated
  analytic height, with p95 angular errors below 1.5 degrees.
- All 121 emitted normal mip levels: correct DDS payload, positive Z and unit
  vectors within RGB8 quantization (length 0.985..1.015).

The projection reference is Ogre's GPU-program right-handed path, including
`clip w=-view z`, from the
[upstream D3D11 implementation](https://github.com/OGRECave/ogre/blob/v1-9-0/RenderSystems/Direct3D11/src/OgreD3D11RenderSystem.cpp#L1473-L1523).
This is an analytical shader/data contract check; it does not replace live
draw-level qualification of the game's camera, bound resources and lighting.
Enhanced's slope sharpening and detail-map luminance relief still affect the
final lit normal. The source-height proof applies to the authored base normals.

Regenerate the checked-in numerical report:

```powershell
python Tools/Validate-MoonHdNormals.py --source-build <saved-source-build> `
  --images Local/TerrainHD/MoonHeightMatched1024 `
  --bundle Local/TerrainHD/MoonBundle1024 --openshim <OpenShim-checkout> `
  --toolbox <Toolbox-checkout> --out Tools/TerrainHD/Moon/normal_validation.json
```

## Preview and evidence

Run the existing serialized, reversible preview with the Moon bundle:

```powershell
powershell.exe -NoProfile -File Tools/Test-MarsHdTerrainLive.ps1 -World moon `
  -OpenShimRepo <OpenShim-HD-checkout> -HarnessRepo <OpenShim-harness-checkout> `
  -TileDirectory Local/TerrainHD/MoonBundle1024 -Hd -WideView -MeasureMemory
```

It uses CR's `misn03` terrain with a temporary player-only camera fixture, so a
command-line launch does not require campaign mission objects or the launch
rocket package. The fixture is written through the Toolbox BZN codec. Changed
GOG files are restored by hash and only the owned process is closed gracefully.
Evidence lives under ignored `Local/TerrainHD/run-*`; another running test is
left alone while the shared launch lock is held.

The pack is approximately 58.7 MiB on disk; estimated GPU array payload is
73.3 MiB. These values do not predict 32-bit process RAM. Live private/peak bytes
and free-VA measurements are a separate harness result.

Fresh Windows/GOG previews on OpenShim `4386558ee` confirmed native D/N/S draws
(`hdTiles=1`, `hdMaterialMask=3`, 24,931 pixel-shader invocations), all 144 native
meshes and 82 passes, and complete stream/material restoration. All 13 logical
Moon tile IDs resolve to the pack's 11 physical slices. Redux startup with the
HD option on allocated no arrays and retained the ordinary atlas.

| Same camera fixture | Settled private RAM | Peak private RAM | Largest free VA block |
| --- | ---: | ---: | ---: |
| Enhanced, ordinary atlas | 305.75 MiB | 399.34 MiB | 2,044.79 MiB |
| Enhanced, 1K Moon HD | 346.20 MiB | 484.11 MiB | 2,044.79 MiB |
| Redux, HD requested but inactive | 302.66 MiB | 393.86 MiB | 2,044.79 MiB |

The measured same-profile increase was approximately **40.45 MiB settled** and
**84.77 MiB at peak**, on this player-only map fixture. These short trials do
not establish a full co-op mission or long-session RAM budget. Evidence:
`run-20261020-141542` (HD, PID 37252), `run-20261020-141831` (atlas, PID 46264),
`run-20261020-141705` (Redux gate, PID 40168). Summarized hashes and run evidence
are in `Tools/TerrainHD/Moon/native_validation.json`; raw logs/screenshots stay
under ignored `Local/TerrainHD`. The source-height proof and native resource
draw proof complement each other; this is not per-pixel GPU normal readback.

The accepted corrected-normal screenshot is `run-20261020-141542/trial.png`.
`run-20261020-142102/trial.png` is the comparison control using the saved recipe's
old ground/rock XY reversal. Both packs have identical diffuse and specular DDS
bytes; only their normals differ. The control is not the shipped pack.

`Tools/Test-MoonHdTerrain.py` rebuilds the checked-in recipe through the shared
Toolbox, verifies all 33 DDS hashes and runtime mapping, checks material/mission
guards, regression-tests normal-basis cases and confirms shipping membership.
CI pins the Toolbox commit supplying that implementation. Runtime screenshots,
camera qualification and platform coverage must be reported separately.
