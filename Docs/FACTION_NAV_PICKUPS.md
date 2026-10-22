# Faction nav beacons and powerups — art-review checkpoint

Owner requests: independent NSDF, Black Dog, CCA and CRA nav/ammo/repair/weapon
assets; keep stock pod models; full atlas/UV edits permitted. Work is on draft
PR #288. No installed game, Workshop, mission or Lua files are changed.

## Current direction

The owner liked the new pod texture construction but rejected its olive NSDF
palette and identical blue/green glow wraps. The v4 pass compares each faction
against **two actual vehicles, a factory and a power building**, using their
resolved active D/E maps and hash-pinned sources, not guessed legacy filenames.
The owner then requested that direction on navs and weapon powerups as well.

| Faction | Body identity | New authored lamp identity |
|---|---|---|
| NSDF | Petrol blue-green / graphite, off-white tactical markings, white star | Paired ice-cyan rails / concentric nav rings |
| Black Dog | Blue-charcoal / crimson, off-white accents, dog-head badge | Red segmented slashes / ladder optics |
| CCA | Aged ivory, blue-grey steel insets, red markings / star | Orange optics, matching the owner's chaingun reference |
| CRA | Ochre-khaki/olive, warm charcoal, red markings / yellow star | Lime brackets/dots and grouped utility ticks |

The owner explicitly standardized decorative emission to cyan / red / orange /
lime by faction. Accepted NSDF ammo/repair cyan rails are actual E-map emitters,
not merely bright diffuse paint. Functional cores remain blue for ammo, green
for repair (service symbol and underside lens), and common amber for weapons.
Each weapon family maps one existing physical lamp group to that common core;
other lamps retain their distinct type-specific optics. These are new designs,
not a claim about exclusive stock faction hues. Stars, badges, metal and hazard paint
are nonemitting. No global RGB faction tint, new shader, point light or gameplay
effect is introduced. The owner requested **offline rendering only for now**.

The accepted v2 nav **paint** is superseded by this explicit new-pass request.
Its eight D/E maps remain historically byte-pinned under
`nav-weapons-v4/previous-nav-v2/`; the original acceptance record is unchanged.
Nav mesh/native/UV and material-block pins remain live invariants. Unique v2
hazard-pattern shapes persist: NSDF chevrons, Black Dog triple slashes, CCA
ladder bars, CRA sawtooth bands. Historical v3 NSDF pod masters are also retained
unchanged, not silently overwritten after the owner revised the palette.

## Resources and use

| Faction | Beacon | Ammo | Repair | Cannon / rocket / mortar / special |
|---|---|---|---|---|
| NSDF | crnvns | cramns | crhpns | crwcns / crwrns / crwmns / crwsns |
| Black Dog | crnvbd | crambd | crhpbd | crwcbd / crwrbd / crwmbd / crwsbd |
| CCA | crnvcc | cramcc | crhpcc | crwccc / crwrcc / crwmcc / crwscc |
| CRA | crnvcr | cramcr | crhpcr | crwccr / crwrcr / crwmcr / crwscr |

Each has independent mesh, VDF and skeleton filenames. Native VDF/skeleton
bytes remain stock and reference existing native geometry parts. Exact oriented
triangles, corner attributes, normals, weights and bounds remain unchanged.

Placeable ODFs prefix the **complete original ODF** with n (NSDF), b (Black Dog),
s (CCA) or c (CRA). Examples: napcamr / bapcamr / sspcamr / capcamr beacons,
napammo / bapammo / sspammo / cspammo appropriate ammo supplies. napmini keeps
NSDF gminigun; sspmini keeps Soviet gminisov. Longer-than-eight-character IDs
use deterministic short hashes. The 261-entry mapping is in
`References/TextureRevamp/nav-pickups/build.json`.

Forty faction recycler/armory ODF menus select these visual variants in existing
slots. Every other ODF field remains unchanged: costs, health/ammo quantities,
sounds, scan settings, AI labels, payloads and slot order. CCA ammo stays 700,
not NSDF's 500. The subsequent owner-authorized integration also updates existing
faction pickup ODFs: `spblst` selects `spcann`, `spcamr` selects `spcamr`, etc.
The prefix map is a / b / s / c for NSDF / Black Dog / CCA / CRA. There are 32
canonical render aliases (seven pickup families plus storage for each faction),
361 routed ODFs, and three new placeable ODFs: `bpcamr`, `sbstor`, `cbstor`.
Aliases share the reviewed textures and materials; they do not add atlases.
Original `abstor` / `bbstor` health remains 500 / 425 respectively. Exact original
ODF snapshots and the complete mapping are in `integration/manifest.json`;
only `baseName` changes. Existing generic/map/script references now resolve to
their faction's appearance, including nav render resources. No mission, Lua,
AI, camera behavior or automatic team-based replacement changes. CRA templates keep their own
source payloads rather than substituting NSDF definitions under a new skin.

## UV and material contracts

- **Navs:** stock UVs and one material batch. New palette/optics preserve hardware,
  centered badge, distinct hazard shapes and original two lamp locations.
  Emission is confined to those two circles, never the painted hazard bands.
- **Ammo/repair:** the selected complete v3 unwrap remains: all 126 ammo / 92
  repair triangles receive unique bounded UVs. Continuous concave perimeter
  wraps match U/V physical density; planar upper/underside and cone charts
  replace rejected per-facet emblem/vent stamps. No collapsed/overlapping UV
  triangles or stock-UV remainder. Shared `Tools/poduv.py` is used by runtime
  and historical NSDF prototype builders. One material plus 1024px D/E per pod.
