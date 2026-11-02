# Chinese 03 co-op: Rescue Me (chmisn03)

Shared offline / 2-4 player co-op port of the CRA mission `ch03` (rearm six abandoned howitzers within 13 minutes so they
shell the three Soviet convoys that carry General Fu, find and take his APC, drive it home through an ambush). One
`Missions/chmisn03cr.bzn` and one `Scripts/chmisn03cr.lua` serve both modes. Companion to
[`Scripts/ch03.lua`](../References/Chinese03Source/README.md) (the faithful DLL port underneath) and
[`CCA_COOP_RUNTIME.md`](CCA_COOP_RUNTIME.md) (the shared runtime, first used by `misns1..8`). Pattern:
[`BDMISN01_COOP.md`](BDMISN01_COOP.md) and [`BDMISN11_COOP.md`](BDMISN11_COOP.md).
Status: **host-tested only**; nothing here has run in the game (see "Live checklist").

## Layout

| File | Role |
| --- | --- |
| `Scripts/chmisn03cr.lua` | The faithful port plus marked `-- CR ... >>` / `<<` regions. Outside them it is exactly `ch03.lua` (`Tools/Test-Chmisn03CoopSourceParity.py`). Holds the runtime CONFIG, the native shadows, the per-howitzer seat, the restored content and the Ganymede weather. |
| `Scripts/CRGanymedeSitesCH03.lua`, `Scripts/CREuropaWeather.lua` | Ganymede weather: the generated sites for this map (the four geysers around the starting base) and the shared icy-moon director (no new module). |
| `Missions/chmisn03cr.{bzn,vxt}`, `chmisn03.{hg2,lgt,mat,trn}`, `Config/chmisn03cr.ini`, `Config/crch.ini` | Map and companions (not part of this change). Enemy team 2 was moved to team 5; guests are teams 2-4 at `coop_spawn1..4`. |
| `Tools/Chmisn03Fixture.lua`, `Test-Chmisn03Coop.lua`, `Test-Chmisn03Presentation.lua`, `Test-Chmisn03CoopSourceParity.py`, `Test-Chmisn03CoopContract.py` | Multi-peer fixture and tests (real map coordinates). |

The CR regions, in file order:

| Region | Where | What |
| --- | --- | --- |
| `co-op layer` | file header | The pointer comment. |
| `co-op runtime` | after `local M = NewState()` | The runtime CONFIG (including the weather), the `RESTORED_*` flags, the shadowed natives. |
| `restored content` | after `GotoIfValid`; one call at the end of `Update` | The seat scan, the timer clock, the load re-presentation and the cut content. |
| `co-op user` | `RestoreHowitzerAI` and both howitzer loops; after `M.user = GetPlayerHandle()` | One line each: the seat of the howitzer being looked at, and the frame's scan. |
| `co-op callback` | start of `Start`/`Update`, end of `Update`, `Save`, `Load` | The runtime's per-frame calls. `Update` never returns early, so `AfterUpdate` sits at its end. |
| `co-op callbacks` | end of file | The engine's player callbacks, and `AddObject` forwarded to the runtime. |

## Teams and ownership

| Team | Use |
| --- | --- |
| 1-4 | Humans (host on 1). The authored Chinese side (the start tank, the converted Minelayer, the nav beacon, the factory and armory) stays on team 1: shared, host-run. Extra starting recyclers are disabled. |
| 0 | The six howitzers (`cvartl`, perceived as the Soviets): neutral until a human enters one, then they take that human's team. |
| 5 | The Soviets: the six APCs, their escorts, the ambush and the map's patrols and towers. The body still says team 2; the runtime maps `BuildObject(..., 2, ...)` to team 5 and the `SetPerceivedTeam` shadow maps 2 to 5. Nothing on the map is authored on team 2. |
| 7 | Support (nothing uses it here). |

Only the authority (host, or the offline player) runs the body; guests only present. `SetAIControl(5, true)` runs once at chunk
load. The mission has no `SetAIP`: the enemy is scripted plus the map's own patrols. Starting scrap `SetScrap(1, 0)` becomes
`0 + 10 per guest` on the shared team-1 base (`scrapPerGuest = 10`); `SetPilot(1, 10)` goes to every human team (each human
respawns from its own pool). Respawn rally point: `won_mission`, the starting base.

### Humans as the player: the seat of each howitzer

The DLL's "player" (`M.user = GetPlayerHandle()`) is read in three places, all `M.user == howitzer[i]` / `~= howitzer[i]`
(a human climbs in -> `ch03002`; a ready howitzer is left -> its AI is restored; the one-shot reset when the player boards
again). In co-op `GetPlayerHandle` is the runtime's token, and a one-line CR hook at each of those places sets
`M.user` / `M.lastUser` to "the howitzer if any human is in it, else the token", from a once-per-frame scan of every human's
handle (`CRCoop.AnyPlayerSatisfies`). The comparisons themselves are the body's own and are unchanged: any human on any
team can board any howitzer, several can be aboard at once, and offline it is the single local player.

