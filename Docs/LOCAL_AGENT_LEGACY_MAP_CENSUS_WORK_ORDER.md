# Local Agent Work Order — Legacy Battlezone Map Preservation Census

## Goal

Finish the historical Battlezone map census needed to identify which classic **Instant Action** maps are still missing from **Battlezone 98 Redux**, then prepare a reliable preservation/port queue. Also track all nine historical **The Red Odyssey** IA maps as priority preservation targets and maintain a smaller, selective **Strategy** lane beginning with `Earth`.

This is a **census/reconciliation task first**, not a mass-port implementation task. Do not start converting hundreds of maps until the ledger is trustworthy.

## Repository / branch

Repository:

`https://github.com/GrizzlyOne95/Battlezone98Redux_CampaignReimagined`

Continue the existing branch:

`agent/legacy-map-preservation-census`

Current branch is documentation-only and is ahead of `main`. Do not mix this work into the separate archive-import draft PR/branch unless explicitly requested.

Primary working files:

- `Docs/INSTANT_ACTION_PORTING_BACKLOG.md`
- `Docs/LEGACY_MAP_PRESERVATION_CENSUS.md`
- `Docs/LEGACY_MAP_PRESERVATION_CENSUS_NOTES.md`
- `Docs/LEGACY_MAP_PRESERVATION_CENSUS_PROGRESS.md`

The old 42-entry backlog is superseded by the census but must remain preserved as a verified-missing seed rather than being discarded.

## Primary source catalogs

Use all of these; do not rely on only one catalog.

### Historical IA catalog

Ssuser historical IA listing:

`https://bzmaps.net/misc/ssuser/Ssuser%27s%20Instant%20Action%20Maps%20Listing.htm`

Important: the published page header states:

- 262 Battlezone maps
- 9 Red Odyssey maps
- 21 Battlezone 1.5 maps
- 9 mod/map packs containing 88 missions total

A previous manual pass appeared to count more normal-BZ rows. Re-parse/recount mechanically and explain the discrepancy rather than silently replacing the published number.

### Current Battlezone Map Room

Instant Action:

`https://bzmaps.net/missions.php?type=instant_action`

### BZScrap

Classic Instant Action:

`https://bzscrap.org/index?parent=Maps%2FBattlezone%2FInstant%20Action`

Classic Strategy:

`https://bzscrap.org/index?parent=Maps%2FBattlezone%2FStrategy`

### Redux Workshop

Battlezone 98 Redux Workshop:

`https://steamcommunity.com/app/301650/workshop/`

Workshop matching must account for renamed/remade ports. Exact title mismatch is **not** enough to declare a map missing.

## Google Drive source locations

### Active preservation intake folder

Folder title: `IA/MP Port to BZR`

Folder ID:

`1PCDaHIka3LElFzfX3K_fyFnH__ZR-SKb`

URL:

`https://drive.google.com/drive/folders/1PCDaHIka3LElFzfX3K_fyFnH__ZR-SKb`

It is under the broader `Battlezone Files` collection.

Known complete archives already visible here / in preserved Old Maps storage include:

- `Europa_Snipe.zip`
- `furyhell.zip`
- `machoman.zip`
- `payback.zip`
- `warzone.zip`
- `The Return of Eagle's Nest 1.zip`
- `Sweet Vengence.zip`
- `Rabthole 1.1.zip`
- `CCA Fun.zip`
- `Call2arm.zip`
- `Rescuethe5th%21.zip`

The active folder also has extracted/source folders such as:

- `CHONMOON`
- `Onslaught`
- `The Vulcan Chamber`
- `CCA Fun`
- `Zombie COD files`
- `Rescuethe5th%21`
- `Call2arm`

Treat ZIPs as preservation originals. Do not modify original archives in place.

### Historical readmes / minimaps

Folder title: `Map readmes & pics`

Folder ID:

