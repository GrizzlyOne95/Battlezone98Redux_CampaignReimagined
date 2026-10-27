# Battlezone (1998) guide lore and recorded cut-content audit

Research checkpoint: **2026-10-16**. Documentation/backlog only; this checkpoint does **not** activate mission content, change gameplay, or endorse a specific reconstruction.

## Purpose and evidence policy

Preserve discoveries from the 1998 *Battlezone Official Strategy Guide* and GoombaBZ's transcribed campaign VO so future Campaign Reimagined work can restore historically grounded material without repeating research. Every entry distinguishes what a source **says** from what shipped in original game logic and what CR already implements.

Evidence tags:
- **[GUIDE]**: Shane Mooney, *Battlezone Official Strategy Guide*, Brady Publishing (Macmillan Digital Publishing USA imprint), copyright 1998, ISBN 1-56686-775-4. Contemporary licensed guide with developer acknowledgments; **published narrative/walkthrough**, not proof that a feature or encounter was implemented. Readable scan catalog: https://archive.org/details/battlezoneoffici00shan.
- **[VO]**: GoombaBZ transcription, `Tools/TranscriptSources/GoombaBZ/campaigns.csv`, and matching `Text/*.txt` subtitles. Recorded speech does not prove that an audio call runs. Upstream "Unused voiceover" notes are *not authoritative* (`misn1303.wav` is a known false positive).
- **[SOURCE]**: Archived C++ in `References/*Source/` and documented Lua ports. In particular, `Docs/MISN15_SOURCE_PORT.md`, `Docs/MISN16_LUA_PORT.md`, `Docs/MISN17_SOURCE_PORT.md`, and `Docs/MISN18_SOURCE_PORT.md`. These BZ2-derived mission sources are not automatically identical to the **shipped 1.5** binary; consult the 1.5 decompile when making historic-execution claims.
- **[CR]**: State of this repository's `main` checked during the 2026-10-16 audit. Branches/PRs may supersede it.
- **[INFERRED]**: Plausible synthesis or restoration design, explicitly not established by original sources.
- **[UNKNOWN]**: Requires asset, script, game-version, or live testing to settle.

The owner supplied an OCR text transcription of the guide as `texttranscript.txt`. The OCR is *not committed here* (avoid copying a copyrighted book into the public repo). Its SHA-256 at the time of research was
`1bcbaf3cf2ab21045b850fc618afe1ad712e2df2e413668047a76f618fb42602`.
The OCR is imperfect: search nearby mission headings/wrap-ups and confirm proper names/punctuation against the scan when accuracy matters. Anchor line numbers below refer only to that exact OCR file. This document paraphrases guide passages rather than republishing them.

## High-priority discovery: Tartarus and an alleged "Titan"

**[GUIDE]** The **Mission 15 wrap-up** (OCR approximately lines **6520-6536**) states that both NSDF and CCA agreed, as part of their treaty against the Furies, **not to tamper with the Tartarus relics**. The stated concern is `unleashing a Titan of some sort`. The surrounding text likens the Fury crisis to Pandora's box and interprets Greek mythology as imperfect recollections of Cthonian technology.

**[VO]** `misn1513.wav` and `misn1514.wav` supply Buzz's and Collins's actual warning against approaching the structure. They **do not name a Titan**.

**[SOURCE]** The Mission 15 proximity trigger plays these two warnings on a **strictly less than 150 m** approach to Tartarus; archived `References/Misn15Source/Misn15Mission.cpp` does not establish a spawned Titan or a release encounter. See `Docs/MISN15_SOURCE_PORT.md`.

**[CR]** The active `Scripts/CRMisn15.lua` already adds a **CR-designed** prolonged-intrusion Fury response and arc-mine behavior. Neither is proof of a historical Titan fight. Preserve that distinction when documenting it.

**[UNKNOWN]** The guide does not specify a Titan unit model, size, allegiance, capabilities, containment method, or whether anything could actually emerge. The name could refer to a Cthonian machine or a Fury-like threat, but either identification is **inference**. Do **not** label a custom boss "restored cut Titan" until supported by further assets/source.

**Next investigation:** compare `misn15` and `misn15b` BZN placements/labels, archived native mission logic, 1.5 executable behavior and unused assets; assess whether a bespoke Tartarus encounter should be an optional, explicitly CR-original secret.

## Historical Cthonian lore preserved in the guide

