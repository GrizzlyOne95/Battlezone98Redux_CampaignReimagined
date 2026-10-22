# Faction nav beacons and powerups — art prototype

Owner request: four NSDF, Black Dog, CCA and CRA versions of `apcamr`, ammo,
repair and weapon pickups. The owner explicitly permits full atlas/UV changes.
This extends draft PR #288; no installed game or Workshop files are changed.

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
It is superseded. The revised pass:

- Uses dedicated plain faction metal on ordinary casing faces, at an object-
  scale projection. It never enlarges a corner of a framed badge as "plain" art.
- Uses at most one complete emblem panel per pickup. Its circular footprint
  must lie inside the actual mapped triangle union; a clipped fixture fails.
  Narrow bevels, rocket fins and unsuitable surfaces remain unmarked.
- Unpacks each pickup-type cell to a **separate 512px DDS before generating
  mips**. Referenced UVs remain inside that texture, avoiding neighbor-cell
  colors and frame fragments. Sixteen emblem maps and four plain finishes are
  shared across the twenty-four pickup models. No cross-cell sampler trick.
- Keeps stock type colors/details on untouched surfaces; repair's plain casing
  additionally has a green material tint. The tint does not recolor its badge.
- Uses flat body normals rather than mismatched relief. Changing UV orientation
  would require a matching tangent basis if a non-flat normal is added later.

Most pickups have up to three material batches (stock detail, emblem, plain),
versus one stock batch. Rocket fins have no badge batch. This needs native
performance/art review, not an unqualified fleet-wide performance claim.
Stock UVs often wrap above V=1; audit them modulo one when inspecting an atlas,
and preserve the original wrapped values on the detail remainder.

## Authoring, rebuild and evidence

Built-in ImageGen authored four beacon masters, four type-panel atlases and
one plain-finish palette. PNGs and full prompts are retained in
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

The targeted test currently passes 5241 contracts, including source/master
hashes, exact drawn geometry, native bytes, ODF behavior equality, UV bounds,
emblem footprint, all forty menu diffs and shipping membership. Existing art,
storage, repository and program-reference checks also pass. All five art
builders/binders reproduce 1132 asset hashes exactly. Offline isolated
Blender renders are art checks only; native GOG/Steam/Proton/Wine load, spinning
parts, pickup collection/rejection, menu behavior and performance remain unrun.
The new UV/material treatment still needs owner acceptance. Rejected renders
are not acceptance evidence. See `review/faction-navs.jpg` and the pickup sheets.
