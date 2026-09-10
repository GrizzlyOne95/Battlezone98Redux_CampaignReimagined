# Legacy Map Preservation / Porting Backlog

This document is the working plan for recovering classic Battlezone maps and making them playable in **Battlezone 98 Redux**.

> **Release policy:** ports are **standalone Workshop maps by default**. Campaign Reimagined is being used as a preservation/research workspace and compatibility reference; a map does **not** need to ship inside CR. Historically coherent multi-mission packs may remain packs where that preserves the original release structure better.

The old 42-map backlog was intentionally conservative and is now superseded by the full census in [`LEGACY_MAP_PRESERVATION_CENSUS.md`](LEGACY_MAP_PRESERVATION_CENSUS.md).

## Source universe

The census reconciles these sources:

- Ssuser's historical Instant Action listing: https://bzmaps.net/misc/ssuser/Ssuser%27s%20Instant%20Action%20Maps%20Listing.htm
- Current Battlezone Map Room IA catalog: https://bzmaps.net/missions.php?type=instant_action
- BZScrap Instant Action archive: https://bzscrap.org/index?parent=Maps%2FBattlezone%2FInstant%20Action
- BZScrap Strategy archive: https://bzscrap.org/index?parent=Maps%2FBattlezone%2FStrategy
- Battlezone 98 Redux Steam Workshop: https://steamcommunity.com/app/301650/workshop/
- Preserved archives/readmes in the project owner's Google Drive collections.

The historical listing's header says **262 Battlezone maps**, but its current normal-Battlezone table contains **281 enumerated IA entries** when counted row by row. The census therefore tracks the actual entries rather than trusting the stale header total. It separately tracks **9 Red Odyssey IA releases**, **21 Battlezone 1.5 IA releases**, and historical multi-map packs.

## Preservation policy

The goal is **port by default, exclude by exception**. A low-rated or primitive map can still be historically valuable because it may preserve an old terrain, ODF trick, custom world, unusual scripting method, author history, or other piece of Battlezone modding culture.

Do not create a new standalone Redux item when the historical release is already represented faithfully on Workshop. Keep the old entry in the census and point it at the existing Redux counterpart instead.

For alternate versions, bug-fix releases, conversions, and near-duplicates, preserve the source history but choose the best release form for Redux. Prefer a single corrected standalone item with provenance for all versions when multiple releases are effectively the same mission.

## Status legend

- **Verified missing** — no Redux counterpart was identified in the latest reconciliation; active port candidate.
- **Needs Workshop check** — historical release catalogued, but exact/renamed Workshop reconciliation is still pending.
- **Workshop represented** — a Redux counterpart is already known; do not duplicate it without a specific reason.
- **Repair candidate** — historically documented defect or compatibility problem should be repaired during the port.
- **Duplicate / variant** — preserve provenance, but it may not warrant a separate Workshop item.
- **Missing source** — historical release known, but a usable source archive has not yet been located.
- **Porting** — Redux conversion is in progress.
- **Playable** — boots and can be completed, but qualification remains.
- **Qualified** — clean-install Redux qualification completed and ready for publication.
- **Blocked** — unresolved dependency, provenance, asset, or engine issue prevents completion.

## Release model

For a normal IA port, the preferred final shape is:

```text
Original archive (preserved unchanged)
        |
        +-- provenance / hashes / original readme
        |
        `-- Redux conversion workspace
                  |
                  `-- standalone Workshop item
```

A standalone map should not require Campaign Reimagined merely because CR was used during recovery. Use OpenShim/EXU/CR helpers only where they solve a real Redux incompatibility; document such a dependency explicitly. Avoid gratuitously redesigning the original mission.

For historical campaigns or tightly coupled packs, preserve the authored grouping when individual publication would damage progression, shared assets, or narrative continuity.

## Highest-priority lane — The Red Odyssey IA preservation

All nine historical TRO IA releases are priority preservation targets. These should receive an explicit Workshop re-check immediately before publication, but the intent is to recover and port all of them rather than wait for selective demand.

| # | Mission | Historical archive(s) | Status | Notes |
|---:|---|---|---|---|
| 1 | ABC Chinese Mission 2 | `abc_chin2.zip` | Needs Workshop check | TRO Chinese Mission 2 variant/modification; preserve as a variant rather than misrepresenting it as wholly original. |
| 2 | ABC Fortress of Fear | `abc_fort.zip` | Needs Workshop check | High-priority TRO IA. |
| 3 | ABC Quantum Leap | `abc_leap.zip` | Needs Workshop check | High-priority TRO IA. |
| 4 | Fresh Meat | `chmisn09.zip`, `RO_IA_chmisn09.zip` | Needs Workshop check | Preserve alternate archive provenance. |
| 5 | Operation Flush Out | `chmisn10.zip`, `RO_IA_chmisn10.zip` | Needs Workshop check | Preserve alternate archive provenance. |
| 6 | Phantoms | `phantoms.zip`, `RO_IA_phantoms.zip` | Needs Workshop check | Known for stealth-turret attack design. |
| 7 | Recovery | `recovery.zip` | Needs Workshop check | Prefer original TRO release over the later TRO-to-BZ conversion when preserving TRO behavior. |
| 8 | Red Tide | `red_tide.zip` | Needs Workshop check | Chinese-vs-CCA TRO IA. |
| 9 | Warlords | `warlords.zip` | Needs Workshop check | TRO IA. |

## Verified-missing seed

The previous 2026-09-09 reconciliation identified 42 high-confidence Map Room/1.5 candidates with no current Redux counterpart after accounting for known renamed/remade ports. Those records are retained in the full census as **Verified missing** rather than being thrown away when the census expanded.