These are **the guide's account**, sometimes framed there as tentative NSDF intelligence. Do not elevate them to independently verified facts about original shipped story/engine behavior.

| Subject | [GUIDE] evidence / interpretation | OCR anchor |
| --- | --- | --- |
| **Icarus and the Cthonians** | The ancient bio-metal civilization is described as coming from Icarus. Guide star charts place it "between Mars and Saturn", where the NSDF instead finds an asteroid belt, leading it to infer the homeworld was destroyed. Retain the guide's geographic wording, not a silently corrected orbit. | ~5490-5503, star-port relic wrap-up |
| **Olympian Council** | A scientific faction led by **Paternus**; knowledge and technology shared with ancient humans are linked to Greek myths. | ~5508-5518 |
| **Hadean Crown** | Rival monarchy governed by **Nexus V**; Nexus's arms race against Paternus's faction leads to the secret **Lerna** weapons facility on Io. | ~5519-5535 |
| **Hercules Brigade / Hydra** | The Olympian Council dispatched its elite **Hercules Brigade** to confront **Hydra** defenders of Nexus's Lerna laboratory. | ~5832-5844, Fury recovery wrap-up |
| **Bio-metal logistics** | **Hephaestus** transported bio-metal from **Lemnos** to the **Omega Star Port**, then presumably onward. | ~4630-4651, Lemnos wrap-up |
| **Fury aggression** | The guide attributes a new sentient bio-metal strain to **Nexus** and material derived from deceased ancient Greek warriors; an intentionally engineered aggression factor is the proposed cause of Fury hostility. | ~5675-5690, Io Fury discovery/recovery |
| **Charon and Styx** | **Charon** collected genetic material on ancient Greek battlefields, delivered to **Styx** on Venus, where the sentient component of bio-metal was created. The guide speculates that such machines contributed to Cthonian extinction. | ~6388-6409, Titan rescue wrap-up |
| **Mythology** | NSDF researchers reinterpret figures from Greek mythology as recollections of Cthonian technology/machines; do not conclude every mythic name corresponds to a distinct playable craft. | ~6520-6536 |

**Continuity caution:** the guide's "machine" characterization of mythical gods and its references to sentient biological material are both part of its narrative. Neither proves a specific physiology for a Titan. These story claims are **not** all present in GoombaBZ's recorded VO.

## From Titan to Achilles; the overlooked crystal path

### Titan escape connects directly to Achilles

- **[GUIDE]** The **Mission 16 wrap-up**, OCR ~6661-6674, says surviving Furies escaped Titan and established a major factory on **Achilles**, which the guide calls a small moon orbiting **Uranus**.
- **[VO]** `misn1615.wav` reports a group of Furies boarding a transport to flee Titan, with an explicit intention to pursue them; `misn1616.wav` announces Fury factory destruction.
- **[SOURCE]** Neither appears in the archived active `Misn16Mission.cpp` playback calls or the faithful `Scripts/misn16.lua`. This is a strong **unused VO narrative bridge**, **not** proof a transport set-piece had working code.
- **[INFERRED]** Consider a mission-end departure sighting or cinematic *only after checking for usable transport assets, map labels and native mission hooks*. Do not silently graft into source-faithful base logic.

### Mission 17: crystal processing sabotage was at least conceived

- **[VO]** `misn1705.wav`: factory power levels stabilize after an apparent crisis. `misn1706.wav` mentions crystals. `misn1707.wav` says the power converter needs a **processed crystal**. `misn1708.wav` suggests getting an **unprocessed crystal** into the converter. `misn1702.wav` warns of critical power levels; `misn1703.wav` warns of an imminent explosion; `misn1709.wav` is a success congratulation. The causal order of all lines is **not established** by the transcript alone.
- **[SOURCE]** `References/Misn17Source/Misn17Mission.cpp` declares `crysswitched`, `firsttimecrysreplaced`, `crystalhint1/2/3`, `procrysgone`, `procrys`, `rawcrys1..5` and crystal-destruction/replacement timers. These survive in the Lua port's state. **There is no executable crystal-processing mechanism in the archived active mission body.** `misn1705-1709` are not called by the faithfully ported body. The C++ archive's outer `Execute` is wrapped in `#if 0`; the Lua port activates the preserved mission body but retains the crystal members unused. See `Docs/MISN17_SOURCE_PORT.md`.
- **[GUIDE]** The Mission 17 walkthrough, OCR ~6816-6829, prescribes destroying the **three power converters behind four apparently invulnerable main factory buildings**. Its wrap-up, ~6830-6851, attributes the consequent overload, seismic instability and imminent destruction of Achilles to the factory's power draw from the moon's core. **No "crystal" occurrence exists in the provided guide OCR.** It documents the final converter-destruction route, not the abandoned crystal substitution.
- **[INFERRED]** A player-engineered **processed/unprocessed crystal swap** could offer a secondary sabotage route, potentially destabilizing the same power system. The exact transport mechanic (hauler, tug, recycler, destructible crystal), replacement rules, timing and explosion condition are **not verified**.

