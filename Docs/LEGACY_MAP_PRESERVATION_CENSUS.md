# Legacy Battlezone Map Preservation Census

**Working document — 2026-09-10**

This is the source-of-truth ledger for the classic Battlezone map preservation effort. The release target is **Battlezone 98 Redux**, with **standalone Workshop items by default**. Campaign Reimagined is being used as a preservation/research workspace; inclusion in CR is not a requirement for a port.

## Source basis

The census is being reconciled from:

- Ssuser's historical Instant Action map listing: https://bzmaps.net/misc/ssuser/Ssuser%27s%20Instant%20Action%20Maps%20Listing.htm
- Battlezone Map Room IA catalog: https://bzmaps.net/missions.php?type=instant_action
- BZScrap Instant Action archive: https://bzscrap.org/index?parent=Maps%2FBattlezone%2FInstant%20Action
- BZScrap Strategy archive: https://bzscrap.org/index?parent=Maps%2FBattlezone%2FStrategy
- Battlezone 98 Redux Steam Workshop
- Preserved archives/readmes/minimaps in the project owner's Google Drive collections

Ssuser's historical page states **262 Battlezone IA maps**, **9 Red Odyssey maps**, **21 Battlezone 1.5 maps**, and **9 mod/map packs containing 88 missions** as of its last published count. A previous row-by-row working pass produced a higher normal-BZ row count; that discrepancy is deliberately left unresolved here until the table can be re-parsed/recounted mechanically. Do not silently replace the published count with the working count.

## Status vocabulary

| Status | Meaning |
|---|---|
| Verified missing | No Redux counterpart was identified in the latest completed reconciliation. Active port candidate. |
| Needs Workshop check | Historical release identified, but renamed/remade Redux equivalence has not yet been ruled out. |
| Workshop represented | Existing Redux item already represents the release; do not duplicate blindly. |
| Archive found | Original or clearly preserved source archive is available. |
| Readme/minimap found | Provenance/reference material is available, but the complete archive has not yet been confirmed. |
| Repair candidate | Historical source documents a defect or newer-engine incompatibility that should be repaired during porting. |
| Duplicate / variant | Preserve provenance, but likely fold into another release rather than publish separately. |
| Missing source | Historical release is known but no usable source has yet been located. |
| Porting / Playable / Qualified | Redux conversion stages. |

## A. Verified-missing seed from the 2026-09-09 reconciliation

These 42 entries were the original high-confidence backlog. They remain active candidates, but the census is now much broader.

