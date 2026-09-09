# Instant Action Preservation Porting Backlog

This document tracks classic Battlezone Instant Action missions that are still useful candidates for preservation/porting into Battlezone 98 Redux through Campaign Reimagined.

The initial list was reconciled on **2026-09-09** against:

- Battlezone Map Room Instant Action catalog: https://bzmaps.net/missions.php?maxplayer=1&minplayer=1&type=instant_action
- BZScrap classic Instant Action archive: https://bzscrap.org/index?parent=Maps%2FBattlezone%2FInstant%20Action
- Steam Workshop for Battlezone 98 Redux: https://steamcommunity.com/app/301650/workshop/
- Ssuser's historical IA map listing for filename/title/author reconciliation: https://bzmaps.net/misc/ssuser/Ssuser%27s%20Instant%20Action%20Maps%20Listing.htm

The table below is intentionally conservative: every entry is a **high-confidence Map Room download candidate** for which no current Redux Workshop counterpart was identified after accounting for renamed/remade ports.

## Status legend

- **Not started** — source archive identified; no CR port work has begun.
- **Intake** — source archive copied into a preservation work area and inventoried.
- **Porting** — BZN/TRN/ODF/script/assets are being adapted for Redux.
- **Playable** — mission boots and can be completed, but qualification is incomplete.
- **Qualified** — tested from clean Redux install, attribution/source recorded, and ready for publication/inclusion.
- **Blocked** — missing source, rights/provenance concern, dependency, or unresolved engine incompatibility.

## Suggested first batch — GrizzlyOne95 originals

These are useful first ports because authorship/provenance is especially clear and they provide a small representative mix of scripted and combat-focused IA content.

| Mission | Original archive | Status |
|---|---|---|
| CCA Fun | `CCA Fun.zip` | Not started |
| Sweet Venegence | `Sweet Vengence.zip` | Not started |
| The Return of Eagle's Nest 1 | `The Return of Eagle's Nest 1.zip` | Not started |
| Rabbit Hole | `Rabthole 1.1.zip` | Not started |
| A Call To Arms | `Call2arm.zip` | Not started |

The Battlezone Map Room currently attributes these missions to **GrizzlyOne95**. The historical Ssuser list records at least Rabbit Hole under the older author name **Ian S.**, which is useful provenance when preserving original readmes/credits.

## High-confidence Map Room backlog

| # | Mission | Original archive | Status | Port notes |
|---:|---|---|---|---|
| 1 | The Forbidden Theories | `Chapter 1-2.zip` | Not started | Preserve multi-chapter structure and bundled dependencies. |
| 2 | Mars Peak | `Cyborggeffien - Mars Peak.zip` | Not started | Inventory custom assets/scripts before conversion. |
| 3 | Escaped by Scavenger | `Cyborggeffien - Escaped by Scavenger.zip` | Not started | Inventory custom assets/scripts before conversion. |
| 4 | Varia Fields - C Sector | `Cyborggeffien - Varia Fields - C Sector.zip` | Not started | Inventory custom assets/scripts before conversion. |
| 5 | Varia Fields - D Sector | `Cyborggeffien - Varia Fields - D Sector.zip` | Not started | Inventory custom assets/scripts before conversion. |
| 6 | Cold Winter | `cldwntr.zip` | Not started | Verify terrain/sky compatibility in Redux. |
| 7 | I Want To Break Free | `i want to break free.zip` | Not started | Check Lua/API assumptions against Redux Lua. |
| 8 | Specimen 1001 | `spec1001.zip` | Not started | Check Lua/API assumptions against Redux Lua. |
| 9 | CCA Scrap Operation | `cysilorc.zip` | Not started | Check Lua/API assumptions against Redux Lua. |
| 10 | Death Blow v2 | `dethblow_1_5.zip` | Not started | Prefer the later 1.5 source over older archive variants. |
| 11 | Heat Sink v2 | `heatsink_1_5.zip` | Not started | Prefer the later 1.5 source over older archive variants. |
| 12 | Final Destination | `final destination.zip` | Not started | Inventory custom terrain/assets. |
| 13 | Chasing the Devil | `chasing the devils.zip` | Not started | Inventory custom terrain/assets. |
| 14 | Downfall | `downfall.zip` | Not started | Verify script and objective flow. |
| 15 | Solo Run | `solorun.zip` | Not started | Do not confuse with the already-ported Flying Solo/Flyn' Solo. |
| 16 | High Command | `highcomm.zip` | Not started | Verify script and objective flow. |
| 17 | Sector 86C | `sect86c.zip` | Not started | BzFrac terrain; verify painter/terrain data under Redux. |
| 18 | The Last Strike | `tlaststr.zip` | Not started | Verify script and objective flow. |
| 19 | Europa Snipe | `Europa Snipe.zip` | Not started | Verify sniper/pilot scripting under Redux. |
| 20 | Rabbit Hole | `Rabthole 1.1.zip` | Not started | GrizzlyOne95 original; suggested first batch. |
| 21 | A Call To Arms | `Call2arm.zip` | Not started | GrizzlyOne95 original; suggested first batch. |
| 22 | Sector 16A | `sect16a.zip` | Not started | BzFrac terrain; verify terrain data under Redux. |
| 23 | Takeover | `takeover.zip` | Not started | Verify custom world/terrain dependencies. |
| 24 | Alien Alliance | `alinally.zip` | Not started | Verify Fury/custom-unit dependencies. |
| 25 | MAG King | `magking.zip` | Not started | Likely a good small smoke-test port. |
| 26 | Venus Badlands Skirmish | `Venus Badlands Skirmish.zip` | Not started | Verify Redux texture-atlas/TRN compatibility. |
| 27 | Ace Of Spades | `acespade.zip` | Not started | Likely a comparatively small skirmish port. |
| 28 | CCA Fun | `CCA Fun.zip` | Not started | GrizzlyOne95 original; suggested first batch. |
| 29 | The Io Incident | `The Io Incident.zip` | Not started | Verify Fury/custom-unit dependencies. |
| 30 | Blood and Iron | `bloodiro.zip` | Not started | Likely a comparatively small skirmish port. |
| 31 | Infiltration and Destruction | `Infiltration and Destruction.zip` | Not started | Verify pilot/sniping/objective script behavior. |
| 32 | Canyon Of Blood | `Canyon of Blood.zip` | Not started | Verify custom terrain/assets. |
| 33 | The Return of Eagle's Nest 1 | `The Return of Eagle's Nest 1.zip` | Not started | GrizzlyOne95 original; suggested first batch. |
| 34 | Operation Mest | `opmest.zip` | Not started | Verify Black Dog/custom checkpoint dependencies. |
| 35 | Sweet Venegence | `Sweet Vengence.zip` | Not started | GrizzlyOne95 original; suggested first batch. |
| 36 | Capt. Chaos strikes again! - NSDF | `pacmania.zip` | Not started | Pair with CCA variant; preserve shared assets. |
| 37 | Capt. Chaos strikes again! - CCA | `pacmani2.zip` | Not started | Pair with NSDF variant; preserve shared assets. |
| 38 | Failed Plans | `failplan.zip` | Not started | Verify Fury/Black Dog modified-unit dependencies. |
| 39 | Fury Recycler | `usrmsnfr.zip` | Not started | Verify Fury unit/ODF dependencies. |
| 40 | Battle for the Alien Anomaly | `abcfrac.zip` | Not started | Verify custom terrain/asset dependencies. |
| 41 | Absolute Zero | `AbsoZero.ZIP` | Not started | Verify terrain/sky compatibility in Redux. |
| 42 | Supply Depot | `Sdepot.zip` | Not started | Verify objective/script flow. |