- **Weapons:** guarded emblem placement and the existing triangle partition stay.
  At most one whole centered emblem fits a checked triangle footprint; fins and
  unsuitable panels stay unmarked. The majority original-UV remainder now has
  a shared faction `/detail` D/E instead of stock human art or four near-copies.
  Checked emblem panels use isolated 512px D/E; plain metal uses a quiet palette
  and explicitly black E. The child must not inherit a mismatched panel E map.
  Stock faces that magnified a tiny light blob across a whole tip/wedge instead
  receive physical planar charts on separate authored type-specific optics:
  cannon rails/vent bars/buttons, rocket paired vertical lamps, mortar circular
  gauge/status dots and special rim-service ports. These distinct patterns share
  one atlas; four existing special-top UV sectors keep its lamps visible rather
  than hiding them in the center recess. No new triangles or material batches.
  Projection preserves in-chart physical aspect; all other detail corner UVs
  remain byte-identical. No logos are mapped onto these narrow light faces.
  Warning swatches occupy four padded bands in the same detail atlas, one per
  weapon type. NSDF uses off-white/graphite chevrons, Black Dog crimson triple
  slashes, CCA red/ivory ladder bars and CRA red/ochre sawteeth. The cannon had
  no stock warning UVs, so one existing side casing gets its complete band;
  other cannon plain faces use quiet hatch metal in the same shared atlas.
  Ammo and repair reuse the authored warning pixels on separate continuous trim
  bands, preserving their front badge and lamps. Only warning paint intentionally
  repeats; whole body charts, logos and optical details are not tiled.
  No extra batches beyond the existing two/three; stock shapes are unchanged.
  The special's former skewed edge fragments are replaced by four physical
  outer-panel charts at one warning scale and common Y phase. Bevel/end caps
  remain quiet metal, not stretched pieces of neighboring strips.
- Flat body normals avoid mismatched relief after re-UVing. A later non-flat
  normal requires a matching tangent basis, not unmodified legacy tangents.
- Faction atlases and compact badge cells compile independently before mip
  generation. Internal weapon-type warning bands have padded UV bounds; their
  coarse mips converge to the same faction paint, never another faction's
  colours. Pod gutters use nearest covered texels. DDS use legacy BC1 headers
  and complete offline mip chains.
- The owner-requested atlas optimization retires eight unbound v2 utility maps,
  duplicate type-3 badge maps and the unoptimized draft's per-type detail copies.
  One 1024px detail D/E, one 512px badge D/E and one 512px quiet finish serve all
  four weapon types per faction. Pod/nav atlases stay independent and unchanged
  by consolidation. There are **44 maps / 23.3 MiB**, down from 84 / 42.0 MiB
  (44.4% fewer bytes), without reducing surviving map dimensions. Removal scope
  is explicitly recorded in the build receipt; unrelated shipping members/order
  are preserved. Retired source history is recoverable from Git/local backup.

## Masters, rebuild and evidence

Built-in ImageGen supplied the creative paint/light artwork; compilers only
unpack/reuse authored strips, resample, extract guarded lamp colours and compress.
They make no network/generation calls or procedural replacement paint.
References live under `References/TextureRevamp/`:

- `pod-palette-v4/`: current eight pod masters/prompts, actual D/E reference
  sheets and resolved source hashes. The v3 folder remains historical.
- `nav-weapons-v4/`: four nav, four compact badge, four compact shared detail masters
  and one quiet finish palette, full prompts and historical accepted nav maps.
  `prompts-hazards.json` / `hazard-repaint.json` record the subsequent built-in
  paint edit and exact guarded regions. The later `prompts-functional-glow.json`,
  `prompts-faction-color-correction.json`, `prompts-nav-glow.json` and
  `glow-repaint.json` record bounded ImageGen glass/core edits. Every pixel outside
  their saved masks remains exact, and those masks cannot touch hazard paint.
  Red decorative extraction additionally uses physical glass masks: hue alone
  would make Black Dog's red hull paint emit. Normalized pattern tests reject
  four copied warning swatches.
  A 2x2 stock-layout guide packs cannon/rocket/mortar/special in reading order;
  only its common top-left detail cell is retained per faction. Unused full
  generation sheets are archived in ignored Local, not duplicated in the current
  source folder. `master-repack.json` pins exact crops. A 1024px output is a compatibility
  resampling size, not a claim each packed cell has 1024 authored pixels.
- `nav-pickups/`: original source/native/ODF snapshots, menu routes and receipts.

```text
python Tools/Build-FactionNavPickups.py
python Tools/Build-FactionPickupIntegration.py
python Tools/Test-FactionNavPickups.py
python Tools/Test-FactionPickupIntegration.py
python Tools/Test-PodUVPrototype.py
```

Targeted tests cover source/master/current-output hashes, exact geometry/native
bytes, complete pod UV coverage, all-pairs prototype overlap plus a negative
fixture, actual palette/emission colour, unique lamp footprints, dark badge
regions, distinct same-faction pickup-type light silhouettes, full mips, every
ODF field, all forty menu routes, shipping membership and redundant-map retirement.
Both suites run in campaign CI. General texture/storage/repository/program
reference checks remain applicable. Source tests are not owner art acceptance.

Offline sheets under `References/TextureRevamp/review/`:

- `faction-pods-palette-v4-day.jpg` / `-glow.jpg` and `*-rear.jpg`.
- `faction-navs-v4-day.jpg` / `-glow.jpg`, both sides.
- `faction-weapons-v4-day.jpg` / `-glow.jpg`, all sixteen variants.

Day/dark views keep one material emission strength and reduce only scene
lighting. Isolated Blender processes and checked exits avoid the earlier cleanup
crash, but are **not** Ogre bloom, load/spinning/collection/rejection, menu or
performance evidence. Windows GOG/Steam and Proton/Wine runtime checks remain
unrun. Rejected v2 supplies/new-model prototypes are historical only.
