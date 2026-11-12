# Chinese 04 co-op: From Out There Somewhere (chmisn04)

Shared offline / 2-4 player co-op port of Chinese mission 4 (a stealth raid on Ganymede: the Chinese Major's fighter
follows six safe nav beacons through a Soviet minefield, slips cloaked into the Soviet scrap silo, identifies it, and
retreats through the portal as the base is overrun). One `Missions/ch04cr.bzn` and one `Scripts/ch04cr.lua` serve
both modes. Companion to the faithful DLL port underneath (`Scripts/ch04.lua`, [`CH04_LUA_PORT.md`](CH04_LUA_PORT.md),
[`References/Chinese04Source/`](../References/Chinese04Source/)) and to [`CCA_COOP_RUNTIME.md`](CCA_COOP_RUNTIME.md) (the shared
runtime). Pattern: [`BDMISN04_COOP.md`](BDMISN04_COOP.md), [`BDMISN09_COOP.md`](BDMISN09_COOP.md).
Status: **host-tested only**; nothing here has run in the game (see "Live checklist").

## Layout

| File | Role |
| --- | --- |
| `Scripts/ch04cr.lua` | The faithful port plus marked `-- CR ... >>` / `<<` regions. Outside them it is exactly `ch04.lua` (`Tools/Test-Chmisn04CoopSourceParity.py`): the body is **not edited at all**, the runtime's per-frame calls wrap its callbacks at the end of the file. Holds the runtime CONFIG, the native shadows and the restorations. |
| `Scripts/CREuropaWeather.lua`, `Scripts/CRGanymedeSitesCH04.lua` | The Ganymede weather (the Europa director, no new module) and the generated sites for this map (two vents: the base geyser beside the portal and the Soviet geyser beside their factory). |
| `Missions/ch04cr.{bzn,vxt}`, `chmisn04.{hg2,lgt,mat,trn}` | Map and companions (not part of this change). The start file offers the upgraded fighter `cvfighe` and the tank `cvtnk` ([`COOP_STARTING_UNITS.md`](COOP_STARTING_UNITS.md)); the map start is the host's `cvfighe` (`player`). The Soviet side is team 5, the map's own enemy team 2 having been moved. |
| `Tools/Chmisn04Fixture.lua`, `Test-Chmisn04Coop.lua`, `Test-Chmisn04Presentation.lua`, `Test-Chmisn04CoopSourceParity.py`, `Test-Chmisn04CoopContract.py` | Multi-peer fixture and tests (real map coordinates). `Test-Chinese04.lua` / `Test-Chinese04SourceParity.py` still cover the faithful port, unchanged. |

## Teams and ownership

| Team | Use |
| --- | --- |
| 1-4 | Humans (host on 1). The Chinese side the body builds on team 1 (the nav beacons) stays on team 1: shared, host-run. The map's own `factory` (a `cvmuf`) and `portal` (`cbport`) are team 1 buildings *perceived* as Soviet (perceived team 5); the body heals both every frame. Extra starting recyclers are disabled (the mission has no recycler). |
| 5 | The Soviets: the silo, the factory, the 25 parked craft (`empty_N`), the four turret tanks (`turret_N`), the barracks, towers, power plants and mines, the 25 pilots, the two scramble fighters, the 12 chase units and the 6 portal guards. The body still says team 2; the runtime maps `BuildObject(..., 2, ...)` to team 5. |
| 7 | Support (nothing uses it here). |