## Port intake checklist

For each mission, preserve the original archive unchanged outside the shipping tree and record its provenance before editing anything.

1. **Archive intake**
   - Record original ZIP filename, source URL, author, release/version, and archive hash.
   - Preserve original README/license/credits verbatim.
   - Inventory BZN, TRN, ODF, script, texture, audio, model, and custom DLL dependencies.
2. **Redux conversion**
   - Establish the actual mission BZN entry point.
   - Repair/convert TRN texture-atlas and locale-sensitive data as required by Redux.
   - Port legacy DLL/script logic to Lua where practical instead of bundling incompatible native code.
   - Keep original mission behavior and story authoritative unless a compatibility fix requires a documented change.
   - Namespace custom assets where collisions with stock/CR/other IA content are possible.
3. **Campaign Reimagined integration**
   - Put mission content under a dedicated IA-preservation namespace rather than mixing it into rewritten stock-campaign mission directories.
   - Reuse CR/OpenShim/EXU compatibility helpers only where they solve an actual Redux incompatibility; do not gratuitously redesign the mission.
   - Preserve original author credit prominently in mission metadata and any Workshop/publication text.
4. **Qualification**
   - Boot from a clean supported Redux installation.
   - Verify objectives, fail/success paths, save/load where applicable, AI production, custom assets, terrain, sky, audio, and mission completion.
   - Test with CR/OpenShim installed as shipped, then check for avoidable coupling to unrelated CR campaign state.
   - Record any intentional behavior differences from the original release.
5. **Publication decision**
   - Re-check Steam Workshop immediately before publication to avoid duplicating a newly uploaded community port.
   - If a separate author-maintained Redux port appears, prefer linking/crediting that version instead of publishing a conflicting duplicate.

## Known exclusions / already represented on Workshop

Do not add a mission to this backlog solely because its Workshop title differs from the old ZIP name. Renamed/remade counterparts already identified include examples such as:

- `wreckers.zip` -> **Wreckers**
- `Blockade.zip` -> **Blockade Redux Redux**
- `scrapfun.zip` -> **Scrap Fun**
- `battauri.zip` -> **Battle of Taurids**
- `Flynsolo.zip` -> **Flyn' Solo**
- Downhill CCA variant -> **Downhils (Faction Switch)**
- **Don't Tread On Me**
- **Though I Walk**
- **The Red Wolf Missions**
- **The Battle Zone**
- **The Relic**

Workshop status is time-sensitive. Re-run the comparison before starting and again before publishing a port.

## Follow-up catalog work

The high-confidence table above is not the entire surviving classic IA ecosystem. A second pass should merge the remaining **BZScrap-only/historical candidates** from Ssuser's larger catalog, deduplicate alternate ZIP versions, and separate:

- confirmed currently downloadable archives;
- archives recoverable from mirrors/community collections;
- historical entries with no surviving source currently identified;
- missions already represented by renamed Workshop ports.

Only the first two groups should become active CR port tasks.
