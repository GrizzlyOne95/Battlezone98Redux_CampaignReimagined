# Chinese 02 co-op: Protection (chmisn02)

Shared offline / 2-4 player co-op port of the Chinese mission `ch02` (the Red Army base on Ganymede must be defended
while the engineers work on the Pegasus relic, the Russian raids keep coming, a defecting Russian walker has to be
brought in, and General Fu's three-APC convoy must reach the hangar alive). One `Missions/chmisn02cr.bzn` and one
`Scripts/chmisn02cr.lua` serve both modes. Companion to [`Scripts/ch02.lua`](../References/Chinese02Source/README.md)
(the faithful DLL port underneath) and [`CCA_COOP_RUNTIME.md`](CCA_COOP_RUNTIME.md) (the shared runtime). Pattern:
[`BDMISN01_COOP.md`](BDMISN01_COOP.md), [`BDMISN14_COOP.md`](BDMISN14_COOP.md).
Status: **host-tested only**; nothing here has run in the game (see "Live checklist").

## Layout

| File | Role |
| --- | --- |
| `Scripts/chmisn02cr.lua` | The faithful port plus marked `-- CR ... >>` / `<<` regions. Outside them it is exactly `ch02.lua` (`Tools/Test-Chmisn02CoopSourceParity.py`). Holds the runtime CONFIG, the native shadows, the co-op fixes, the restorations and the Ganymede weather. The body is not edited at all. |
| `Scripts/CRGanymedeSitesCH02.lua`, `Scripts/CREuropaWeather.lua` | Ganymede weather: the generated sites for this map (seven vents, the first beside the armoury) and the shared icy-moon director (no new module). |
| `Missions/chmisn02cr.{bzn,vxt}`, `chmisn02.{hg2,lgt,mat,trn}`, `Config/chmisn02cr.ini`, `Config/crch.ini` | Map and companions (not part of this change). The enemy was moved from team 2 to team 5 on the map; the guests start at the `coop_spawn1..4` buoys on teams 1-4. |
| `Tools/Chmisn02Fixture.lua`, `Test-Chmisn02Coop.lua`, `Test-Chmisn02Presentation.lua`, `Test-Chmisn02CoopSourceParity.py`, `Test-Chmisn02CoopContract.py` | Multi-peer fixture and tests (real map coordinates). `Tools/test_ch02.py` still covers the faithful port, unchanged. |

The CR regions, in file order:

| Region | Where | What |
| --- | --- | --- |
| `co-op layer` | file header | The pointer comment. |
| `co-op runtime` | after `local M = NewState()` | The `RESTORED_*` flags, the runtime CONFIG (including the weather), the shadowed natives, the ticket-scaled `BuildObject`, the `Goto` route restoration, the shot fallback. |
| `co-op fixes` | after `GotoLiveApc` | The saved objective list, the load fix, the cut ambushes and the extra voice lines (`Restored`). |
| `co-op callbacks` | end of file | The runtime's per-frame calls wrapped around the body's `Start/AddObject/Update/Save/Load`, and the engine's player callbacks. |

## Teams and ownership

| Team | Use |
| --- | --- |
| 1-4 | Humans (host on 1). The authored Chinese side (recycler `recycler`, hangar `hanger`, comm tower, armoury, power plants, turrets, factory) stays on team 1: shared, host-run. The convoy (`cvapcb` x3, `cvfighc` x6) and the intercept nav are built on team 1. |
| 5 | The Soviets (CCA): the authored `attack_3_*`, `attack_5_*` groups and every wave unit. The body still says team 2; the runtime maps `BuildObject(..., 2, ...)` to team 5. Nothing on the map is authored on team 2. |
| 0 | The defecting walker is built neutral (as in the source) and switched to team 1 when it reaches the base. Its perceived team is 1 while it walks, so the raiders hunt it. |
| 7 | Support (nothing uses it here). |

Only the authority (host, or the offline player) runs the body; guests only present. `SetAIControl(5, true)` runs once
at chunk load. This mission has no `SetAIP`: the enemy is entirely scripted. Starting scrap `SetScrap(1, 30)` becomes
`30 + 10 per guest` on the shared team-1 base (`scrapPerGuest = 10`); `SetPilot(1, 10)` is repeated for every human
team so each guest has its own 10 pilots. Respawn rally point: the Recycler (`rallyPoints = {[0]="recycler"}`).
Starting craft: `Docs/COOP_STARTING_UNITS.md` (Tank, Fighter).

The body's `M.user = GetPlayerHandle()` is read nowhere except as `getBase`'s last-resort target when no base building
is left. In co-op it is the runtime's nearest-human token. That fallback cannot be reached while the mission runs: a
dead hangar is a loss (`M.lost`), which ends the spawns.

## Scaling and concealed arrivals [owner rules, mission decisions]

Scaled spawns: every Soviet ODF the body builds on team 2 (`svfigh`, `svtank`, `svwalk`, `svhraz`, `svartl`, `svltnk`,
`svrckt`). They become *tickets*: the body gets a negative request id and the unit is built by the runtime on the next
frames, with the body's later orders replayed on it (`Goto`, `Attack`, `Hunt`: `orders = {"Goto", "Attack", "Hunt"}`).
Built straight through, never scaled: the convoy and its escorts (team 1), the intercept nav (team 1) and the defecting
walker (`svwalk` on team 0 - only team 2 builds become tickets).

A new scripted wave (a new frame or a new entry path) is a new scaling event, and the first unit of each event is
mirrored by `min(floor(humans / 2), 2)` extras of the same kind, entry and orders:

| Event | Source | Units |
| --- | --- | --- |
| Annoy raid (every 120 s) | `annoy_1` | 2 `svltnk` + 2 `svfigh`, hunting |
| Attack 3 cleared | `hanger_attack_2` | 1 `svartl` at the hangar |
| Attack 5 cleared +60 s | `attack_6` 9, `attack_7` 9, `hanger_attack_3` 2 | 20 units |
| Walker ambushes | `walker_attack_1` 2 (restored), `_2` 6, `_3` 4 + 2 razors (restored) | on the walker |
| Hangar artillery | `hanger_attack_5` 1, `_6` 2 (after the convoy leaves) | `svartl` |
| `attack_8` | 3 `svtank` + 4 `svwalk` | to a base building |
| Convoy raid +60 s | `convoy_attack_1` 4, `_2.._9` 1 each | to a live APC |
| Trigger 1 | `convoy_attack_10` 6, `hanger_attack_3` 3 razors | APC / hangar |
| Trigger 2 | `attack_9` 6, `attack_10` 6, `hanger_attack_4` 3 razors | base / hangar |

| Humans | Extras per event |
| --- | --- |
| 1 (offline) | 0 |
| 2 or 3 | 1 |
| 4 | 2 |

Cap: at most **36** live scaled units (`liveCap`; the runtime default is 12): the biggest raid alone is 20 plus the
extras of three events. Extras are the only requests dropped for the cap, primaries always spawn.

No pop-in: a ticket is never built within **300 m** of any human (`safeRadius`; the runtime default is 460). The
nearest scripted spawns to the hangar are `hanger_attack_5` and `hanger_attack_6` (about 330 m from the hangar), so with the
default a human standing at the base would hold back every artillery attack; 300 m lets the humans at the buoys not block
them while a human who walks out to meet the spawn still does. If a human is near the authored entry, the next hidden
approach in `fallbackEntries` is used (`attack_8`, `hanger_attack_3`, `attack_10`, `attack_7`, `attack_6`, `attack_9`,
`hanger_attack_4`, `convoy_attack_10`: all 800-2300 m from the base, first that is clear), else the request waits (saved
in `M.crcca`, so a save/load neither loses nor duplicates it). Reinforcements stop for good when the mission is decided
(`endedFlags = {"lost", "won"}`) or a result is queued.

Consequence: a convoy escort who stands within 300 m of a `convoy_attack_*` point pushes that attack to a fallback
approach near the base, from where it still goes for a live APC.

## Humans' result, timer, win and loss

- Win: the body's own flow. A living APC within 30 m of the hangar -> `M.won`, the 30 s cockpit display, `ch02005` -> 1 s
  -> `SucceedMission(..., "ch02win.des")`. Nothing else is required (the timer is a display; see the HUD note below).
- Loss, hangar dead: `ch02006` -> `ch02lsea.des` (1 s). Two APCs dead before arrival: `ch02006`, then the unused `ch03007`
  (restored), then `ch02lseb.des`. The defector dead: `ch02lsec.des` (see "Restored content": the unused `ch04005` plays
  first and the debrief waits 7 s). Out of lives (every human out): `ch02lsea.des` for everyone. Leader departs: every
  guest fails.
- `wonFlags = {"won"}`: after the convoy has arrived a late out-of-lives failure is ignored. The body already keeps
  `M.won`/`M.lost` exclusive.
- The HUD: the map class is `MultSTMission`, which restarts the cockpit timer upward every frame (`BDMISN04_COOP.md`), so
  the 30 s display may count up instead of down. It is only a display in the source, so nothing depends on it.

## Cinematics are shared and unskippable in a network game [owner]

The opening shot (`camera_start`, 800 m, 2000, subject the hangar) is driven by `CameraPath` every frame, so the
runtime's camera stream carries it to every guest; `CameraCancelled` is false in a network game, offline it stays
skippable. The body ends the shot on `CameraPath`'s return value, so the CR `CameraPath` also ends a network shot at its
flight time plus a margin (the same fix as `bdmisn01cr`): `1.25 * length / (speed / 100) + 3` seconds from the first call
(16.6 s -> 23.8 s); `Test-Chmisn02CoopContract.py` recomputes the flight time from the map's path. Without a skip the
native arrival wins well before that. A save/load cannot resume a shot: the first `CameraPath` after a load reports
arrival, so the body runs its own arrival code (the 2 s pause, then the objective and the clocks).

## Restored content [owner decision 2026-11-01]

Each item is switched by a `RESTORED_*` flag at the top of the runtime region and by the map carrying the path.

| Flag | Source | What is restored |
| --- | --- | --- |
| `RESTORED_WALKER_AMBUSH` | the `#if 0` block (kept as a Lua long comment in `ch02.lua`) | As the walker passes `walker_attack_1` (< 300 m, the unused `M.walkerAttack1`) two Soviet fighters attack it, before the 200 m ambushes at `_2` and `_3`. |
| `RESTORED_WALKER_RAZORS` | the commented `svhraz` pair in the `walker_attack_3` block | The two heavy razors that the authors commented out are built with the ambush (4 tanks + 2 razors) and attack the walker. |
| `RESTORED_ATTACK_9_PATH` | the authored `attack_9_path` (5 points, ending 50 m from the hangar), named by no code | The six `attack_9` raiders (trigger 2) take that path instead of heading for a random building: the other trigger-2 column (`attack_10`) still does. |
| `RESTORED_VOICE_LINES` | see below | Two shipped lines the game never plays. |

Not restored, with reasons:

- The early `AudioMessage("ch02008.wav")` after the walker spawns is a duplicate of the line that plays on its arrival
  ("another new piece of equipment"): it only makes sense when the walker is in.
- `objective1Complete`/`objective2Complete`, `cameraReady[1]`, `cameraComplete[1]`, `apcArrived[]` and `factory` are
  declared and never used by the source; there is no behaviour to restore. The authored `avrecy0_recycler` (a Soviet
  recycler on team 1 at 4614, 102165) is left as the map has it.
- `attack_path_1`, `attack_path_2`, `attack_path_3`, `attack_path_4` and `attack_path_5` are the routes of the authored sentries (`attack_1`..`attack_5`, ending at the base); `edge_path` is
  the playable box (the weather reads it); `outer_limits` is a closed outline. No code names them.
- The second `hanger_attack_3` path: the map has two paths of that name; the engine uses the first, as the source does.

### Voice lines

The ch02 catalogue is `ch02001`..`ch02008` (`Tools/TranscriptSources/GoombaBZ/campaigns.csv`) and the body plays all eight:
001 briefing, 002 incoming forces, 003 convoy, 004 convoy hit, 005 victory, 006 failure, 007 defector, 008 defector in.
Every one has a subtitle in `Text/`. Two shipped lines of neighbouring missions are never played by any script
(`ch03007`, `ch04005`; also `ch01010`, `ch04004`, `ch05008`, `ch06007` and `ch08001..9`, which are mission-specific or from the
cut mission 8). They are slotted in here as **inferences**:

- `ch03007` ("This is unthinkable! Your feeble ineptitude sickens me, Major. You will be left to rot on this barren rock,
  and that is a kindness compared to what some here would inflict upon you.") follows `ch02006` when two APCs are lost:
  General Fu is the one who "inflicts punishments for incompetence" in `ch02003`. It is queued behind `ch02006`, and the
  body's failure gate waits for both lines (`IsAudioMessageDone` is shadowed).
- `ch04005` ("What are you trying to do, Major? You are a most weak and feeble leader. You will be replaced.") plays when
  the defector walker is destroyed: that loss has no voice line in the source. The debrief `ch02lsec.des` is delayed 7 s
  so the line is heard.

## Stock bugs and co-op fixes in the CR layer (the faithful body is untouched)

- Teams: the body builds the Soviets on team 2, a human slot in co-op; the runtime maps them to team 5. The body's `SetPilot`
  is repeated for every human team.
- The opening shot hangs after a skip on a network host (the body ends the shot on `CameraPath`'s return, and a skip
  releases only the skipper's own native camera): the flight-time fallback above. A load during a shot: see "Cinematics".
- `SetName(convoyIntercept, "Convoy Intercept")` and `SetObjectiveOn(walker)` are local-only in the source: the CR layer
  uses the runtime's `SetObjectiveName`/`SetObjectiveOn`, which replicate by label so every human gets the nav name and the
  walker marker. The 30 s `StartCockpitTimer` is published to every peer.
- The runtime's `Load` drops the objective list and the markers: the CR layer records every `ClearObjectives`/`AddObjective`
  and publishes them again after a load, with the walker marker and the nav name.
- A scripted failure ends the spawns (`endedFlags`): the source keeps building annoy raids every 120 s forever, including
  during the victory line and after a defeat.
- An audio message whose handle is absent counts as finished (`AudioMessage` returns 0), so no gate can wait on it.
- The defector's loss failed the mission in silence; see the restored `ch04005`.
- Orders on tickets: `Goto`, `Attack` and `Hunt` are recorded on a waiting ticket and replayed on the real unit (the same on
  the extras); the body's checks never see a ticket (it only keeps real handles in `M`).
- Objective rebuilds are coalesced by the runtime (a rebuild identical to the last published one is dropped).
- The body already carries its own documented port fixes (`References/Chinese02Source/README.md`: NULL health/distance guards,
  live-APC-only triggers, no victory after defeat, no `Goto` without a live APC). Its `AtEndOfPath` 25 m radius is an
  approximation of the native `isAtEndOfPath` (see "Inferences").

## Weather: Ganymede

An icy, airless Jovian moon. `CREuropaWeather` (no new module) with `CRGanymedeSitesCH02`: orbit lighting
(`Environment.Init{lightingMode="orbit", orbit={period=1800, startHour=-40}}`, as `bdmisn01cr`), the cryovolcanic plume, quake
and Jupiter-surge director, networked through the runtime's ops (`EuropaState`, `EuropaPlume`, `EuropaQuake`,
`EuropaSurge`): seeded timeline from the host, host-chosen events over the ordered stream, `Save`/`Load` state,
`AnnounceState`. The generated sites carry seven vents (the first is the geyser beside the armoury, 2954, 98720) and the frost
clusters. If the weather module or the sites module is missing, or any weather call errors, the mission runs without weather
and logs once. The director never damages and never touches perception or sensors.

Beats (host/offline only, each once, tied to the story; a site list with fewer vents skips only the plume):

| Story moment | Beat |
| --- | --- |
| Briefing and the opening shot | rung 1 (quiescent) |
| "Incoming CCA forces" (`ch02002`, 60 s in) | rung 2 (stirring) |
| `attack_3` cleared | a 2.5 s quake (0.3) |
| The big raid leaves `attack_6`/`attack_7` | rung 3, a plume at the armoury vent (1), a 3 s quake (0.35), a 6 s surge (0.8) |
| The defecting walker spawns | a quake (0.3) and a plume at the western vent (5) |
| General Fu's convoy rolls | rung 4, a 3.5 s quake (0.5), a 5 s surge (0.9) |
| The convoy is first hit | a quake (0.4) and a plume at vent 2 |
| The convoy reaches the hangar | release the forced level, back to rung 1 |
| Any loss | a last surge and quake |

## Tests

```sh
lua5.1 Tools/Test-Chmisn02Coop.lua            # offline == faithful, 1-4 peers, scaling, 300 m, fallback, cameras, results, restorations, weather
lua5.1 Tools/Test-Chmisn02Presentation.lua    # E/A/C protocol on a guest
python Tools/Test-Chmisn02CoopSourceParity.py # chmisn02cr.lua minus CR regions == ch02.lua
python Tools/Test-Chmisn02CoopContract.py     # labels/paths/teams/flight time in chmisn02cr.bzn (skips with a message if the map is absent; ini/vxt/mpdes only when present)
python Tools/test_ch02.py                     # the faithful port, unchanged (needs lupa)
```

## Inferences and open questions

- Scaling is per (frame, entry path), a CR inference; so is the 300 m concealment radius.
- `fallbackEntries` assumes the eight points are usable enemy approaches (they are all the body's own spawn points).
- The 1.25x + 3 s network shot fallback is a margin on the 1.5-source flight time (`speed/100` m/s, documented in
  `BZR_LUA_AGENT_REFERENCE.md`, not re-measured on this map).
- The walker's end-of-path radius is the TRO 1.3 value (2D, 12 m to the last waypoint; the leaked source gives none).
- `ch03007` and `ch04005` as the convoy-lost and defector-lost lines, and `attack_9_path` as the route of the attack_9
  column, are inferences from the text and the geometry; the flags switch them off.
- The restored walker ambushes add 2-4 units to a fight the source balanced for one player; with extras at four players
  the `walker_attack_3` ambush is 4 + 2 razors + 2 mirrored units.
- The bzn carries an `[AOI]` entry on team 2 that nothing reads.
- The out-of-lives path is not exercised by the host tests (leader departure is).

## Live checklist (unrun)

1. Opening: the arc over the hangar is the same on every peer, ends on its own (skip it on the host: it still ends about
   24 s in), cameras balanced, then `ch02001`, the objective and the 60 s / 120 s clocks.
2. 60 s later `ch02002`; the first annoy raid after 2 min hunts from `annoy_1` (585 m from the base), with extras at 2-4
   humans.
3. Kill the five fighters of `attack_3`: one artillery tank comes for the hangar. Kill the five tanks of `attack_5`: a minute
   later the raid (two columns, the hangar razors), a vent blows at the armoury, the ground shakes.
4. Four minutes after that the defector walker: marker for everyone, `ch02007`, three ambushes along its path (the first is
   the restored one), `ch02008` on arrival and it joins the base (no `ch02lsec`).
5. Five minutes later the `attack_8` wave, 4.5 minutes after that the convoy (`ch02003`): three APCs, six escorts, the raid on
   it a minute later, the first hit gives `ch02004` and the named nav for everyone.
6. Trigger 1 and 2: the razors at the hangar, the `attack_9` column walking its path.
7. An APC within 30 m of the hangar: the 30 s display (may count up), `ch02005`, one shared victory a second after.
8. Lose the hangar: `ch02006`, `ch02lsea` for everyone. Lose two APCs: `ch02006` then `ch03007`, `ch02lseb`. Lose the walker:
   `ch04005`, `ch02lsec` ~7 s later.
9. Save during the opening and later: the shot ends, the objectives and the walker marker come back, no duplicate raid.
10. Ganymede sky and plume render on guests; no weather error in the log.