| # | Mission | Historical archive | Status |
|---:|---|---|---|
| 1 | The Forbidden Theories | `Chapter 1-2.zip` | Verified missing |
| 2 | Mars Peak | `Cyborggeffien - Mars Peak.zip` | Verified missing |
| 3 | Escaped by Scavenger | `Cyborggeffien - Escaped by Scavenger.zip` | Verified missing |
| 4 | Varia Fields - C Sector | `Cyborggeffien - Varia Fields - C Sector.zip` | Verified missing |
| 5 | Varia Fields - D Sector | `Cyborggeffien - Varia Fields - D Sector.zip` | Verified missing |
| 6 | Cold Winter | `cldwntr.zip` | Verified missing |
| 7 | I Want To Break Free | `i want to break free.zip` | Verified missing |
| 8 | Specimen 1001 | `spec1001.zip` | Verified missing |
| 9 | CCA Scrap Operation | `cysilorc.zip` | Verified missing |
| 10 | Death Blow v2 | `dethblow_1_5.zip` | Verified missing |
| 11 | Heat Sink v2 | `heatsink_1_5.zip` | Verified missing |
| 12 | Final Destination | `final destination.zip` | Verified missing |
| 13 | Chasing the Devil | `chasing the devils.zip` | Verified missing |
| 14 | Downfall | `downfall.zip` | Verified missing |
| 15 | Solo Run | `solorun.zip` | Verified missing |
| 16 | High Command | `highcomm.zip` | Verified missing |
| 17 | Sector 86C | `sect86c.zip` | Verified missing |
| 18 | The Last Strike | `tlaststr.zip` | Verified missing |
| 19 | Europa Snipe | `Europa Snipe.zip` | Verified missing / Archive found |
| 20 | Rabbit Hole | `Rabthole 1.1.zip` | Verified missing / Archive found |
| 21 | A Call To Arms | `Call2arm.zip` | Verified missing / Archive found |
| 22 | Sector 16A | `sect16a.zip` | Verified missing |
| 23 | Takeover | `takeover.zip` | Verified missing |
| 24 | Alien Alliance | `alinally.zip` | Verified missing |
| 25 | MAG King | `magking.zip` | Verified missing |
| 26 | Venus Badlands Skirmish | `Venus Badlands Skirmish.zip` | Verified missing |
| 27 | Ace Of Spades | `acespade.zip` | Verified missing |
| 28 | CCA Fun | `CCA Fun.zip` | Verified missing / Archive found |
| 29 | The Io Incident | `The Io Incident.zip` | Verified missing |
| 30 | Blood and Iron | `bloodiro.zip` | Verified missing |
| 31 | Infiltration and Destruction | `Infiltration and Destruction.zip` | Verified missing |
| 32 | Canyon Of Blood | `Canyon of Blood.zip` | Verified missing / Repair candidate |
| 33 | The Return of Eagle's Nest 1 | `The Return of Eagle's Nest 1.zip` | Verified missing / Archive found |
| 34 | Operation Mest | `opmest.zip` | Verified missing |
| 35 | Sweet Venegence | `Sweet Vengence.zip` | Verified missing / Archive found |
| 36 | Capt. Chaos strikes again! - NSDF | `pacmania.zip` | Verified missing |
| 37 | Capt. Chaos strikes again! - CCA | `pacmani2.zip` | Verified missing |
| 38 | Failed Plans | `failplan.zip` | Verified missing |
| 39 | Fury Recycler | `usrmsnfr.zip` | Verified missing |
| 40 | Battle for the Alien Anomaly | `abcfrac.zip` | Verified missing |
| 41 | Absolute Zero | `AbsoZero.zip` | Verified missing |
| 42 | Supply Depot | `Sdepot.zip` | Verified missing |

### Correction added after the first audit

| Mission | Historical archive | Status | Why it matters |
|---|---|---|---|
| Alien Yard | `alyard13.zip` | Verified missing / Readme found | Omitted by the old 42-map shortlist. Historical source describes Alex112's unusual Achilles/custom-world experiment with airborne-style units. |

## B. The Red Odyssey IA preservation lane

All nine historical TRO releases are preservation targets unless an existing faithful Redux port is positively identified.

| # | Mission | Archive(s) | Author | Status / notes |
|---:|---|---|---|---|
| 1 | ABC Chinese Mission 2 | `abc_chin2.zip` | {ABC}~Scarab | Needs Workshop check / variant of Chinese Mission 2 |
| 2 | ABC Fortress of Fear | `abc_fort.zip` | {ABC}~Scarab | Needs Workshop check; high priority |
| 3 | ABC Quantum Leap | `abc_leap.zip` | {ABC}~Scarab | Needs Workshop check; timed/customized |
| 4 | Fresh Meat | `chmisn09.zip`, `RO_IA_chmisn09.zip` | {SFP} Sonic | Needs Workshop check |
| 5 | Operation Flush Out | `chmisn10.zip`, `RO_IA_chmisn10.zip` | {SFP} Sonic | Needs Workshop check |
| 6 | Phantoms | `phantoms.zip`, `RO_IA_phantoms.zip` | BSer | Needs Workshop check; stealth-turret waves |
| 7 | Recovery | `recovery.zip` | BSer | Needs Workshop check; original TRO release has priority over BZ conversion |
| 8 | Red Tide | `red_tide.zip` | ssuser | Needs Workshop check; Chinese vs CCA |
| 9 | Warlords | `warlords.zip` | ssuser | Needs Workshop check; cloaked Chinese attacks |

## C. Expanded historical IA candidates identified in the current source pass

These are outside the original 42 and are now explicitly retained instead of being lost between catalogs. `Needs Workshop check` is intentionally conservative: it is **not** a claim that the map is definitely absent from Redux yet.

| Mission | Archive(s) / source note | Status |
|---|---|---|
| ABC Battle for the Colliseum | `abc_coll.zip` | Needs Workshop check |
| Abridged | `abridged.zip` | Needs Workshop check |
| Armory Rules | `armryrlz.zip` | Needs Workshop check |
| The Arsenals of Io | `arsenals.zip` | Needs Workshop check |
| Artifact | `artifact.zip` | Needs Workshop check |
| The Assault | `assault.zip` | Needs Workshop check |
| Attack the CCA Again | `usrmsnda.zip` | Needs Workshop check |
| Battle at Iron Peak | `ironpeak.zip` | Needs Workshop check |
| The Battle for Hoth | `hothbttl.zip` | Needs Workshop check |
| Battle for the Scrap Field | `ScrapField.zip` | Needs Workshop check |
| Battlezone Mech Commander V 1.1 | `batlzm11.zip` | Needs Workshop check |
| Battlezone Mech Commander II | `batlzm2.zip`, `batlzm2_fixed.zip` | Repair candidate |
| Desert Storm | `DesertSt.zip` | Needs Workshop check |
| Devil's Run | `devilrun.zip` | Needs Workshop check |
| Die on the River | `RedRiver.zip` | Needs Workshop check |
| Double Terror | `BV_Double_Terror_v1.1` | Repair candidate |
| Fire Fox 2 | `firefox2.zip` | Needs Workshop check; historical bug-fixed release |
| Flak1 | `flak1.zip` | Repair candidate |
| Flak2 | `flak2.zip` | Repair candidate |
| Fleeing the Wrangling Herd | `usrmsnde.zip` | Needs Workshop check |
| Heat Sink (legacy) | `heatsink.zip` | Duplicate / variant of later 1.5 release unless behavior differs materially |
| Hellborn | historical source | Needs Workshop check |
| Hell's Gate | `hellgate.zip` | Readme/minimap found / Needs Workshop check |
| Heroical | `heroical.zip` | Needs Workshop check |
| High Ground | `highgrnd.zip` | Needs Workshop check |
| Ice Strike | `icestrike.zip` | Needs Workshop check |
| In Between | `inbtween.zip` | Needs Workshop check |
| Infiltrator Part One | `infltrte.zip` | Needs Workshop check |
| Insomnia | `insomnia.zip` | Needs Workshop check |
| Instant Action | `instantact.zip` | Needs Workshop check; historical Activision IA release |
| Last Man on the Moon | `lastmoon.zip` | Needs Workshop check |
| Left on the Moon | `leftmoon.zip` | Needs Workshop check |
| The Lode | `the_lode.zip` | Needs Workshop check |
| Lock and Load | `locknload.zip` | Needs Workshop check |
| Long Shot | `longshot.zip` | Needs Workshop check |
| Lots of Canyons on Titan | `usrmsngr.zip` | Needs Workshop check |
| Lunar Recon | `Lunarrcn.zip` | Needs Workshop check |
| Mars Canyons | `Mcanyons.zip` | Repair candidate |
| Mars Wars | `marswars.zip` | Needs Workshop check |
| Martian War | `martianwar01.zip` | Needs Workshop check |
| On the Offensive | `ontheoffensive.zip`, `ofensive.zip` | Needs Workshop check |
| Outpost | `outpost.zip` | Readme/minimap found / Needs Workshop check |
| Outriders | `outrider.zip` | Needs Workshop check |
| Paranoia Conversion | `paranoia.zip` | Readme/minimap found / Needs Workshop check |
| Part 1: The Rescue | `part___1.zip`, `partone.zip`, `part_one_fixed.zip` | Repair candidate |
| Part Two: Scrap Yard | `part___2.zip` | Needs Workshop check |
| Part Three: The Quarry | `part___3.zip` | Needs Workshop check |
| Recovery (TRO to BZ Conversion) | `recoverybz.zip` | Duplicate / variant; original TRO Recovery is priority |
| Red Field | `redfield.zip` | Needs Workshop check |
| Red Plains | `RedPlain.zip` | Needs Workshop check |
| Red Ravines | `ravines.zip` | Needs Workshop check |
| Red Revenge | `redrevng.zip` | Needs Workshop check |
| Red Rock | `red_rock.zip` | Needs Workshop check |
| The Relic Mission | `Relichunt.zip`, `convoy5m.zip` | Needs Workshop check |
| Tweaked Demo | `demonova.zip` | Needs Workshop check; stock-file overwrite risk |
| Under Force | `bz-underfor.zip` | Needs Workshop check |
| Undiscovered Country | `undscvrd.zip` | Needs Workshop check |
| User Mission 2 | `User Mission2.zip`, `usrmsn02.zip` | Needs Workshop check |
| usrmsn26 | `usrmsn26.zip` | Needs Workshop check / historical test release |
| usrmsn50 | `usrmsn50.zip` | Needs Workshop check |
| War Zone | `warzone.zip` | Archive found / Needs Workshop check |
| Winter War II | `WinterW21.zip` | Needs Workshop check |
| Wreckers | `wreckers.zip` | Workshop represented |
| Zen's MCanyons Fix | `Zmcanyons.zip` | Duplicate / repair variant of Mars Canyons |
| Ziggurat | `ziggurat.zip` | Needs Workshop check |

## D. Additional preserved legacy-map references in Drive

The historical `Map readmes & pics` collection supplies provenance/reference material for many more maps. Some are IA, some are Strategy/DM or conversions and must be classified before being moved into the IA queue. The important point is that they are now recorded rather than ignored.

`Walker Arena`, `Recon Mars`, `Heartbreak Ridge`, `Base Raid`, `Ancients`, `Rock Baby`, `Scrap Pit`, `Ravine`, `Dunes`, `Lifeline`, `Strike at the Heart`, `Punishment`, `Bring it Home`, `Nasty Surprise`, `Grand Theft`, `Total Recall`, `Valkyrie`, `Moon v1.5`, `Warfield`, `Undiscovered`, `Rend`, `Rings`, `HiLo`, `Machoman`, `Mars Madness`, `Biometal Run v1.5`, `Tobruk v1.5`, `Scrap Yard`, `Vulcanic`, `The Pits`, `Vendetta`, `Nemesis`, `Mtn. Maddness`, `Io`, `Par 3`, `Canyon Madness`, `Z Snowed In`, `Blast Chamber`, `Ice Ice Baby`, `Scrap Crater`, `Moon War`, `Death Cirlce`, `Hex Loader`, `Mags Cage`, `Low Visibility`, `Achilles Pie`, `Face of Death`, `Aarmpits`, `Parp Parp`, `Martians`, `Foothills`, `Mag Arena`, `Victory Hill`, `Bommamid`, `Scouts & Rockets III`, `Nomad`, `Fury Hell`, `Death by Dawn`, `Shooter`, `Tunguska`, `Downhill`, `Bridges`, `Z Heavy Metal`, `The Great Pyramid`, `Final Strike`, `Lunar Chaos`, `Rest & Relaxation`, `Run Away!`, `The Crucible`, `Though I Walk`, `Dueling Arena`, `Clash of Titans`, and `Dragon's Mouth`.