**Owner-directed restoration objective (backlog; NOT implemented here):** Restore the cut crystal concept in CR, as an **optional, documented reconstruction**, while preserving the original power-converter destruction path. Before implementation:
1. Audit `misn17` original BZN object labels, `.odf` assets and the 1.5 executable for raw/processed crystal objects or pickups; distinguish map-original material from newly authored props.
2. Reconstruct a playable state graph from audio and surviving C++ member names; record precisely which transitions are inferred. Avoid assuming `1702` / `1703` are crystal-specific (stock victory already uses `1703`).
3. Decide how crystal handling coexists with the seven power-tower/minefield phase and the three factory-part victory gates, including simultaneous alternative completion.
4. Keep the faithful Lua/native port and its source-parity baseline traceable; add CR-only marked extensions rather than presenting authored behavior as recovered native code.
5. Account for save/load persistence, lost/destroyed crystal handles, sound sequencing/subtitles, 2-4-player leader authority and client replication, co-op and offline success/failure precedence.
6. Verify WAV availability per supported language, `Tools/Test-ShippedCutVo.py`, `Tools/Import-GoombaTranscripts.py --check`, package lock requirements and real GOG/Steam play before shipping.

## Other recorded-VO restoration queue (status at audit)

The CSV contains **778 campaign/training entries**, **51** of which have an explicit "Unused voiceover." annotation. Those labels are only *leads*, not a complete or infallible cut-content list. In particular `misn1303.wav` is marked unused yet plays in original Mission 13 and in CR; see `Tools/TranscriptSources/GoombaBZ/README.md`.

| Priority | VO files / mission | Finding and audit status | Next decision |
| --- | --- | --- | --- |
| **High** | `misn1615`; Mission 16 | A Fury transport apparently departs Titan. **[VO]** No matching active call in archived Mission 16 DLL-body or current faithful Lua. | Inspect map/assets, design a truthful bridge to Achilles (avoid asserting a finished cut cinematic existed). |
| **High** | `misn1609`, `1610`, `1611`, `1614`, `1616`; Mission 16 | Counterattack, defending the Texas, flanking advice, an optional end-of-reinforcement/construction reminder and factory completion. `1614` is explicitly commented out in `Scripts/misn16.lua`; the others have no active calls in the source port. | Reconcile each line with actual encounters/objective order; restore selectively, not as unconditional radio spam. |
| **High** | `misn1817`, `misn1818`; Mission 18 | Fury attack on Texas and dedicated Texas-loss line. **[SOURCE]** Actual loss branch still plays `misn1704.wav`, not `misn1818.wav` (`Scripts/misn18.lua` and archived C++). | Check stock 1.5 behavior; consider replacing the cross-mission audio in a clearly marked CR-only enhancement. |
| **Medium** | `misn0825`; Mission 8 | Collins responds to destruction of **Colorado** and orders continuing against the CCA base. **[CR]** Source-parity test explicitly requires this line remain unused. | Reconsider intentionally with owner; confirm no overlapping existing destruction dialogue or gameplay fallout. |
| **Medium** | `misns120` / `misns121`; Soviet Golem Ambush | Alternative American reinforcement approach warnings. **[SOURCE]** The original C++ branch remains inside disabled comments in `Scripts/misns1.lua`, with concrete approach-distance tests. | Validate paths/labels on original BZN, then consider a faithful optional reactivation. |
| **Medium** | `misn0435`; Mission 4 | Alternative Mars/bio-metal retrospective not referenced by current Mission 4 script or campaign INI. | Compare with `misn0426` (already restored) before choosing; likely alternate, not additive, narration. |
| **Low / defer** | `misn1225`; Mission 12 | Soviet scrap-silo sabotage line. `Docs/MISN12_COOP.md` deliberately leaves it out because it describes an earlier map arrangement. | Do not enable without map/layout evidence. |
| **Low / defer** | `misn1517`, `misn1803` | Transitional line for 15; redundant return line for 18 (`1804` is active). | No need to force every unused voice into the final design. |
| **Research** | `misns211` / `minss213`; Soviet Precious Cargo | Alternate American-on-hill warning and Black Dog retreat line; filename `minss213` is distinct from the active `misns213`. | Audit Soviet Mission 2 source and compare alternate takes, not assume new phases. |
| **Research** | Training: `tran0403/0404/0419/0422/0423`, `misn0115-0120`, `tran0203/0213` | Training flow/revisions preserved as labeled unused recordings. | Audit tutorial objectives/control scheme before attempting restored lessons. |

