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
