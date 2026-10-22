# Faction nav beacons and powerups — art prototype

Owner request: four NSDF, Black Dog, CCA and CRA versions of `apcamr`, ammo,
repair and weapon pickups. The owner explicitly permits full atlas/UV changes.
This extends draft PR #288; no installed game or Workshop files are changed.

Owner review update: v2 navs are accepted. The owner selected **stock pod
models with the new full-unwrap artwork**, rejected the new-model alternative,
and requested stock-style emissive/glowing parts. The selected unwrap now
serves ammo and repair pods in all four factions. The original selected NSDF
masters and accepted nav bytes/material blocks are pinned unchanged in
`References/TextureRevamp/nav-pickups/owner-selected-art.json`. New faction
paint and glow still need visual/native review; structural tests are not art
acceptance. The rejected shapes remain labelled historical render references,
not runtime assets. See `References/TextureRevamp/pod-uv-v3/README.md`.

## Resources and use

| Faction | Beacon model | Ammo model | Repair model | Cannon / rocket / mortar / special models |
|---|---|---|---|---|
| NSDF | crnvns | cramns | crhpns | crwcns / crwrns / crwmns / crwsns |
| Black Dog | crnvbd | crambd | crhpbd | crwcbd / crwrbd / crwmbd / crwsbd |
| CCA | crnvcc | cramcc | crhpcc | crwccc / crwrcc / crwmcc / crwscc |
| CRA | crnvcr | cramcr | crhpcr | crwccr / crwrcr / crwmcr / crwscr |

Each has its own mesh, VDF and skeleton filename. Native VDF/skeleton bytes
remain stock, referencing the same existing native geometry parts. These are
render/ODF variants, not remodels or new collision shapes. Beacons retain stock
UVs; ammo/repair get complete fresh UV charts and weapon casing panels are
re-UV'd. Positions, normals, tangents, weights,
oriented triangles, bounds and native moving parts are checked unchanged.

Placeable ODF names prefix the **complete original ODF** with `n` (NSDF), `b`
(Black Dog), `s` (CCA) or `c` (CRA). For example `napcamr`, `bapcamr`, `sspcamr`,
`capcamr` are beacons; `napammo`, `bapammo`, `sspammo`, `cspammo` are appropriate
ammo supplies. `napmini` keeps NSDF `gminigun`; `sspmini` keeps Soviet `gminisov`.
The complete 261-entry mapping is `nav-pickups/build.json` under References.
Names longer than eight characters use a deterministic short hash suffix.

Forty existing faction-owned recycler/armory ODF variants now select the new
assets in their existing build/weapon slots. Every other ODF setting, including
costs, ammo/health amounts, health, scan rate/range, weapon payloads, pickup
sounds, AI labels and slot order, remains unchanged. CCA ammo stays 700, not
NSDF's 500. The original ODFs and scripted/map-placed generic objects remain
available: no blanket mission/team-based object replacement or Lua hooks.
Camera fixtures, invisible anchors, decoys and other `apcamr` derivatives are
not automatically repainted. Alternate faction templates used by actual CRA
menus are retained instead of substituting an NSDF payload under a new skin.

## Selected stock-pod full unwrap and glow

The owner rejected per-facet badge stamping, plain casings and the later
vent-panel collage. All are superseded for ammo/repair by the selected v3:

- Every stock triangle (126 ammo, 92 repair) is remapped, with no collapsed or
  overlapping UV faces and no old-UV detail remainder. Shared `Tools/poduv.py`
  supplies both the runtime compiler and original NSDF prototype.
- Five ammo charts and three repair charts include continuous side wraps,
  planar upper/underside shells and the ammo cone. Perimeter distance, not
  repeated per-facet stamps, controls the concave side wrap; U/V side density
  matches physical distance.
- One material batch and one **1024px full diffuse atlas** per supply model.
  Nearest-covered-texel gutter extrusion precedes offline mip generation.
  Original selected NSDF paint stays untouched; Black Dog, CCA and CRA are
  guide-preserving ImageGen paint variants with their own insignia/finishes.
