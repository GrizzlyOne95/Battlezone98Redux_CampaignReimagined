# Faction nav beacons and powerups — art prototype

Owner request: four NSDF, Black Dog, CCA and CRA versions of `apcamr`, ammo,
repair and weapon pickups. The owner explicitly permits full atlas/UV changes.
This extends draft PR #288; no installed game or Workshop files are changed.

Owner review update: v2 navs are accepted; v2 pods are **not**. A full-stock-
unwrap versus new-model NSDF comparison is under
`References/TextureRevamp/pod-uv-v3/README.md`. It does not change runtime assets
or shipping. Wait for direction before carrying either prototype across factions.

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
UVs; pickup casing panels are re-UV'd. Positions, normals, tangents, weights,
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

## UV correction after owner review

The first preview repeated framed badges per facet and clipped them on fins.
The owner then rejected the corrected but overly plain ammo/repair casings.
Both supply previews are superseded by the v2 mechanical casing pass:

- Uses dedicated plain faction metal on ordinary **weapon** casing faces, at
  object scale. Ammo and repair instead use separate authored mechanical
  utility panels with cooling ribs, fasteners and blue/green equipment trim.
  Supply UVs now include narrow broad panels that retained oversized stock
  stripes before. Every selected panel has an aspect-preserving planar unwrap.
- Uses at most one complete emblem panel per pickup. Its circular footprint
  must lie inside the actual mapped triangle union; a clipped fixture fails.
  Narrow bevels, rocket fins and unsuitable surfaces remain unmarked.
- Unpacks each pickup-type cell to a **separate 512px DDS before generating
  mips**. Referenced UVs remain inside that texture, avoiding neighbor-cell
  colors and frame fragments. Sixteen emblem maps, eight supply utility maps
  and four plain weapon finishes serve the twenty-four pickup models.
- Keeps stock details on untouched surfaces, including ammo's blue tip and
  repair's small coupling caps. Repair art uses ivory, graphite and green
  service trim, not a whole-casing green tint. One repair badge faces +Z so it
  is visible from the same front inspection view as the other supply badge.
- Uses flat body normals rather than mismatched relief. Changing UV orientation
  would require a matching tangent basis if a non-flat normal is added later.

Most pickups have up to three material batches (stock detail, emblem, plain),
versus one stock batch. Rocket fins have no badge batch. This needs native
performance/art review, not an unqualified fleet-wide performance claim.
Stock UVs often wrap above V=1; audit them modulo one when inspecting an atlas,
and preserve the original wrapped values on the detail remainder.

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
and four v2 ammo/repair panel atlases. PNGs and full prompts are retained in
`References/TextureRevamp/nav-pickups/`. Returned square masters are 1254px;
beacon DDS are 1024px, and isolated panel/finish cells are 512px. The compiler
performs only technical unpacking/compression and model/ODF transformation.
It does not make network or generation calls. All DDS use legacy BC1 headers
and complete offline mip chains. Painted emblems never contribute emission;
only the beacons' two existing lower lamps do.

```text
python Tools/Build-FactionNavPickups.py
python Tools/Test-FactionNavPickups.py
```

The targeted test passes 5305 contracts: source/master hashes, exact drawn
geometry, native bytes, ODF behavior equality, UV bounds,
emblem footprint, all forty menu diffs and shipping membership. Existing art,
storage, repository and program-reference checks also apply. The five
builders/binders reproduce 1140 asset hashes exactly. The eight
supply utility DDS add roughly 1.33 MiB; the existing material-batch limit is
unchanged. Offline isolated
Blender renders are art checks only; native GOG/Steam/Proton/Wine load, spinning
parts, pickup collection/rejection, menu behavior and performance remain unrun.
The new UV/material treatment still needs owner acceptance. Rejected renders
are not acceptance evidence. See `review/faction-navs-v2.jpg` (both sides) and
`review/faction-ammo-repair-v2.jpg`. Prompt sets are `nav-v2-prompts.json` and
`supply-v2-prompts.json`; selected masters are `nav_*_v2.png` and
`supply_*_v2.png`. Weapons still use their existing v1 artwork/UV treatment.