The body's last test, `GetTeamNum(general) == 1`, is the second player-shaped check: the General's APC is ours when it belongs
to **any** human team (a `GetTeamNum` shadow reports teams 1-4 as 1).

## Scaling and concealed arrivals [owner rules, mission decisions]

Scaled spawns: the ODFs `svtank`, `svhraz` and `svfigh` (the escorts and the ambush). They become *tickets*: the body gets
a negative request id and the unit is built by the runtime on the next frames (two per frame), with the body's later orders
replayed on it (`Defend2(h, apc, 1)`, `Attack(h, general, 1)`, `Attack(h, factory, 1)`). Built directly on team 5, never as
tickets: the **six APCs** (`svapcr` x5, `svapcq` x1): the body holds their handles from the first frame (turn-around test,
the General, `base_fail`), and their spawn points are in the Soviet base, 2.5-4 km from any howitzer.

A new scripted wave (a new frame or a new entry path) is a new scaling event, and the first unit of each event is mirrored by
`min(floor(humans / 2), 2)` extras of the same kind, entry and orders:

| Event | Source | Units | Extras with 4 humans |
| --- | --- | --- | --- |
| Escorts, east / north / west | 2 `svtank` + `svhraz` + `svfigh` per APC, two APCs per path | 8 per route (24) | +2 `svtank` per route (+6) |
| Ambush at `apc_attack` | 6 `svfigh` | 6 | +2 |
| Ambush at `apc_attack_2` | 4 `svfigh` | 4 | +2 |
| Ambush at `factory_attack` | 3 `svtank` + 2 `svfigh` (they attack the factory) | 5 | +2 |

| Humans | Extras per event |
| --- | --- |
| 1 (offline) | 0 |
| 2 or 3 | 1 |
| 4 | 2 |

Cap: at most **40** live scaled units (`liveCap`; the runtime default is 12): 24 escorts and their extras are about 30 at four
humans, the 15-unit ambush adds to that only while the escorts live. Extras are the only requests dropped for the cap, primaries
always spawn.

No pop-in: a ticket is never built within **250 m** of any human (`safeRadius = 250`; the runtime default is 460 m). The
authored ambush spawns are 300-360 m from `trigger_1`, where the General's driver is when the ambush starts: a 460 m rule
would divert it every time. If a human is near the authored entry, the next hidden approach in `fallbackEntries` is used (the
three map-edge exits `east_fail`, `north_fail`, `west_fail`, then the three `*_defend` points at the Soviet base), else the
request waits (saved in `M.crcca`, so a save/load neither loses nor duplicates it). Reinforcements stop for good when the
mission is won or lost (`endedFlags = {"won", "lost"}`) or a result is queued.

## Humans' result, timer, win and loss

