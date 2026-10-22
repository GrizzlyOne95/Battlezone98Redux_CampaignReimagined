# New nav and weapon-pickup palette pass

The owner liked the reference-based v4 pods and explicitly requested the same
direction for nav beacons and faction weapon powerups. This supersedes **v2 nav
paint**, not its stock mesh/UVs or distinct hazard-marking patterns. Earlier
accepted maps remain in `previous-nav-v2/`, pinned by the original
`../nav-pickups/owner-selected-art.json`. Do not erase that acceptance history.
No deployment, game launch or publication accompanies this offline checkpoint.

## Inputs and outputs

- Current built-in ImageGen art: four `nav_*_v4.png`, four compact
  `badge_*_master.png`, four compact `weapon_*_master.png`, and `plain_v4.png`.
  Full prompts/input roles are in `prompts.json`; `master-repack.json` records
  base lossless crop coordinates and original/current hashes. Eight original full
  generation sheets are archived recoverably under ignored
  `Local/TextureRevamp/unoptimized-authoring-masters/`, not repeated in the
  current source folder. Existing v2 nav hazard shapes, plaques and lamp locations
  stay fixed; body/optics receive the new palette. No newly invented beacon
  model or animated/runtime point light is involved.
- Actual references are `../pod-palette-v4/*-actual-references.jpg` and the
  independently inspected `*-actual-emission.jpg` sheets. Those resolve two
  vehicles plus factory/power art for each faction, with source/hash metadata.
  The existing pod repaint supplies the matching art direction, not new fleet
  or building edits. See that folder's README for authored-vs-stock hue limits.
- NSDF: petrol blue-green/off-white, twin ice-cyan optics. Black Dog:
  blue-charcoal/crimson, segmented red lamps. CCA: ivory/blue-grey/red, orange
  rectangular optics. CRA: ochre-khaki/red, lime brackets and ticks.
  Insignia and hazard stripes are **paint**, not emitters.
- `weapon-stock-layout.png` is a technical 2x2 pack of four unchanged original
  UV snapshots: cannon, rocket, mortar, special in reading order. The four
  generation sheets kept those layouts. The owner then requested atlas
  optimization: only the top-left cannon-layout cell is retained in each compact
  weapon master and compiled into ONE
  shared `crwp??_d/e.dds` pair per faction. All four weapon families use its
  compatible machinery/hazard layout. Other cells remain ignored local history,
  not source/shipped copies. The sole badge master is the bottom-left panel cell;
  cannon/mortar/special reuse it. Rocket fins remain deliberately unbadged.
  Resulting 1024px DDS are compatibility/resampling choices; a packed master
  627px compact master is not claimed to contain 1024 authored pixels.
- Existing checked emblem panels are repainted to the actual palette, with
  unique inset lamp borders and a centered nonemitting insignia. The current
  complete-emblem/no-clipped-fin UV guard stays in place. Plain metal samples
  have no logos or lamps, avoiding repeated cropped insignia on narrow faces.

## Mesh/material and behavior contract

The 16 weapon meshes keep their existing triangle partition but now bind
the remainder to a namespaced `/detail` material; previously that majority
still selected shared stock human art. Every `/detail` shares its faction D/E,
the emblem batch uses isolated faction panel D/E, and `/plain` explicitly
selects black E rather than inheriting a mismatched lamp map. No added batches,
geometry, weights, bounds, native companions, collision or gameplay changes.
Offline low-light review exposed a stock-UV problem: tiny bright atlas swatches
were stretched across whole rocket tips and casing wedges. Those selected
faces now use physical planar charts on authored type-specific optics,
rather than magnifying a flat light blob. Chart aspect follows physical
geometry, with per-corner duplication preserving all skin/non-UV attributes.
All unselected detail corner UVs remain byte-identical; tests check both lanes.
Nav mesh/native/UV and material-block pins remain byte-identical.

Each weapon type has distinct optics **without another full atlas**: cannon
rails/vent bars/status buttons, rocket paired vertical lamps, mortar circular
gauge/status-dot module, and special rim-service ports. Four physical UV sectors
make the special's lamps visible on its existing rim; its center recess no
longer hides them. Per-type UV chart regions and normalized E-mask silhouettes
must differ. Ammo/repair retain separately authored full-atlas light arrangements,
with a same-faction type-difference regression check. No new model batches.