### Already restored or explicitly accounted for in CR: don't duplicate

- **Mission 4:** `misn0426.wav` is already the retrospective in `Config/crcampgn.ini`; `misn0407.wav` (wingman sees relic) and `misn0428.wav` (relic destruction rebuke) have CR logic in `Scripts/misn04.lua`.
- **Mission 5:** `misn0515.wav` already identifies **Lemnos** as the original bio-metal production facility in `Scripts/misn05.lua`.
- **Mission 6:** `misn0615-0627.wav` and other naval/blockade radio already have restored cut-VO scheduling in `Scripts/misn06.lua`. The intended Lincoln/Roosevelt naval sequence is already tracked; see `CHANGELOG.md`.
- **Mission 7:** `misn0703/0704` test range and minefield and `misn0717` alternative overlook take are implemented in `Scripts/misn07.lua`; see `Docs/MISN07_COOP.md`.
- **Mission 9:** `misn0910/0917` were restored; `0912` deliberately remains a duplicate briefing; see `Docs/MISN09_COOP.md`.
- **Mission 12:** `misn1224.wav` is restored with an **inferred** Razor One escape route; the map contains an otherwise unused one-way route, but voice-to-route attribution is not original-source proof. See `Docs/MISN12_COOP.md`.
- **Mission 13:** `misn1301.wav` is restored, and `misn1303.wav` plays on mission victory despite Goomba's "unused" note; see `Docs/MISN13_COOP.md`.
- **Mission 15:** `misn1506/1508/1512` and the Tartarus warnings are already active in `Scripts/CRMisn15.lua`; see `Docs/MISN15_COOP.md`.

## Implementation and research handoff

1. **First:** map + code + VO parity audit for **Mission 17 crystal logistics**; capture a diagram of the actual available objects and a source-attributed proposal before changing scripts.
2. **Then:** Mission 16 Titan transport VO/context and Mission 18 Texas dialogue. These can strengthen the chronological Titan-to-Achilles finale without forcing speculative new lore.
3. **Then:** optional Titan/Tartarus mystery work. Keep the guide's explicit *warning* as a published-lore fact and any boss/guardians/emergence as deliberately authored CR content unless an original implemented encounter is found.
4. **Afterward:** route-specific Soviet warnings and alternate Mission 4/8 dialogue, with tests and review of existing restored lines.

**Do not** commit the full OCR, convert unverified claims into source-faithful Lua, overwrite existing restored scenes, or assume a scripted line exists in every localized `.zfs`. Consult the owner before turning open interpretive questions (especially the Titan's identity and crystal gameplay) into mandatory campaign canon.

## Quick reference locations

- Guide scan: https://archive.org/details/battlezoneoffici00shan (verify page view against supplied OCR)
- Transcript corpus: `Tools/TranscriptSources/GoombaBZ/campaigns.csv`, `Tools/TranscriptSources/GoombaBZ/README.md`
- Intro/guide claims: owner's `texttranscript.txt`, SHA-256 above, especially OCR lines ~4630-4651, 5490-5535, 5675-5690, 5832-5844, 6388-6409, 6520-6536, 6661-6674, 6816-6851
- Port/source comparisons: `References/Misn15Source/`, `References/Misn16Source/`, `References/Misn17Source/`, `References/Misn18Source/` and `Docs/MISN*_SOURCE_PORT.md` or `Docs/MISN16_LUA_PORT.md`
- Restored VO/package checks: `Tools/Test-ShippedCutVo.py`, `Tools/Import-GoombaTranscripts.py`, `Shipping/shipping.lock.json`