Only the authority (host, or the offline player) runs the body; guests only present. `SetAIControl(5, true)` runs once at
chunk load. The mission has no `SetAIP`. `SetScrap(1, 0)` stays 0 for everyone (`scrapPerGuest = 0`: the mission is about the
enemy's scrap) and `SetPilot(1, 10)` goes to every human team. Respawn rally point: the `factory`, 63 m from the portal.

## Humans as the player

The DLL keeps **one** handle for "the player" (`M.user`) and reads it in a dozen places. In the CR layer `GetPlayerHandle()` is the
runtime's token for the humans (as in `bd09cr`; offline too, where the humans are the one player), valid while any human lives.
Each use of the token then means what keeps a stealth mission fair for several humans, without an edit of the body:

| Body call on the player | Co-op meaning |
| --- | --- |
| `GetDistance(user, X) < r` (every nav, `trigger_1` within 70, silo within 200) | the **nearest** human. The retreat test `GetDistance(user, portal) < 100` is the exception (`farthestTargets = { "portal" }`): **every** human must be near the portal. A human waiting to respawn counts as far, and respawns at the factory beside the portal. |
| `IsCloaked(user)` | at the alarm decision (the end of the alarm shot): **every** human is cloaked. Afterwards (core failure): **any** cloak that is still up. |
| `Decloak(user)`, `EnableCloaking(user, false)` | every human. |
| `SetPerceivedTeam(user, 2)` / `(user, 1)` | every human, on every peer (`CH4Disguise`): team 2 is the Soviets (5), team 1 is a reveal (each human back on their own team). |
| `Hide(user)` | every human, on every peer (`CH4Hide`). |
| `RestoreHealth(user)` | every human (`AddHealth(token)`). |
| `Attack(unit, user)` | the human **nearest to that unit**. A unit still waiting for a concealed entry keeps the order; it is aimed the moment it exists. |
| `SetUserTarget(nav)` | the local target of the host and a replicated objective marker for every human (the previous marker goes out). |
| `IsInfo(GetOdf(silo))` | the local info panel: a guest's inspection reaches the host as a short `I` packet every 0.25 s while the panel shows `sbsiloa`; the host honours a report for one second (the `bd04cr` / `misn08cr` pattern). |

The player-handle-change logic of the body (`user ~= olduser`: decloak the abandoned ship, retarget the attack groups) cannot fire with
a token. The CR layer keeps its intent where it matters: whenever the **set of human craft changes** while the base is alarmed (a human
died, respawned or changed craft) every live attacker is ordered again at the human nearest to it, and the portal guards, which the body
never orders, start hunting then, exactly as the body's player change does for them.

Every Tank option can cloak (`cloakAllowed = "True"` in `cvtnk.odf`); a human who does not cloak exposes the group at the alarm decision,
by design (see "Stealth rules").

### Stealth rules

- The body decides **once**, when the alarm shot ends: not all cloaked -> the base attacks at once and every human is revealed; all cloaked ->
  the base stays calm until the silo is identified, when the core failure takes every cloak down and the same attack starts (`ch04002`,
  `ch04004`, `ch04003`).
- Restored (below): an **uncloaked** human within 400 m of `trigger_1` sets the alarm off early, so the unused objective "Remember to cloak!" is true.
  The pit entrance (`nav_6`) is 236 m from `trigger_1`: cloak before it.

## Scaling and concealed arrivals [owner rules, mission decisions]

Scaled spawns: the ODFs `svfigha` (chase_1 and chase_3), `svtanka` (chase_2) and `svfigh` (the portal guards): the pursuit. They become *tickets*:
the body gets a negative request id and the unit is built by the runtime on the next frames, with the body's later orders replayed on it.
Not scaled: the 25 pilots (`sspilo`), the two scramble fighters (`fighter_1`, `fighter_2`, built directly: a set piece at the silo, same
`svfigh` ODF as the portal guards), the nav beacons (`cpcamr`) and the stand-in craft.

Events: **a new frame or a new entry path is a new scaling event** (the body builds the three chase groups unit by unit, interleaved: an event is the
first unit of an entry path in a frame), and the first scaled unit of an event is mirrored by `min(floor(humans / 2), 2)` extras of the same kind, entry and orders.

| Humans | Extras per group |
| --- | --- |
| 1 (offline) | 0 |
| 2 or 3 | 1 |
| 4 | 2 |

The groups: 4 `svfigha` at `chase_1`, 4 `svtanka` at `chase_2`, 4 `svfigha` at `chase_3`, 6 `svfigh` at `portal_units` (so 18 units, 26 with four humans).
Chase units attack the human nearest to them; the portal guards get no order, as in the body. Cap: at most **26** live scaled units (`liveCap`;
the runtime default is 12); extras are the only requests dropped for the cap.

No pop-in: a ticket is never built within 460 m of any human. If a human is near the authored entry, the next hidden Soviet approach in `fallbackEntries`
is used (`chase_1`, `chase_3`, `chase_2`, `portal_units`, first that is clear), else the request waits (saved in `M.crcca`, so a save/load neither loses nor
duplicates it). Reinforcements stop for good once the mission is won or lost (`endedFlags = { "won", "lost" }`).

## Results

- Win: unchanged. The retreat is complete when every human is within 100 m of the portal; the end film plays, two seconds later the portal closes and
  `SucceedMission(..., "ch04win.des")` is issued once (the runtime holds the result until every guest acknowledged the preceding events). `wonFlags = { "won" }`:
  a loss after the win is ignored.
- Loss: the 130-second route expires (`ch04lsea.des`, voice `ch04006`) or the 135-second retreat expires (`ch04lseb.des`, voice `ch04005`, restored) -> one
  `FailMission` for everyone. Out of lives (every human): `ch04lose.des` (the shipped debrief the body never used). The leader departing fails every guest.
- The body's `lost` flag (unused in the DLL) is set on a failure and `won` on the victory: the runtime and the weather read them.

## Cinematics are shared and unskippable in a network game [owner]

Three shots. The opening flight over the silo (`camera_start`) and the alarm shot at the Soviet factory (`camera_alarm`) are driven by `CameraPath` every frame,
so the runtime's camera stream carries them to every guest; `CameraCancelled` is false in a network game, offline both stay skippable. A skip on one machine releases
only that machine's camera (the runtime's rule); the host's opening then ends at its flight time plus a margin (`CAMERA_ETA`, recomputed from the map by
the contract test); the alarm shot ends on its own five-second timer.

