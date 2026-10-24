# Red Devil legacy-guided skin and purpose-built cockpit

Owner request, 22 October 2026: use the legacy Red Devil's stronger red/black
identity, replace the unrelated default cockpit, align it to the real POV, and
avoid unintended open holes. This is an offline art-review prototype, not a
deployed or native-qualified release.

Branch `agent/red-devil-legacy` starts at `origin/main` e6123c9c. No open PR
overlapped these model/material resources. Building detail PR #305 remains
separate; the canonical checkout and its unrelated local work are untouched.

## Exterior

CR already overrode the diffuse with a 1256² repaint and the mesh with a
cockpit-weather-glass fix. These, not merely the stock Redux assets, are the
before baseline. Stock Redux diffuse is 2048²; the legacy `bvrdev00_d.dds` is
256² with different UV packing. The legacy image is a paint reference, never
rebound directly onto the new model.

Built-in ImageGen produced `reddevil-draft1.png`, then the selected
`reddevil-selected.png` (1254²): larger angular scarlet/crimson/charcoal blocks,
quieter panel centers, clearer existing insignia and restrained wear. This is
a legacy-inspired interpretation on the current UV layout, not a pixel-exact
restoration. `prompt.json` and `prompt-refinement.json` retain the full prompts
and input roles. The selected art compiles to the existing `bvrdev_d.dds` at
1280² (1,092,448 bytes versus 1,053,112 before). This is near-authored format
resampling, not a claim of 2K/4K new detail.

The original material, UVs, complete exterior mesh, cockpit-glass fallback and
all four Red Devil ODFs remain unchanged. Existing yellow/amber and cyan
exterior emissive bindings are retained, as are stock N/S. No painted red
armor becomes an emitter. Original diffuse alpha was uniformly opaque. All
existing variants using `bvrdev` share the new diffuse without gameplay edits.

## New cockpit

`Assets/Models/bvrdev_cockpit.mesh` uses the engine's separate-cockpit lookup,
ahead of the old in-mesh fallback. Its matching skeleton is a byte-identical
copy of stock `bvrdev.skeleton`, renamed only as a resource. The eye is the
captured **brd11POV** derived transform: `(0, 1.665995955, 1.229256034)`, identity
basis. Every new vertex is weighted 1.0 to the stable **brd21BDA**, handle 14.
The POV and every hardpoint/bone/native model record are unchanged.

The new shape has a raked, faceted canopy, low pointed sill, inward-facing side
controls, a low flight console and a view over **252 actual Red Devil foredeck
triangles**, with their original UVs, normals and tangents. The central aiming
corridor stays clear. This is not the old APC frame with another texture.

There are **609** interior/frame triangles and **252** foredeck triangles. The
weather glass is refitted to the new shell using the existing ray-grid fitting
algorithm (pure arrays only); all on-disk model I/O uses `bzmodellibs`. Its
1024 triangles follow the same cockpit bone and use `CRWX_CockpitGlass` with
the existing angular weather UV convention. The material remains a no-op
outside first-person weather use. Native weather-layer operation is unverified.

### No unintended open holes

Panels sit over a continuous inner tub, rear bulkhead and roof. The backing
shell has 36 triangles: position-welded edge checks require a manifold surface
with exactly one boundary loop / 14 boundary edges, the deliberate wraparound
canopy window. Floor, roof and rear-wall ray checks from the real POV reject
see-through seams. The beveled frame beams are closed volumes. Forward,
look-left/right/up/down, floor, side-seam and rear-bulkhead views were rendered
for inspection. These checks support this prototype, not a native claim for
every game FOV, damage state or weather lifecycle.

### Cockpit artwork and atlas

Built-in ImageGen supplied `cockpit-d.png` (1254²), using `cockpit-layout.png`
as a technical chart guide and the exterior repaint as its material reference.
The full prompt is in `prompt-cockpit.json`. `cockpit.json` records measured
source crop bounds and the exact 1024² runtime chart placements: frame,
console, side switches, red/black armor, quiet trim. These charts are technically
repacked to preserve UV registration; the builder does not draw instruments or
invent material detail. Frame UVs select the quiet central strip, avoiding
oversized repeated end decorations on thin struts.

One 1024² D/E pair uses full-mip legacy BC1. Cyan screen traces and selected
amber indicator glass emit; frame, armor, red toggle paint and quiet trim stay
dark. `cockpit-glass-mask.png` preserves the exact extraction footprint. Flat
normal and the already-shipped 4×4 quiet specular are reused; no diffuse-as-height
normal, duplicate N/S maps or new shader system. Both opaque materials derive
from `CR_BZBaseCockpit`; the foredeck reuses the exterior's existing D/N/S/E.

## Build and evidence

```text
python Tools/Build-RedDevilLegacy.py
python Tools/Build-RedDevilCockpit.py
python Tools/Test-RedDevilLegacy.py
python Tools/Test-RedDevilCockpit.py
```

`sources.json`, `original/`, `build.json` and `cockpit-build.json` retain exact
source/current hashes. No build performs image generation or network access.
The two new suites run in campaign CI. Current local checks: **37 exterior**
and **55 cockpit** contracts pass, including a misaligned-eye negative fixture;
the existing **808** general texture checks and **1197** program references pass.
All **9** asset/material/mask/receipt outputs reproduce byte-identically. The
original exterior model/material/ODFs remain pinned, with no gameplay changes.

Shipping adds exactly five resources: separate mesh/skeleton, one material
script, one D/E pair. The existing exterior DDS is replaced in place. `-bless`
refused 51 absent sibling-generated payload removals and left the lock alone;
the documented in-place membership fallback preserves every earlier member
and its order, adding only these five, **4426→4431**. Nothing in Bin, the GOG
install, Steam Workshop cache or the canonical worktree is modified.

Review files in `review/`: exterior before/after, side/top and dark comparisons;
`cockpit-before-after.jpg`, `cockpit-pov.png`, `cockpit-look-down.png`,
`cockpit-emissive.png` and seam-inspection evidence. Blender runs are isolated
one-model processes and exit cleanly. Views are matched at the captured POV
with 64° vertical FOV; instrument graphics are illustrative, not live telemetry.
Blender lighting is not Ogre/Enhanced lighting or bloom.

Owner art acceptance and native GOG/Steam/Proton/Wine loading, cockpit selection,
aiming/motion, weather, damage and performance checks remain pending/unrun.
No game launch, deployment, merge, release or Workshop publication is included.
