# Texture revamp and Olympian interiors

Owner request, 2026-10-21: work through the complete texture-candidate audit and
cover the available Olympian interiors using the existing local replacement
models. Canonical CR's untracked sources were copied read-only into the isolated
`agent/texture-revamp` workstream; they were not edited in place.

This is an art prototype for review, not a Workshop publication or a claim of
complete campaign/runtime qualification. The rejected Tartarus redraw is not
part of the deliverable.

## Coverage

| Finding | Implementation |
|---|---|
| Tartarus eye | Import the existing `ubtart` replacement and its original 256px `trld_d.dds` eye. Preserve that DDS byte-for-byte; both `trld00` and the fallback `ubtart00` select the eye, not Styx. No newly drawn iris or gold redesign. |
| Olympian interiors | Dedicated wall, floor, trim and display textures on all eight imported models with interior surfaces: `obstp1`–`3`, `oblema`, `obheph`, `obher100`–`300`. Existing energy details and glass retain their source materials. |
| Hephaestus/Hercules hull family | Import the owner-selected replacement geometry, native parts, rig and existing full material sets. Preserve exterior atlas layouts; deduplicate and mip-compress identical source textures. |
| Other Olympian relics | Keep the original diffuse identity of data/Cyclops/Lemnos pieces and power-device family; add shallow authored RGB normals. The power map is shared by `obcurt`, `obhavc`, `obmits`, `obmagc`, `obrfld`, `obtags`. Closed props do not gain invented rooms. |
| Achilles trunks | Higher-detail bark for both species with separate height-authored normals; quiet wood specular. Tree geometry, UVs, branch art, placement and collision are unchanged. |
| Pickups/salvage | One enhanced atlas shared by ammo/repair/rocket pickups (their original diffuse pixels are identical), plus the distinct salvage atlas. Colour coding and original atlas regions remain recognizable. Conservative panel-only normal fields do not emboss coloured stripes or lamp colours. |
| Mission 16 corrupted CCA | Approved diffuse DDS remain byte-identical. Add restrained authored normals and cyan-node emissive/specular companions selected by the actual Fury overlay, not the stock human lamp map. |
| NSDF storage | Conservative original-layout colour refinement plus shallow authored broad panel outlines. |
| Shared NSDF cockpit | Conservative original-layout colour refinement; retain the established stock normal/specular/emissive bindings. No cockpit geometry, animations or camera changes. |
| Large building expansion | Audit 49 active building models/materials. CCA launch-pad pilot dedicates texture space to its existing door, stairs and large plate; Black Dog pad pilot covers its painted ribbed panel. Other building art remains pending; see the ranked queue below. |

The accepted nine-world terrain stack, utility textures, newly authored Fury
mines/fighter and unrelated fleet art were explicitly excluded from the audit's
outdated-art candidates and remain untouched.

## Authoring and model contracts

- Built-in `image_gen` supplied the PNG colour and height masters. Full prompts
  live in `References/TextureRevamp/{prompts,map-prompts,power-prompt}.json`.
  ImageGen returned 1254px square masters, 887×1774 bark and a 2172×724 display;
  shipping sizes are format-conversion choices, not claims of additional native
  authored resolution.
  Building patch masters have their own dimensions and prompts in
  `building-prompts.json`: the door is 1016×1547, stair strip 760×2068 and plate
  1398×1125; Black Dog panel 971×1620. Their compiled sizes stay close to or
  below that authored budget. Original building input crops are retained under
  `building-sources/` beside the stock mesh baselines.
- The first Tartarus enhancement was rejected because it changed the surface
  shapes/brightness. It is retained only in ignored local scratch, never in the
  shipped files or tracked image masters. `trld_d.dds` keeps the original eye.
- Imported model provenance and source hashes are in `local-model-import.json`.
  The owner-authorized local import originated in their ISDF Chronicles relic
  packages. Native GEO/SDF/skeleton data is byte-pinned, including collision.
- Shared model codecs come through `Tools/bzmodellibs.py`; no private format
  parser is introduced. Only dedicated interior material names, UVs and their
  tangent/binormal basis change. Positions, normals, indices, weights and rig
  names are fingerprinted in `mesh-invariants.json`. Exterior UVs are unchanged.
- The initial atlas-range remap stretched the interior patterns in offline
  previews. Interior surfaces now use local meter-scale projections (4 m panels,
  2 m trim) and matching orthonormal tangents. Display layouts remain normalized.
  Model/skeleton scale can change their final game-world physical scale.
- Separate generated height fields are authored approximations, not recovered
  geometry. The compiler smooths high-frequency paint noise and limits slope
  strength; it never treats the diffuse image's general brightness as height.
  Inspect relief alignment and tiling in the actual renderer before acceptance.
- BC1/BC3 DDS use legacy headers and complete offline mip chains through the
  existing `Tools/bcdds.py`. Constant specular/utility fields stay tiny. The 73
  imported textures share 26 unique source resources; original duplicates are
  retained recoverably under ignored local scratch, not shipped repeatedly.
- Credits for 99.Miles's tree pack remain in `Docs/FOLIAGE_ART_CREDITS.md`.

## Rebuild and validation

```text
python Tools/Build-TextureRevamp.py
python Tools/Bind-TextureRevamp.py
python Tools/Build-BuildingTexturePatches.py
python Tools/Test-TextureRevamp.py
```

The build uses checked-in masters, with no generation/network calls. The forest
builder reapplies its six bark outputs using `--foliage-only`. Imported native
model files are the retained editable runtime sources, not regenerated by the
texture compiler. `Bind-TextureRevamp.py` is idempotent.