`1LccYUro9D2231WZV0IvNDQHhj3KQc74L`

This contains provenance/reference material for a large number of classic maps. It includes `Alien Yard.txt` and many other old mission readmes. A readme/minimap is evidence of a historical release, **not** proof that the complete source archive has been recovered.

Examples found in this folder include:

`Alien Yard`, `Walker Arena`, `Recon Mars`, `Heartbreak Ridge`, `Base Raid`, `Ancients`, `Rock Baby`, `Scrap Pit`, `Ravine`, `Dunes`, `Lifeline`, `Strike at the Heart`, `Punishment`, `Bring it Home`, `Nasty Surprise`, `Grand Theft`, `Total Recall`, `Valkyrie`, `Moon v1.5`, `Warfield`, `Undiscovered`, `Rend`, `Rings`, `HiLo`, `Machoman`, `Mars Madness`, `Biometal Run v1.5`, `Tobruk v1.5`, `Scrap Yard`, `Vulcanic`, `The Pits`, `Vendetta`, `Wreckers`, `Outpost`, `Nemesis`, `Mtn. Maddness`, `Io`, `Par 3`, `Canyon Madness`, `Paranoia`, `Z Snowed In`, `Blast Chamber`, `Ice Ice Baby`, `Scrap Crater`, `Moon War`, `Death Cirlce`, `Hex Loader`, `Mags Cage`, `Low Visibility`, `Achilles Pie`, `Face of Death`, `Blockade`, `Aarmpits`, `Parp Parp`, `Martians`, `Foothills`, `Mag Arena`, `Victory Hill`, `Earth`, `Bommamid`, `Scouts & Rockets III`, `Nomad`, `Fury Hell`, `Death by Dawn`, `Warzone`, `Shooter`, `Tunguska`, `Downhill`, `Payback`, `Bridges`, `Z Heavy Metal`, `The Great Pyramid`, `Final Strike`, `Lunar Chaos`, `Rest & Relaxation`, `Run Away!`, `The Crucible`, `Though I Walk`, `Dueling Arena`, `Clash of Titans`, and `Dragon's Mouth`.

### Preserved 1.5 / Old Maps storage

Known folder:

`Battlezone Files/.../1.5/Old Maps`

Old Maps folder ID:

`1TQk394lX-2VpZ7N9MxyDRV1J26rIoMB6`

Parent `1.5` folder ID:

`1XPM75l0QzxyEHZXxraXikgbd_LxMWr3c`

There is at least one additional archived `Old Maps` folder with ID:

`1dUIDH04jiLmhCCPUc2BgR7Nl1BomoHLk`

Search both rather than assuming one is canonical.

## Explicit correction: Alien Yard

`Alien Yard` was missed by the original 42-map shortlist and must remain in the census.

Historical archive name:

`alyard13.zip`

Known provenance/readme exists in `Map readmes & pics` as `Alien Yard.txt`.

Current status should remain `Verified missing / Readme found` unless a Redux Workshop equivalent is positively identified or the complete source archive is recovered.

## The Red Odyssey priority list

Track all nine historical TRO IA releases explicitly and attempt to recover source bytes for each:

| Mission | Archive(s) |
|---|---|
| ABC Chinese Mission 2 | `abc_chin2.zip` |
| ABC Fortress of Fear | `abc_fort.zip` |
| ABC Quantum Leap | `abc_leap.zip` |
| Fresh Meat | `chmisn09.zip`, `RO_IA_chmisn09.zip` |
| Operation Flush Out | `chmisn10.zip`, `RO_IA_chmisn10.zip` |
| Phantoms | `phantoms.zip`, `RO_IA_phantoms.zip` |
| Recovery | `recovery.zip` |
| Red Tide | `red_tide.zip` |
| Warlords | `warlords.zip` |

Rules:

- Prefer original TRO releases over later TRO-to-BZ conversions when preserving TRO behavior.
- `ABC Chinese Mission 2` is a variant/modification of the TRO Chinese mission, so preserve that provenance.
- Keep alternate archive names when historically documented.
- Do not declare a TRO map missing from Redux until Workshop reconciliation is complete.

## Battlezone 1.5 lane

Ssuser's historical listing reports 21 individual Battlezone 1.5 IA maps. Add every one explicitly to the census with title, archive, author, source state, Workshop state, and notes.

Some currently known 1.5-related references in Drive include:

- `Moon v1.5`
- `Biometal Run v1.5`
- `Tobruk v1.5`
- `Asphodel, Gomek & Draconis v1.5`

Do not assume these four are the complete 21-row set; derive the authoritative list from the historical source.

## Existing Redux representations already known

Do not republish these blindly. Preserve provenance and verify current Workshop state:

- `Wreckers`
- `Blockade` -> `Blockade Redux Redux`
- `Scrap Fun`
- `Battle of Taurids`
- `Flying Solo` / `Flyn' Solo`
- Downhill CCA variant -> `Downhils (Faction Switch)`
- `Don't Tread On Me`
- `Though I Walk`
- `The Red Wolf Missions`
- `The Battle Zone`
- `The Relic`

## Historical packs

Track pack contents separately so individual rows are not accidentally double-counted or republished against an existing Redux pack.

- Great Pyramid Pack — 3 maps
- Get Arkin Sixpack — 6 maps
- Hard Soviets Map Pack — 5 maps
- Last of the Galilean — 11 SP missions plus MP content
- Unofficial Battlezone 2 Demo — 4 missions
- Red Wolf Missions — 8 plus secret mission
- Shrieking Eagles Level Pack — 8 maps
- Battlezone: Elite Corps — 10 CCA missions
- Omega Squadron Mission Pack — 18 NSDF/Black Dog + 8 Chinese + 6 bonus IA

## Known repair / archaeology cases

Do not discard these. Mark them `Repair candidate`, preserve the original defect in notes, and identify the smallest Redux-compatible repair.

- `Canyon of Blood` — historical custom ODF/baseName defect.
- `Battlezone Mech Commander II` — internal BZN terrain-name mismatch; repaired historical variant exists.
- `Defence 1` — broken AIP; corrected historical version exists.
- `IAKIv2` — missing/broken AIP and force-matching syntax issue.
- `Eye of the Needle`, `Oh Shit!!`, `Stolen LT` — wrong internal MP/Strategy mission typing prevents normal IA behavior.
- `Mars Canyons` — corrupt TRN in some copies.
- `Part 1: The Rescue` — missing-TRN/type/script-success problems in original variants.
- `Phase Two - The Take` — custom recycler/AIP mismatch and missing recycler ODF.
- `Princess Part 2: The Big Climb` — internal `EmptyMission` typing interferes with IA behavior.
- `Punishing the Red Cows` — AIP repair required.
- `The Crater` — missing MAT data in historical package; reconstructed copy exists.
- `Flak1`, `Flak2` — BZN filename problems; Flak2 also has a missing asset dependency.
- `Zen's MCanyons Fix` — preserve as Mars Canyons repair provenance, not a separate target by default.
- `Recovery (TRO to BZ Conversion)` — conversion/variant; original TRO Recovery has preservation priority.

## Selective Strategy lane

Do not attempt to port every Strategy map yet. Maintain a curated list.

First explicit candidate:

### Earth

Historical readme file:

`Earth.txt`

Drive file ID:

`1XyY3E2bnNyo7SiftjUHop-lvi_VBkF8b`

Original installation line:

`earth.bzn    earth.des    5 5    netveh.txt S Earth`

Author: `Cmdr Wayne`

The `S` entry is the historical Strategy registration. Treat this as a standalone Strategy Workshop port candidate unless source inspection reveals shared dependencies that justify grouping it.

## Required census columns

Every historical mission row should eventually have:

1. Canonical historical title
2. Alternate title(s)
3. Author
4. Game / era (`BZ 1.4`, `TRO`, `BZ 1.5`, etc.)
5. Mission type (`IA`, `Strategy`, pack member, conversion, variant)
6. Original archive filename(s)
7. Historical source URL/catalog
8. Drive/archive source state
9. Exact source file/folder location when found
10. Redux Workshop state
11. Existing Redux item/title/URL when represented
12. Census status
13. Known compatibility defect(s)
14. Dependencies/custom assets
15. Intended release form (`standalone`, `pack`, `variant only`, `do not duplicate`)
16. Port priority
17. Notes/provenance

## Workshop reconciliation rules

For every row:

1. Search exact historical title.
2. Search normalized title (punctuation/spelling removed).
3. Search archive basename where useful.
4. Search author name.
5. Search likely remake/Redux terms.
6. Compare description/screenshots/readme provenance before declaring equivalence.
7. Record the specific existing Workshop item when represented.
8. Only then set `Verified missing`.

Do not use Workshop title equality alone.

## Source-recovery rules

Search in this order:

1. Active `IA/MP Port to BZR` Drive folder.
2. Both known `Old Maps` archive folders.
3. `Map readmes & pics` for provenance / filenames / authors.
4. BZScrap IA / Strategy catalogs.
5. Current Map Room.
6. Historical mirrors / archive sites where necessary.

When an archive is found:

- Preserve the original bytes unchanged.
- Record filename, source location, byte size, SHA-256, and archive member count.
- Do not overwrite the original ZIP with a repaired copy.
- Put repaired/Redux files in a separate workspace.

## Battlezone-specific porting constraints

These matter later when a census item becomes a port task:

- Files ending in `.ODF` must be **8 characters or fewer**. Apply the same limit to files directly referenced by Lua or legacy engine data where required, including WAV/TRN/BZN-style engine-facing names.
- Lua target is **Lua 5.1 only**.
- No external Lua libraries such as `io`, `os`, or `debug` unless a custom DLL explicitly provides them.
- Do not use `goto` / labels.
- `ObjectiveObjects()` is engine-broken as an iterator; do not use it.
- `GetOdf()`, `GetPilotClass()`, `GetWeaponClass()`, `GetClassSig()`, and `GetBase()` can contain invisible trailing null characters; normalize before comparison.
- `DeleteObject()` immediately invalidates object properties other than handle/objective name.
- For multiple spawns around one point, prefer `GetPositionNear` so units are not stacked.
- Use `print` for single-player/offline debugging; `DisplayMessage` / `/Command` are multiplayer-only.

If code is eventually edited, comment each repair explaining what changed and why.

## Deliverables for this work order

Do all of the following before stopping:

1. Expand `Docs/LEGACY_MAP_PRESERVATION_CENSUS.md` so every historical IA row from the Ssuser source is explicitly represented.
2. Explicitly enumerate all 9 TRO and all 21 BZ 1.5 rows.
3. Reconcile each row against current Redux Workshop and classify `Workshop represented` vs `Verified missing` vs `Needs Workshop check` only when genuinely unresolved.
4. Reconcile source availability against Drive/BZScrap/Map Room and distinguish complete archive from readme/minimap-only evidence.
5. Keep historical repair/variant relationships instead of flattening them.
6. Produce a short numeric summary: total historical rows, represented in Redux, verified missing, archive found, source missing, repair candidates, duplicates/variants, unresolved.
7. Produce a **first port batch** made only from maps that are both `Verified missing` and `Archive found`, with TRO given high priority.
8. Update `Docs/LEGACY_MAP_PRESERVATION_CENSUS_PROGRESS.md` with what was completed and remaining uncertainty.

Do not mass-edit game content in this pass. Do not merge the branch. Stop with the docs in a reviewable state and report exact counts plus any unresolved identity/source ambiguities.