### Complete archives already found in Drive during this pass

| Archive | Map / likely content | Census action |
|---|---|---|
| `Europa_Snipe.zip` | Europa Snipe | Active port candidate |
| `furyhell.zip` | Fury Hell | Reconcile Workshop, then port if absent |
| `machoman.zip` | Macho Man | Reconcile Workshop, then port if absent |
| `payback.zip` | Payback | Reconcile Workshop, then port if absent |
| `warzone.zip` | War Zone | Reconcile Workshop, then port if absent |
| `The Return of Eagle's Nest 1.zip` | The Return of Eagle's Nest 1 | Active port candidate |
| `Sweet Vengence.zip` | Sweet Venegence | Active port candidate |
| `Rabthole 1.1.zip` | Rabbit Hole | Active port candidate |
| `CCA Fun.zip` | CCA Fun | Active port candidate |
| `Call2arm.zip` | A Call To Arms | Active port candidate |
| `Rescuethe5th%21.zip` | Rescue the 5th! | Add to historical reconciliation; omitted from old 42 |

## E. Known Redux representations / exclusions from duplicate publication

These historical releases already have known Redux representations from the earlier audit. Preserve their source/provenance, but do not create another Workshop item without a reason.

- Wreckers
- Blockade -> **Blockade Redux Redux**
- Scrap Fun
- Battle of Taurids
- Flying Solo / Flyn' Solo
- Downhill CCA variant -> **Downhils (Faction Switch)**
- Don't Tread On Me
- Though I Walk
- The Red Wolf Missions
- The Battle Zone
- The Relic