- Win: the General's APC taken by any human team (objective 2), driven to `won_mission` (30 m) -> `SucceedMission(+1 s,
  "ch03win.des")`. `wonFlags = {"won"}`: a later failure request (for example out of lives) is ignored.
- Loss, the body's own: the 13:00 timer runs out (`ch03lsea`), the factory is destroyed (`ch03lsee`), the General's APC is
  destroyed (`ch03008` -> `ch03lsec`), the uncaptured General's APC is back at `base_fail` after 120 s (`ch03009` ->
  `ch03lsed`). Out of lives (every human out): `ch03lsea.des` for everyone. Leader departs: every guest fails.
- The timer: the map runs `MultSTMission`, which restarts the cockpit timer upward every frame, so the engine never counts
  the 13 minutes down. The host keeps the clock itself (`Restored.TimerStart/TimerLeft`), every peer shows the host's timer
  (`StartCockpitTimer` / `StopCockpitTimer` / `HideCockpitTimer` travel through the stream), and a load re-shows the remaining time.
- The gas explosions (`xgasxpl` at the exits, five per route 5 s apart) are a local effect: the host makes its own, every guest
  makes its own from the `CH03Boom` op (like the portal blast of `bdmisn11`).

## Cinematics: none

`Chinese03Mission.cpp` has no camera calls (`cameraReady` / `cameraComplete` are declared and never used). There is no cutscene to
share or to make unskippable, and the CR layer wraps no camera native. The runtime's camera stream is still live for the
presentation protocol tests.

## Restored content [owner decision 2026-11-01]

Each item is behind a `RESTORED_*` flag at the top of the runtime region.

| Flag | Source | What is restored |
| --- | --- | --- |
| `RESTORED_FACTORY_SCAVENGERS` | the four commented-out `cvscav` builds + `Goto(h, "factory_path", 1)` next to the factory | The four Chinese scavengers arrive with the factory and the armory (team 1, host-built, send to `factory_path`). The factory comes with 200 scrap and no way to gather more; the scavengers are what the block was drawn for. |
| `RESTORED_TIMEOUT_LINE` | unused voice line `ch03007.wav` ("This is unthinkable! Your feeble ineptitude sickens me, Major. You will be left to rot on this barren rock...") | Played when the 13:00 timer runs out, before the `ch03lsea.des` debrief (which then falls one second after the line ends, as the other losses do). The source fails this loss in silence. |
| `RESTORED_ESCAPE_FAIL` | unused map paths `east_fail`, `north_fail`, `west_fail` and unused debrief `ch03lseb.des` ("The General has been taken to the launch facility! He is already well on his way to Russia!") | Each fail point is the end of one APC route (34 / 47 / 57 m from the last point of `east_path` / `north_path` / `west_path`, 300+ m beyond the turn-around exits). The General's APC, still Soviet, within 75 m of its route's fail point has escaped: `ch03007` then `ch03lseb.des`. A backstop only: the pair turns around at the exits, so it needs a convoy that was never turned. |

Dead source items that are **not** restored:

| Item | Decision |
| --- | --- |
| `lose2Sound` -> `ch03lsed` branch | Nothing ever sets it. `ch03lsed` is already the base-return loss (`sound9`); the branch stays as in the port. |
| `objective3Complete`, `winSound`, `cameraReady/Complete`, `openingSound`'s unused twins | Never read; kept in the saved table by the port. |
| The cut `obj->curPilot = 0;//*(PrjID*)"cspilo\0"` pilot assignment | Engine-only (`AiProcess::Attach`); the port already substitutes `SetPilotClass(h, nil)` + `Stop`. |

Authored map content the script never uses, documented rather than guessed:

- `edge_path`: the playable box (the weather reads it as bounds).
- `patrol_path_1`, `patrol_path_2`, `patrol_path_3`: routes for the map's own Soviet patrols (`patrol_1_*`, `patrol_2_*`, `patrol_3_*`);
  no code, active or cut, names them.
- `apc_attack_2_path`: a two-point path from `apc_attack_2` towards the base; the ambush there attacks the General directly.
- `mine_path`: a 133-point route near the start; no code names it (probably the Minelayer demonstration of the original map).

Unused voice lines: the mission's catalogue is `ch03001`..`ch03009`; the body plays all but `ch03007`, which the layer slots in
(above). Every other `chNN` line the repository carries that no script plays (`ch01010`, `ch04004`, `ch04005`, `ch05008`,
`ch06007`, `ch08001..009`) is a line of its own mission's story; none fits Rescue Me. Every line has a subtitle in `Text/`
(`Test-Chmisn03CoopContract.py` asserts the full nine).

## Stock bugs and co-op fixes in the CR layer (the faithful body is untouched)

- One player: see "Humans as the player" (a fixed single `GetPlayerHandle()` would ignore every human but the host).
- `GetTeamNum(general) == 1` only recognised team 1; humans are teams 1-4, so a guest who took the General's APC never completed
  objective 2. The shadow reports teams 1-4 as 1.
- The engine timer (see "Humans' result"). `GetCockpitTimer() <= 0` could never fire on the real map.
- The Soviet team literal 2 (builds, `SetPerceivedTeam`, `SetPilot`, `SetScrap`) is team 5 on the co-op map.
- Objective rebuilds are coalesced by the runtime (a rebuild identical to the last published one is dropped); a load shows the
  list, the unfinished howitzer markers, the timer and the beacon name again.
- The howitzers' `SetObjectiveOn` / `SetObjectiveOff` and the beacon's `SetObjectiveName` travel to guests by label
  (`howitzer_1..6`, the beacon gets a runtime label).
- Audio: every line the body names has a subtitle in `Text/`; the runtime queues a line that starts while another talks.
- Orders on tickets: `Defend2` and `Attack` are recorded on a waiting ticket and replayed on the real unit (the same on the extras);
  the body's checks on tickets (`IsValid`) answer "valid".
- The body already carries its own documented port fixes (`ch03.lua` header comments: the `turnedAround` array overflow, the
  AI restoration after the repair phase, the destroyed-APC distance guard, the loss-sound one-shot, `not won` on the escape check).

## Weather: Ganymede