The end film is a `CameraPathDir`, which the runtime's stream does not carry. The host's first `CameraPathDir` publishes `CH4Shot(path, height, speed)`; every
peer opens its own camera and runs the shot from its update hook, and a change of speed (the body's hold at the end of the path) is published again. The body has no
cancellation and no `CameraFinish` for it, and the CR layer adds neither (the result ends the mission). The portal opens inward and closes on every peer by label
(`CH4Portal`): `PortalIn` / `DeactivatePortal` are per-peer animation calls. A save during a film cannot resume it (the cameras are gone): the opening and alarm shots
then report arrival at once, the end film opens a fresh camera and runs again from the start of its path.

## Restored content [owner decision 2026-11-01]

Cut-content restorations live only in the CR layer, apply offline and in co-op, and each has a flag (`RESTORED_*` at the top of the runtime region of
`ch04cr.lua`).

| Restoration | Cut block it comes from | Status in this map |
| --- | --- | --- |
| `RESTORED_UNCLOAKED_DETECTION` | `if(dist <= 70 \|\| ((!insideCloakedShip \|\| !isCloaked(user)) && dist <= 400) \|\| target_silo_inspected)` (the active line drops the middle term), and the shipped objective `ch04004.otf` "Remember to cloak!", which no script ever shows | An uncloaked human within 400 m of `trigger_1` (while the silo is still unidentified) sets the alarm off. The objective is on the list from the first nav until the base is alarmed or the silo is identified. |
| `RESTORED_SILO_BEACON` | `navPoints[0] = BuildObject("apcamr", 1, "nav_silo"); SetName(navPoints[0], "Silo"); SetUserTarget(navPoints[0]);` and `//SetUserTarget(target_silo)` | The `nav_silo` camera pod, named "Silo", is built when the route ends and is the target (a network game marks it for every human); it goes out when the silo is identified. The silo's own objective marker is the body's. |
| `RESTORED_ALARM_PILOTS` | The block of nine `Retreat(BuildObject("sspilo", 2, temp), temp)` for `empty_15`, `empty_16` and `empty_18`..`empty_24` | The nine craft the body gives no pilot get one when the alarm shot ends, beside the sixteen the body spawns. They stand at their own craft (no `pilot_N` path exists for them). |
| `RESTORED_FAKE_CRAFT` | `//fakePlayer = BuildObject((char *)&gameObj->GetClass()->cfg, 1, user);` ... `//o2->AddHealth(...)` ... `//Goto(fakePlayer, "auto_end");` | The player is hidden for the end film (`Hide`), so a copy of each human's craft, on team 1 with the human's health, flies the `auto_end` path the film follows. The camera's own arrival still ends the film (the cut `GetCurrentCommand(fakePlayer)` test stays cut). |
| `RESTORED_VOICE_LINES` | see below | see below |

Unused shipped voice lines [owner decision 2026-11-01]: the wavs and `Text/ch04004.txt`, `ch04005.txt` ship with the game (`Config/durations.csv` lists both)
but the DLL never plays them. They play through the CR layer (`AudioMessage`: replicated to co-op guests, queued behind a line still playing), are latched
in `M.crcca.r` (kept by Save/Load) where they fire once, and sit behind `RESTORED_VOICE_LINES`.

| Line | Transcript | Trigger | Why it fits |
| --- | --- | --- | --- |
| `ch04004.wav` | "As we thought, they are stockpiling scrap, now get back to base." | The frame the silo is identified (state `MS_WAITFORSOUND2`), once; it queues behind the core-failure line `ch04002` and ahead of the alarm `ch04003` and the overrun `ch04008` | Command's answer to the silo report, ahead of "We're being overrun, retreat to the portal". |
| `ch04005.wav` | "What are you trying to do, Major? You are a most weak and feeble leader. You will be replaced." | With the retreat-timeout debrief `ch04lseb.des` ("You must be far quicker to obey orders..."), as `ch04006` goes with `ch04lsea.des` | The scolding for failing to obey the order to retreat. |

Skipped, with the reason:

- The forced core failure inside the early-alarm block (`if(insideCloakedShip) { if(isCloaked(user)) { ch04002; Decloak } enableCloaking(user, FALSE); }`): it would
  take the cloak down at the alarm, which contradicts the surviving design (a cloaked player stays unseen until the silo is identified).
- The three disabled `ch04003` plays (before the alarm, in the alarm shot, in the approach): the line plays at the pursuit as shipped.
- `// RemoveObject(navPoints[0])` before `nav_base`: the first nav is removed when the route ends.
- The 45-second `stateTimer` after the identification, which the body sets and never reads (`intentionally unused in source`), and the unused members `lost` /
  `fakePlayer` as state (`lost` now records a failure).

Authored paths the script never uses (documented, not wired): `edge_path` (the playable box the weather uses), `outer_limits` (the map boundary), `camera_end`
(a one-point path of the removed end shot; the film follows `auto_end`) and `path_3` (a two-point path of the Soviet base no unit is sent along). `nav_silo` is the
restored beacon's position; `pilot_15` etc. do not exist (the nine restored pilots stand at their craft).

## Stock bugs fixed in the CR layer (the faithful body is untouched)

- **The 130-second route never expires on this map's clock.** The map's mission class is `MultSTMission`, which restarts the cockpit timer upward every frame, so
  `GetCockpitTimer() < 1` is never true: the navigation-skills line `ch04006` and the `ch04lsea.des` failure never happen, in co-op *and* offline on the same map.
  The CR layer shadows `StartCockpitTimer` / `GetCockpitTimer` / `HideCockpitTimer`: the host counts the 130 s itself (saved with the mission state) and shows the same timer on every peer.
  The faithful test shows the stock body never sees the zero under this clock.
- One hidden, disguised, healed, cloak-checked and decloaked player: see "Humans as the player" (a stock single handle would ignore every human but one).
- The attack groups left on a dead or replaced handle: see above.
- The portal opens and closes on every peer, not only the host; the end film runs on every peer.
- The silo inspection of a guest (`IsInfo` is local UI state): relayed.
- A save in the middle of a film: see "Cinematics".
- Objective rebuilds are coalesced by the runtime (a rebuild identical to the last published list is dropped).
- Audio: every line the body or the CR layer names has a subtitle in `Text/` (`Test-Chmisn04CoopContract.py`); `audioSubstitute` is empty. The `.des` debriefs ship with the game.
- The body already carries its own documented port fixes (`CH04_LUA_PORT.md`: guarded health/portal/player dereferences, invalid-handle distances, the `IsInfo` ODF adaptation,
  the end-film `arrived` initialisation) and preserved quirks (the single stateless alarm decision, the unordered portal guards). None is changed here.

## Weather: Ganymede

`Environment.Init` in orbit mode (the Jovian sun path, as for the Black Dog maps) plus the **Europa director** (`CREuropaWeather`: Ganymede is also an airless icy moon of Jupiter)
with `CRGanymedeSitesCH04`, networked through the runtime (seeded timeline from the host, host-chosen quakes and surges over the ordered stream, `Save`/`Load` state,
`AnnounceState`) and bound to the sensor service (`Environment.BindWeatherSensors("Ganymede", ...)`). If the weather module or the sites module is missing, or any weather call
errors, the mission runs without weather and logs once. Beats (host/offline only, each once, tied to the story): the first nav -> level 2; the alarm shot -> level 3 and a radiation surge;
the silo identified -> level 4, a quake, a surge and a plume at the first vent (the map has two); the portal opens -> a quake; victory -> `ReleaseForcedLevel` and calm; a loss -> level 4.
The director never damages.

## Tests

```sh
lua5.1 Tools/Test-Chmisn04Coop.lua            # offline == faithful, 1-4 peers, stealth rules, relay, timer, scaling, 460 m, retreat, end film, saves, weather
lua5.1 Tools/Test-Chmisn04Presentation.lua    # E/A/C protocol and this mission's four ops on a guest
python Tools/Test-Chmisn04CoopSourceParity.py # ch04cr.lua minus CR regions == ch04.lua
python Tools/Test-Chmisn04CoopContract.py     # labels/paths/teams/start file in ch04cr.bzn (skips with a message if the map is absent)
lua5.1 Tools/Test-Chinese04.lua && python Tools/Test-Chinese04SourceParity.py   # the faithful port, unchanged
```

The contract test checks `Missions/ch04cr.vxt`, `Config/ch04cr.ini`, `Config/crch.ini` and the `.mpdes` only when they are present.

## Inferences and open questions

- **Authored objects and guests.** The silo, the Soviet factory (camera subjects, markers) and the portal are map-authored. Redux sends an authored object's handle as nil
  unless the OpenShim label-id hooks are installed (`AGENT_KNOWLEDGE_BASE.md` 3.3); the labels travel instead (`target_silo`, `cca_factory`, `portal`). The tests cover the
  label path. A guest who inspects the silo (`IsInfo`) needs nothing authored.
- `GetOdf` of the silo is read as `sbsiloa` and `IsInfo("sbsiloa")` as "the info panel shows a silo" (the body's own adaptation); other `sbsiloa` objects, if the map has
  any, would count as well.
- Cloaking: that `cloakAllowed` fighters and tanks keep the cloak into the alarm decision, and that a perceived-team-5 human is ignored by the Soviet AI until the body reveals
  it, is the DLL's design, not tested here. The "every human cloaked at the decision, any cloak at the failure" split is a CR inference.
- The 400 m detection and the nine pilots are restorations of cut code whose reason for being cut is unknown (a difficulty or a placement problem are possible); both are one
  flag each.
- The stand-in craft is built at the human's own position (`BuildObject(odf, 1, human)`, as the cut code did): two craft overlap for a frame. If that throws either craft, turn
  `RESTORED_FAKE_CRAFT` off.
- Scaling is per (frame, entry path), a CR inference; `liveCap = 26` so four humans' extras fit the pursuit.
- The route countdown is host-counted and shown with the engine's own `StartCockpitTimer` on every peer; if the HUD keeps counting upward (the MultSTMission override) the number on
  screen is wrong while the logic is right.
- Out of lives is not exercised by the host tests (leader departure is).

## Live checklist (unrun)

1. Two clients, DX11: the opening flight over the silo is the same on both (cameras balanced) and cannot be skipped; ch04001 plays once.
2. Both cloak, follow the six navs: one shared countdown, the markers follow the host's target; the Pit Entrance is named; both are perceived as Soviets afterwards.
3. "Remember to cloak!" is on both lists; an uncloaked guest within 400 m of the alarm trigger starts the alarm: the alarm shot at the Soviet factory is the same on both, nine more pilots run for their craft.
4. All cloaked: nothing happens until a guest identifies the silo from its own info panel: ch04002, ch04004, ch04003, then the twelve chasers and six portal guards arrive from the far side of the map (none visible at spawn); the portal opens on both screens.
5. Retreat: the extraction nav; with one human far from the portal nothing happens; everyone near it: the end film runs on both with the stand-in craft flying the path, then one shared victory.
6. Let either countdown run out: one shared failure with the right line (ch04006 route, ch04005 retreat).
7. A human dying mid-mission respawns at the factory, is disguised again, and the attackers aim at the nearest human.
8. The Ganymede sky renders on guests (orbit lighting, quake shakes at the identification), no weather error in the log.