## Faction/type hazard pass

The owner's next request adds unique warning paint to every pickup family.
`prompts-hazards.json` records four further built-in ImageGen edits. Their raw
outputs stay in ignored Local; the final compact weapon masters contain only
three exact composited paint regions. `hazard-repaint.json` pins those regions,
raw/result hashes and untouched RGB hashes. Hardware, metal, lenses and other
pixels stay **byte-identical**, rather than accepting incidental image-edit drift.

The right column holds four padded weapon-type swatches: cannon / rocket /
mortar / special, top to bottom. Each is a variation on the faction nav style:
NSDF off-white/graphite chevrons, Black Dog crimson grouped triple slashes,
CCA red/ivory ladder bars, CRA red/ochre sawteeth. UVs select their own band,
never all four or the neighboring type. Cannon lacked a stock warning island;
one existing side casing gets its complete type-0 swatch. Other casing faces
use quiet shared-atlas metal. This adds no batch or texture. Ammo/repair reuse
the authored warning pixels on separate continuous trim bands, preserving the
badge and existing lights. Repeated **warning marks** are intentional; emblems,
body panels and light charts do not get repeated per facet. Every warning ROI
is explicitly masked out of E, even when paint colour passes a lamp hue test.

Creative work is ImageGen-authored. Technical operations are lossless cell/ROI
selection, authored warning-strip reuse, resampling, guarded lamp extraction
and BC1/mip compression;
no generation calls, procedural repaint or global RGB faction tint at runtime.
Nav E is confined to its original two circular lamp locations. Panel E excludes
the center insignia. Tests retain original ODF/menu/payload behavior, mip chains,
geometry/native/UV contracts and validate current-map receipts plus historical
accepted-map pins. The optimized set contains **44 maps / 24,472,992 bytes**,
versus the unoptimized draft's 84 / 44,052,064: 40 fewer maps and 44.4% less
texture data, with no downsizing of surviving maps. Forty-eight redundant maps
(32 draft detail copies, 8 duplicate type-3 badge maps, 8 old unused utility
maps) are retired and replaced by 8 shared detail maps. Unused full PNG authoring
history stays outside the repository/shipping set. Prior runtime files have a recoverable
ignored backup under `Local/TextureRevamp/retired-runtime-atlases/`; tracked
historical files also remain recoverable from Git. Shipping changes remove only
these named redundant maps and preserve all other members/order.

Review sheets: `../review/faction-navs-v4-*.jpg` and
`../review/faction-weapons-v4-*.jpg`, day/low light. Offline Blender rendering
cannot establish Ogre bloom, spinning/collection/rejection/menu behavior or
performance; Windows GOG/Steam and Proton/Wine runtime checks remain unrun.

The owner's final colour corrections are cyan NSDF / red Black Dog / orange
CCA / lime CRA. Functional blue ammo, green repair and amber weapon cores are
separate from decorative lights. NSDF's liked cyan pod rails are retained and
bound to E. `glow-repaint.json` plus `glow-masks/` record 18 bounded ImageGen
edits with exact unselected RGB hashes; the prompts are saved in the three
`prompts-*glow*` / `prompts-faction-color-correction.json` sets. Masks exclude
hazard paint and prevent red armour being mistaken for red lamp glass.

Special outer warning panels use equal physical scale and common vertical
phase, with unstriped bevels; old per-face warped fragments are removed.
Canonical model/ODF integration lives in `../integration/` and runs after the
art builder. It preserves all other gameplay settings and adds no textures.

Checkpoint validation: 5,932 pickup/resource/paint/UV/behavior assertions,
13,241 pod UV assertions, 808 general texture checks and 126 storage checks
pass, plus 2,100 integration assertions. Repository invariants cover 4,880 files;
1,109 owned program references resolve. Six builders reproduce all 1,244 asset
hashes exactly. All 28 model
variants have day/low-light offline evidence; current palette/hazard/glow still
requires owner visual acceptance, not inferred from passing source tests.