An icy, airless Jovian moon. `CREuropaWeather` (no new module) with `CRGanymedeSitesCH03`: orbit lighting
(`Environment.Init{lightingMode="orbit", orbit={period=1800, startHour=-40}}`, as `bdmisn01cr`), the cryovolcanic plume,
quake and Jupiter-surge director, networked through the runtime's ops (`EuropaState`, `EuropaPlume`, `EuropaQuake`,
`EuropaSurge`): seeded timeline from the host, host-chosen events over the ordered stream, `Save`/`Load` state,
`AnnounceState`. The generated sites carry the four geysers around the starting base (`eggeizr17/10/11/12_geyser`) and the
frost clusters. If the weather module or the sites module is missing, or any weather call errors, the mission runs without
weather and logs once. The director never damages and never touches perception.

Beats (host/offline only, each once, tied to the story; a site list without vents skips only the plumes):

| Story moment | Beat |
| --- | --- |
| Rearming | rung 1 (quiescent) |
| Three howitzers ready | rung 2 |
| All six ready, the convoys leave the Soviet base (`objective1Complete`) | rung 3, a plume at vent 1, a 3 s ice quake (0.3) |
| The first bombardment (`turnedAround`) | rung 4 and a 6 s surge (0.8) |
| The General is ours (`objective2Complete`) | rung 3 |
| The ambush closes in (`trigger1Done`) | rung 4, a plume at vent 2, a 3 s quake (0.35) |
| Won or lost | release the forced level, back to rung 1 |

## Tests

```sh
lua5.1 Tools/Test-Chmisn03Coop.lua            # offline == faithful, 1-4 peers, seats, timer, scaling, 250 m, fallback, restored content, results, weather
lua5.1 Tools/Test-Chmisn03Presentation.lua    # E/A/C protocol on a guest, the timer and the gas explosion op
python Tools/Test-Chmisn03CoopSourceParity.py # chmisn03cr.lua minus CR regions == ch03.lua
python Tools/Test-Chmisn03CoopContract.py     # labels/paths/teams/vents/audio in chmisn03cr.bzn (skips with a message if the map is absent; ini/vxt only when present)
```

## Inferences and open questions

- **Authored craft and guests.** The six howitzers are map-authored. Redux sends an authored object's handle as nil unless the
  OpenShim label-id hooks are installed (see `BDMISN04_COOP.md`). Without them a guest sitting in one is invisible to the host and
  `CRCoop` keeps the session "not ready" (the body pauses; it does not crash). With the hooks the label travels as the id and
  everything above holds. The tests cover both (`nilAuthoredHandles` in the fixture). This is the first thing to confirm live.
- That a neutral howitzer takes the team of the human who enters it, and keeps it after they leave (so the AI howitzer shoots for
  that human's side), is the engine's behaviour the body assumes; unverified here.
- `ch03007` for the timeout and the escape is an inference from its text ("left to rot on this barren rock") and from the
  missing voice on the timeout loss. `ch03lseb.des` for the escape is an inference from its text and from the unused fail paths
  at the ends of the three APC routes.
- `safeRadius = 250` and `liveCap = 40` are CR inferences (see "Scaling"). The fallback order is a guess: the map-edge exits first
  because the ambush fallback matters most, the Soviet base last.
- Scaling is per (frame, entry path), a CR inference: a route's two APCs share one event, so a route's escorts get one set of extras.
- The Soviet APC pairs and the towers are authored on team 5; their AI is the map's and the engine's.
- The APCs are built directly and may pop in if a human is parked at the Soviet base when the last howitzer is rearmed.
- `GetCurHealth(h) > 400` and `GetCurAmmo(h) > 400` are the body's absolute thresholds; the Minelayer repair/reload rates are
  the engine's. Several humans can share the repair work.
- The out-of-lives path is not exercised by the host tests (leader departure is).

## Live checklist (unrun)

1. Opening: the briefing `ch03001` plays once on every peer, the 13:00 timer and the six howitzer markers appear for everyone.
2. A guest (team 2-4) enters a howitzer: `ch03002` once; the marker disappears for everyone when it is repaired and rearmed; the
   guest leaves, the howitzer fires on its own (AI restored) once the convoys come.
3. Rearm all six: the timer stops everywhere, the "CCA Base" beacon appears for everyone, the six convoys leave the Soviet base.
4. Each route turns at its exit: `ch03003/4/5`, five gas explosions on every peer, the howitzer pairs shoot their APC pair.
5. A guest takes the General's APC: `ch03006`, the third objective for everyone.
6. Drive to `trigger_1`: the ambush arrives from the authored points (or the map edge when watched); nothing pops in view.
7. Reach `won_mission`: one shared victory. Lose the General / the factory / the time: one shared failure with the right debrief,
   `ch03007` before the timeout and the escape debriefs.
8. Four scavengers arrive with the factory at 8:00 and go to work.
9. Save during the rearming and after the convoys leave, load: objectives, markers, timer, beacon name are back; no second convoy.
10. Ganymede sky and plumes render on guests; no weather error in the log.