## Large building pilot and remaining queue

`Tools/Audit-BuildingTexelDensity.py` resolves the actual material diffuse alias,
not an inferred `*00.dds` name. `building-audit.json` records the 49-model stock
texture baseline with existing CR ModelFixes geometry where present. It does
not claim that the original stock art overrides CR's newer storage texture or
this pilot. Model-space density is an area-weighted UV estimate, including
repeated islands; it is not a world-meter or final screen-space measurement.
Skeleton scale, UV anisotropy, camera distance and tiny close-up islands matter.

| Queue | Active source atlas | Approx. texels/model unit | Status |
|---|---|---:|---|
| NSDF pad `ablpad` | 2048×1024 | 10.8 | Approach surfaces pending |
| CCA pad `sblpad` | 2048×1024 | 11.8 | Door/stairs/plate pilot built; remaining atlas pending |
| CCA supply `sbsupp` | 1024×1024 | 14.6 | Pending |
| Black Dog HQ `bbhqcp` | 1024×512 | 18.7 | Pending |
| NSDF hangar `abhang` | 1024×1024 | 20.5 | Pending; preserve existing animated ModelFixes |
| Black Dog pad `bblpad` | 4096×2048 | 21.5 | Painted ribbed-panel pilot built; other surfaces pending |
| CCA hangar `sbhang` | 1024×1024 | 25.1 | Pending |
| NSDF factory `abmbld` / comm `abcomm` | 1024×1024 | 26.5 / 28.0 | Pending |
| Remaining HQ/power/silo/support/tower families | See audit | Varies | Lower priority; review close-up doors, walkways and controls individually |

Black Dog silo's active atlas is **4096×2048**, not the inactive 256px legacy
`bbsilo00_d.dds`. Do not replace it on that false low-resolution premise.

The CCA source mesh is hash-pinned under `building-sources/`. Three disjoint UV
crops select **356 of 4973 existing triangles**. These move into three new
material batches: door 1024×1536 (formerly 180×274 atlas pixels), stairs 512×1408
(86×234), and plate 1280×1024 (328×264). No full-atlas upscale is shipped. The
remainder retains its original UVs and material. Positive affine crop mapping
preserves tangent orientation; these patches keep a flat normal rather than
inventing relief from diffuse brightness. The door has a matched lamp-only
emissive mask. Other surfaces retain the original source atlas and lamps.

The shared codec repartitions indices and clones render buffers, retaining all
drawn positions, normals, other attributes, weights, skeleton name, bounds and
triangle winding exactly. It adds three draw batches and about 3.3 MiB of mip-
compressed maps; the mesh grows from about 244 KiB to 887 KiB. Native collision,
SDF, skeleton, gameplay and source geometry are not edited. The source has no
precomputed edge lists; the builder fails if a future source needs edge-list
reconstruction rather than silently dropping that topology. New maps retain
BC1 legacy headers and complete mips. This tradeoff still needs native load,
animation/launch-state and performance review before accepting the technique
across every large building.

The Black Dog pilot follows the same guard on **88 of 5813 triangles**. Its
600×1000 atlas crop receives a dedicated 768×1280 map from the 971×1620 authored
patch: a modest local improvement, not an alleged whole-building 8K remaster.
It adds one batch and about 0.63 MiB of compressed diffuse data. Existing 4K
stock atlas, Black Dog insignia, lamps, remaining UVs and native files stay
unchanged. `bdog-pad-patch.json` and `bdog-building-build.json` record the crop,
exact triangle selection and hashes. The shared quiet patch specular is a tiny
utility; no native shader changes or new material-sampler support are required.

The first door draft shifted indicator layout. It was excluded; a corrected
conservative draft is used. Like the other art, this is reviewable authored
interpretation, not a pixel-exact restoration of every source diffuse detail.

The targeted test covers texture hashes, full mip chains, positive-Z RGB normals,
normal polarity ramps, preserved approved diffuse art, native data/rig hashes,
interior coverage, tangent/UV contracts, actual material aliases, original eye
selection and shipping membership. It runs in campaign CI.

Shipping admission: `-bless` refused removing 50 absent sibling-supplied payloads
in the fresh worktree. The documented in-place membership fallback adds only
owned resources, retaining every prior entry in its original order; it does not
drop or substitute native payloads. No `Bin` or installed-game files change.

### Evidence status

- Targeted host checks: 800 art/mesh/package checks, repository invariants,
  program references, Mission 16 scene contract, and 272 Mission 17 jungle
  checks passed. Python compilation and diff whitespace checks also passed.
- Offline Blender inspections: both pads' matched-camera before/after and relic model
  inspections test texture/UV presentation, not Ogre/Enhanced lighting, native
  collision or campaign behavior. A multi-model Blender process crashed on
  cleanup after eight successful renders; fresh one-model processes are used
  for the final evidence and their exits checked separately. Tartarus also
  crashed Blender's legacy DDS decoder; its lossless imported PNG is used only
  for the preview, leaving the runtime DDS unchanged. That retry exited cleanly.
  Automatic interior cameras can land on an exterior deck or a dark nook; the
  contact sheet is not a complete walk-through or art acceptance of every room.
  Review sheets are under `References/TextureRevamp/review/`.
- Native GOG DX11 preview: unrun; another game session occupied the machine.
- Windows Steam, Proton/Wine and full campaign/co-op lifecycles: unrun.
- Owner acceptance of the new art: pending. Tartarus's first redraw was rejected
  and replaced by the original eye-art path, as directed.
- Broad building-family implementation is not complete. The pilot and queue
  intentionally precede broad production hardening/qualification, per AGENTS.