Workshop state is time-sensitive; this list should be checked again before publication.

## F. Historical packs / campaigns

| Pack | Historical scope | Disposition |
|---|---:|---|
| Great Pyramid Pack | 3 maps | Reconcile individual-map vs pack representation |
| Get Arkin Sixpack | 6 maps | Preserve as coherent pack unless source inspection suggests otherwise |
| Hard Soviets Map Pack | 5 maps | Preserve as coherent pack |
| Last of the Galilean | 11 SP missions plus MP content | Existing Redux representation known; preserve provenance |
| Unofficial Battlezone 2 Demo | 4 missions | Repair candidate; documented `scs2man.odf` defect |
| The Red Wolf Missions | 8 plus secret mission | Workshop represented |
| Shrieking Eagles Level Pack | 8 maps | Workshop represented |
| Battlezone: Elite Corps | 10 CCA missions | Development-era archaeology; dependencies need inventory |
| Omega Squadron Mission Pack | 18 NSDF/BD + 8 Chinese + 6 bonus IA | Workshop represented; retain original package provenance |

## G. Selective Strategy lane

Strategy is **not** currently an exhaustive-port target, but worthwhile maps should be preserved selectively.

| Map | Author / evidence | Status |
|---|---|---|
| Earth | Cmdr Wayne; preserved 1999 readme registers `earth.bzn` as `S Earth` in `netmis` | Selected standalone Strategy port candidate |

