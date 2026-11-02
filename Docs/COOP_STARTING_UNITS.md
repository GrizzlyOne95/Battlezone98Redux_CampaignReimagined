# Co-op starting ships

Owner-approved progression, 2026-10-15. The multiplayer ship menus in
`Missions/misn*.vxt` follow the mission's player-controlled production tier.
This is a static per-mission selection, not a persistent campaign unlock system:
a standalone co-op lobby offers the same roster regardless of prior completions.
Production menus, starting resources, offline starting ships and mission scripts
are unchanged.

| Mission | VXT choices, in menu order | Production basis or scenario exception |
| --- | --- | --- |
| 02b, Red Arrival | Pilot (`asuser`) | Start on foot and board the provided empty vehicles. |
| 03, Eagle's Nest | Tank, Scout | Retain the basic co-op kit; `avrec3` has no factory. |
| 04, The Relic Discovered | Tank, Scout, Light Tank | `avrec4` builds `avmuf4`; that factory also exists on the map. |
| 05, An Unexpected Connection | Tank, Scout, Light Tank | `avrec5` builds `avmuf5`. |
| 06, Escape from Mars | Tank, Scout, Light Tank | `avrec6` builds `avmuf6`. |
| 07, Behind Enemy Lines | Tank, Scout, Light Tank, Rocket Tank | The script delivers `avrec7` and `avmu7` after the radar objective. |
| 08, A Nasty Surprise | Tank, Scout, Light Tank, Rocket Tank, Bomber | The player-owned Utah (`avrec8`) builds `avmu8`. |
| 09, Wrangling the Fleeing Herd | Tank, Scout, Light Tank, Rocket Tank, Bomber, Walker | The player starts with the full `avmuf`. |
| 10, The Race is On | Tank, Scout, Light Tank, Rocket Tank, Bomber, Walker | Utah (`avrecy`) can build the full `avmuf`. |
| 11, Bring it Home | Tank, Scout, Light Tank | No friendly production; retain the basic kit and add the Light Tank represented in the authored escort. |
| 12, Flying Solo | Tank, Scout | No friendly production; each player must capture a mission-provided `svfi12`. |
| 13, Total Destruction | Tank, Scout, Light Tank, Rocket Tank, Bomber, Walker | Texas (`avrecy`) can build the full `avmuf`. |
| 14, The Three Beacons | Tank, Scout, Light Tank, Rocket Tank, Bomber, Walker | Texas (`avrecy`) can build the full `avmuf`. |
| 15, United We Fight - United We Die | Tank, Scout, Light Tank, Rocket Tank, Bomber, Walker | The shared Texas (`avrecy`) can build the full `avmuf`. |
| 18, The Ultimate Quake | Tank, Scout, Light Tank, Rocket Tank, Bomber | Owner-specified 2026-10-19: the Walker is not a starting choice. The map starts with the shared Texas (`avrecy2_recycler`) and `avmuf2_factory` on team 1. |

The vehicle records use the existing `odf ,` VXT form:

| Menu name | ODF |
| --- | --- |
| Tank | `avtank` |
| Scout | `avfimp` |
| Light Tank | `avltnk` |
| Rocket Tank | `avrckt` |
| Bomber | `avhraz` |
| Walker | `avwalk` |

Keep the multiplayer Scout (`avfimp`), whose CR health and ammo differ from
`avfigh`. All choices use existing shipped ODFs and loadouts. Red Arrival retains
its full pilot record (`asuser aspilo.des<TAB>anims\aspil.avi NSDF Pilot`);
the short `asuser ,` form does not ready correctly.

`avmuf4` offers Tank, Light Tank and Tug. `avmuf5`/`avmuf6` add Howitzer.
`avmu7` adds Minelayer and Rocket Tank, `avmu8` adds APC and Bomber, and the
full `avmuf` adds Walker. Howitzers, Minelayers, Tugs and APCs remain production
choices rather than starting ships. Colorado's support-team factory in 08 does
not unlock the Walker for the player-owned Utah.

Mission 07's Rocket Tank is a deliberate starting option even though friendly
production arrives later in the story. It does not confer a Soviet disguise:
players still steal their infiltration vehicles. Mission 12 never offers the
key ship in the lobby, so its capture, disguise and shared stealth gates remain
part of play. Mission 14's scripted Fury squad is not a lobby choice.