- Dedicated **1024px emission maps** restore blue/cyan ammo bands and tip plus
  green repair rails/tips/service marks. Faction badges and broad metal remain
  dark. A CCA repair correction explicitly keeps functional green separate
  from faction red. Glow maps derive from the authored lit-colour regions,
  constrained by chart coverage; no new native lights or gameplay hooks.
- Flat normals avoid mismatched relief; a later non-flat normal would require
  rebuilding tangents against the new UVs. Vertex/corner duplication changes
  UV storage only, not the exact drawn shapes, native VDFs or rigs.

Weapon pickups retain their prior v1 art/UV treatment: dedicated plain faction
metal and at most one checked complete emblem, no badges on rocket fins, and
separate 512px cells before mips. They can have up to three material batches;
their stock-detail remainder keeps its wrapped UVs. Eight superseded v2 supply
`*_surf.dds` remain in the shipping set but are no longer bound by materials;
this checkpoint does not mix a resource removal into the selected-art change.

## Unique nav hazard striping

The owner requested unique faction hazard markings after reviewing the navs.
The v2 atlases retain the same stock UV islands, body identity and two lamps:

| Faction | Hazard-band pattern |
|---|---|
| NSDF | Off-white/charcoal V chevrons with ochre edge lines |
| Black Dog | Crimson triple-slash groups on charcoal, thin ivory lines |
| CCA | Red/ivory horizontal ladder bars with a charcoal centerline |
| CRA | Yellow/olive angular sawtooth bands edged in red |

## Authoring, rebuild and evidence

Built-in ImageGen authored four initial beacon masters, four type-panel
atlases and one plain-finish palette, followed by four v2 hazard-band edits
and four v2 ammo/repair panel atlases. Selected full-pod art, six faction edits
and the CCA green-cue correction are under `References/TextureRevamp/pod-uv-v3/`;
earlier PNGs/prompts remain under `References/TextureRevamp/nav-pickups/`.
Returned square masters are 1254px; beacon/full-pod DDS are 1024px and weapon
panel/finish cells are 512px. The compiler
performs only technical unpacking/compression and model/ODF transformation.
It does not make network or generation calls. All DDS use legacy BC1 headers
and complete offline mip chains. Painted emblems never contribute emission;
beacons retain their two existing lower lamps and pods use the functional
blue/green lit areas described above.

```text
python Tools/Build-FactionNavPickups.py
python Tools/Test-FactionNavPickups.py
python Tools/Test-PodUVPrototype.py
```

The targeted test passes 5375 contracts: source/master hashes, exact drawn
geometry, native bytes, ODF behavior equality, UV bounds,
emblem footprint, all forty menu diffs and shipping membership. Existing art,
storage, repository and program-reference checks also apply. The five
builders/binders reproduce 1148 asset hashes exactly. The separate prototype
test passes 13241 checks including all-pairs UV intersection and a negative
overlap fixture. The new eight emission DDS add shipping membership without
removing/reordering earlier members (4225 total). Pod diffuse+emission maps
are about 10.67 MiB across all eight pods, before runtime driver overhead;
superseded maps remain on disk. Offline isolated
Blender renders are art checks only; native GOG/Steam/Proton/Wine load, spinning
parts, pickup collection/rejection, menu behavior and performance remain unrun.
See `review/faction-navs-v2.jpg` (accepted, both sides),
`review/faction-ammo-repair-stock-v3.jpg` (all four factions in daylight),
`review/faction-ammo-repair-glow-v3.jpg` (all four in low light), and their
`*-rear-v3.jpg` counterparts (opposite sides). The smaller
`review/pod-stock-glow-v3.jpg` pairs NSDF day/low-light inspection. Dark renders
use reduced Blender scene lights, not an engine bloom/performance claim.
Rejected v2 and new-geometry renders are historical only, not acceptance evidence.

Owner direction after this checkpoint is **offline rendering only for now**.
No game launch or installed-file changes were made for the all-faction review.