Important examples include **Alien Alliance, Absolute Zero, Ace of Spades, Canyon of Blood, CCA Fun, Europa Snipe, Failed Plans, Fury Recycler, High Command, Infiltration and Destruction, MAG King, Operation Mest, Rabbit Hole, Sector 16A, Sector 86C, Solo Run, Supply Depot, Sweet Vengeance, Takeover, The Io Incident, The Last Strike, The Return of Eagle's Nest One, Venus Badlands Skirmish**, and the newer Map Room-only candidates recorded in the census.

**Alien Yard (`alyard13.zip`) is now explicitly included** in the master census. Its omission from the old 42-entry list was one of the reasons this broader census was necessary.

## Historical packs

Historical pack contents are tracked separately from ordinary one-map releases so that we do not accidentally duplicate missions already represented through a Redux campaign/pack.

| Pack | Historical scope | Current disposition |
|---|---:|---|
| Great Pyramid Pack | 3 maps | Reconcile individual maps / pack representation. |
| Get Arkin Sixpack | 6 maps | Preservation candidate; source/release check required. |
| Hard Soviets Map Pack | 5 maps | Preservation candidate; source/release check required. |
| Last of the Galilean | 11 SP missions plus MP content | Workshop represented; preserve provenance, do not duplicate blindly. |
| Unofficial Battlezone 2 Demo | 4 missions | Repair candidate; historical `scs2man.odf` dependency defect documented. |
| Red Wolf Missions | 8 plus secret mission | Workshop represented. |
| Shrieking Eagles Level Pack | 8 maps | Workshop represented. |
| Battlezone: Elite Corps | 10 CCA missions | Incomplete/dev-era content; source and dependency archaeology required. |
| Omega Squadron Mission Pack | 18 NSDF/BD + 8 Chinese + 6 bonus IA | Workshop represented; preserve original package provenance. |

## Selective Strategy preservation

Strategy is intentionally **curated rather than exhaustive**. The BZScrap Strategy archive is a source pool, and maps should be selected for historical importance, unusual world/terrain work, distinctive gameplay, or community interest.

### Selected: Earth

`Earth` is the first explicit Strategy preservation candidate. The preserved 1999 readme identifies **Cmdr Wayne** and gives the classic `netmis` registration as:

```text
earth.bzn    earth.des    5 5    netveh.txt S Earth
```

The `S` registration confirms it was distributed as a classic multiplayer Strategy map. Treat Earth as a standalone Redux Strategy Workshop item unless source inspection reveals a reason to bundle shared assets.

## Compatibility / repair notes already known

These should be carried into the port rather than rediscovered or silently reproduced:

- **Canyon of Blood** — historical notes identify a missing `baseName` in `bvkrtu.odf`; repair during conversion and keep project filename limits in mind.
- **Battlezone Mech Commander II** — internal BZN terrain-name mismatch; a repaired historical archive exists.
- **Defence 1** — original AIP was broken; a corrected historical version exists.
- **IAKIv2** — historical package lacks a working AIP and has a documented force-matching syntax problem.
- **Eye of the Needle**, **Oh Shit!!**, **Stolen LT** — historical notes identify incorrect internal multiplayer/strategy mission typing that prevents normal IA behavior.
- **Mars Canyons** — some copies contain a corrupt TRN; use a corrected source when possible.
- **Part 1: The Rescue** — historical release had missing-TRN/type problems; a repaired archive exists.
- **Phase Two - The Take** — custom recycler/AIP mismatch and missing custom recycler ODF are documented; a repaired archive exists.
- **Princess Part 2: The Big Climb** — historical internal `EmptyMission` typing prevents normal IA AI/end behavior.
- **Punishing the Red Cows** — AIP repair required.
- **The Crater** — historical package is missing MAT data; a reconstructed historical copy exists.
- **Flak1 / Flak2** — historical BZN naming problems; Flak2 also has a missing asset dependency.
- **Zen's MCanyons Fix** — effectively a Mars Canyons variant/fix and itself historically broken; preserve provenance, do not automatically publish separately.
- **Recovery (TRO to BZ Conversion)** — keep as a conversion/variant; the original TRO `Recovery` is the preservation priority.

## Per-map intake / port checklist

1. **Preserve source** — keep the original archive unchanged and record source URL/location, original archive name, author, version/date when known, byte size, and SHA-256.
2. **Inventory dependencies** — BZN, TRN/HGT/HG2/MAT/LGT, ODF/AIP, Lua/DLL, textures, models, sounds, custom worlds, readmes, and stock-file overrides.
3. **Establish authored behavior** — identify mission entry point, victory/failure semantics, AI production, scripted units, objectives, and intended faction/world.
4. **Convert for Redux** — fix only what is required for compatibility or a clearly documented historical defect. Prefer Lua 5.1 for legacy script reconstruction where practical.
5. **Respect legacy filename limits** — ODF names and other engine/script-facing legacy asset names must remain eight characters or fewer where required by this project.
6. **Qualify** — clean supported Redux install; mission start; objectives; AI production; success/failure; save/load where applicable; terrain/sky; audio; assets; completion.
7. **Publish standalone by default** — original author credited prominently; explain compatibility repairs; list any OpenShim/EXU dependency only if genuinely required.
8. **Re-check Workshop before upload** — avoid publishing a duplicate if another faithful Redux port appeared during conversion.

## Working documents

- [`LEGACY_MAP_PRESERVATION_CENSUS.md`](LEGACY_MAP_PRESERVATION_CENSUS.md) — complete enumerated IA/TRO/1.5 inventory and initial Redux disposition.
- This file — policy, priorities, repair notes, and release workflow.

The census is deliberately a living preservation record. A `Needs Workshop check` row is not a claim that a port is missing; it is a work item to reconcile before conversion. Conversely, a historical map should not disappear from the record merely because its source is currently missing.