Walkers are unlocked in 09 but remain slow interception choices; the mission's
existing warning about their speed is retained. Mission 11 keeps its mobile
escort kit for the lava routes. These are mission rosters, not a rule that every
later mission must offer every earlier choice.

Validation covers the per-mission co-op contracts and repository invariants.
The expanded selections still need a native two- and four-player playtest,
including lobby readiness, spawn clearance and the 07/12 infiltration gates.

## CCA (Soviet) campaign

Proposed 2026-11-01, awaiting owner review. The CCA co-op maps (`misns1cr`
through `misns8cr`) offer Soviet ships, adding each mission's production or
briefing-relevant craft to the basic kit.

| Mission | VXT choices, in menu order |
| --- | --- |
| CCA 01, The Golem Ambush | Tank, Scout |
| CCA 02, Precious Cargo | Tank, Scout |
| CCA 03, The Evil Battalion | Tank, Scout, Bomber |
| CCA 04, Io's Bridge | Tank, Scout |
| CCA 05, Controlling the High Ground | Tank, Scout, Light Tank |
| CCA 06, Clear the Path | Tank, Scout, Walker |
| CCA 07, Reclaim our Base | Tank, Scout |
| CCA 08, Punishing the Black Dogs | Tank, Scout, Light Tank, Rocket Tank, Bomber, Walker |

ODFs: Tank `svtank`, Scout `svfimp`, Light Tank `svltnk`, Rocket Tank `svrckt`,
Bomber `svhraz`, Walker `svwalk`.

## Black Dog (Red Odyssey) campaign

Proposed 2026-11-01, awaiting owner review. The Black Dog co-op maps (`bdmisn01cr`
through `bdmisn15cr`) offer the player's own starting ship class (read from team 1
in each map) plus at most one light escort. Black Dog craft use the `bv*` ODFs.
Production menus and mission scripts are unchanged.
| Mission | VXT choices, in menu order | Basis |
| --- | --- | --- |
| BD 01, Close Target Wrecky | Tank, Light Tank | Player starts in a `bvtank` with two `bvltnk` wingmen. |
| BD 02, Hidden Enemy | Tank, Light Tank | Same kit as 01 (`bvtank`, two `bvltnk`, one scavenger). |
| BD 03, Spilt Milk | Tank, Light Tank, Scout | Player `bvtank` with `bvltnk` and `bvraz` wingmen. |
| BD 04, Wolf in Sheep's Clothing | Pilot on foot (`bsuser`) | The mission is an on-foot infiltration: the script perceives the player as team 2, so a Black Dog ship would break the disguise. |
| BD 05, Achilles Heel | Tank (upgraded), Light Tank | Player starts in a `bvtanka` with `bvturr` support. |
| BD 06, Blitzkrieg | Rocket Devastator, Light Tank | The player-controlled force is `bvrdeva`; add a Light Tank escort. |
| BD 07, Terra Incognita | Tank (upgraded), Light Tank | Player starts in a `bvtanka`; the Light Tank represents the authored `bvtank`/`bvrckt` support. |
| BD 08, Hook, Line, and Sinker | Tank (upgraded), Light Tank | Player starts in a `bvtanka` with a `bvltnk` wingman. |
| BD 09, Grand Theft Portal | Stolen Chinese APC (`cvapc`) | The player drives a stolen `cvapc` perceived as team 2; a `bvapc` would break the disguise. |
| BD 10, The Enemy Within | Tank (upgraded), Fighter | Player `bvtanka` with `bvfigha` escorts in the strike force. |
| BD 11, Stranded | Tank, Light Tank | Player `bvtank` with `bvltnk` in the authored escort. |
| BD 12, Meanwhile, Back at the Ranch... | Tank (upgraded), Fighter | Player `bvtanka` with `bvfigha` wingmen. |
| BD 13, Frustrate Their Knavish Tricks | Tank, Light Tank | Player `bvtank` with `bvltnk` wingmen. |
| BD 14, Lifeline | Tank (upgraded), Light Tank | Player `bvtanka` with `bvtank` wingmen. |
| BD 15, The Best Laid Plans... | Tank, Light Tank | Player `bvtank` with `bvltnk` wingmen. |

ODFs: Tank `bvtank`/`bvtanka`, Light Tank `bvltnk`, Scout `bvraz`, Rocket
Devastator `bvrdeva`, Fighter `bvfigha`. Missions 04 (`bsuser` on foot) and
09 (`cvapc`) keep the disguise unit the map starts the player in.