More Strategy candidates should be selected after the IA/TRO census is stable, with preference for historically notable maps, custom worlds/terrain, unusual mechanics, or strong community interest.

## H. Repair queue carried forward from historical documentation

These are not reasons to discard maps. They are exactly the kind of compatibility defects this preservation pass should fix while documenting the change.

- Canyon of Blood — missing/incorrect `baseName` relationship in custom ODF noted historically.
- Battlezone Mech Commander II — internal BZN terrain-name mismatch; repaired historical variant exists.
- Defence 1 — broken AIP; corrected historical version exists.
- IAKIv2 — missing/broken AIP and force-matching syntax issue.
- Eye of the Needle / Oh Shit!! / Stolen LT — incorrect internal multiplayer/strategy mission typing prevents normal IA behavior.
- Mars Canyons — corrupt TRN in some releases.
- Part 1: The Rescue — missing TRN / script-success issues in original variants.
- Phase Two - The Take — custom recycler/AIP mismatch and missing recycler ODF.
- Princess Part 2: The Big Climb — internal `EmptyMission` typing interferes with IA AI/end behavior.
- Punishing the Red Cows — AIP repair required.
- The Crater — historical package missing MAT data; reconstructed copy exists.
- Flak1 / Flak2 — BZN filename problems; Flak2 also has a missing asset dependency.
- Zen's MCanyons Fix — preserve only as Mars Canyons repair provenance, not a separate target by default.

## Next reconciliation pass

1. Reconcile every row in sections C/D against the current Redux Workshop, including renamed/remade ports.
2. Enumerate the remainder of Ssuser's normal-BZ IA table so **every historical row** exists in this ledger rather than only the current expanded subset.
3. Search Drive/BZScrap/Map Room/mirrors for original archives; distinguish complete archive vs readme/minimap-only evidence.
4. Add all 21 historical Battlezone 1.5 individual-map rows explicitly.
5. Identify and inventory the complete source bytes for all nine TRO releases.
6. Assign port order: source-found + no-Workshop-counterpart first, repair-heavy archaeology second.

This file is intentionally conservative about `Verified missing`. A map is not moved into that state until exact and renamed Redux representations have been checked.