# Black Dog 01 co-op: Close Target Wrecky (bdmisn01)

Shared offline / 2-4 player co-op port of the Black Dog mission `bd01` (deploy the Recycler, investigate the Nav
Alpha beacon, defend the base against a cloaked ambush and two waves of Chinese fighters and a light tank). One
`Missions/bdmisn01cr.bzn` and one `Scripts/bdmisn01cr.lua` serve both modes. Companion to
[`Scripts/bd01.lua`](../References/BlackDog01Source/PORT_NOTES.md) (the faithful DLL port underneath) and
[`CCA_COOP_RUNTIME.md`](CCA_COOP_RUNTIME.md) (the shared runtime, first used by `misns1..8`). Pattern:
[`MISNS2_COOP.md`](MISNS2_COOP.md).
Status: **host-tested only**; nothing here has run in the game (see "Live checklist").

## Layout

| File | Role |
| --- | --- |
| `Scripts/bdmisn01cr.lua` | The faithful port plus marked `-- CR ... >>` / `<<` regions. Outside them it is exactly `bd01.lua` (`Tools/Test-Bdmisn01CoopSourceParity.py`). Holds the runtime CONFIG, the native shadows, the co-op fixes and the Ganymede weather. |
| `Scripts/CRGanymedeSitesBD01.lua`, `Scripts/CREuropaWeather.lua` | Ganymede weather: the generated sites for this map (one vent, the base geyser) and the shared icy-moon director (no new module). |
| `Missions/bdmisn01cr.{bzn,vxt}`, `bdmisn01.{hg2,lgt,mat,trn}`, `Config/bdmisn01cr.ini` | Map and companions (not part of this change). The map has **no authored enemies**: Lua spawns all of them. |
| `Tools/Bdmisn01Fixture.lua`, `Test-Bdmisn01Coop.lua`, `Test-Bdmisn01Presentation.lua`, `Test-Bdmisn01CoopSourceParity.py`, `Test-Bdmisn01CoopContract.py` | Multi-peer fixture and tests (real map coordinates). `Test-BlackDog01.lua` / `Test-BlackDog01SourceParity.py` still cover the faithful port, unchanged. |

The CR regions, in file order:

| Region | Where | What |
| --- | --- | --- |
| `co-op layer` | file header | The pointer comment. |
| `co-op runtime` | after `local M = NewState()` | The runtime CONFIG (including the weather), the shadowed natives, the direct-build bypass, the beacon/camera wrappers. |
| `co-op fixes` | after `Distance` | The nearest-human distance wrap, the load fix and the extras check (`Restored`). |
| `co-op victory` | before the body's victory test | One early return while a co-op extra lives. |
| `co-op callbacks` | end of file | The runtime's per-frame calls wrapped around the body's `Start/AddObject/Update/Save/Load`, and the engine's player callbacks. |

The wrapped callbacks differ from the `misns` pattern on purpose: the `bd01` body `return`s early on most frames (before
deployment, during every wait), so `AfterUpdate` (objective flush, scaling-event close) cannot sit at the end of
`Update`. The wrapper runs it after every body pass.

## Teams and ownership

| Team | Use |
| --- | --- |
| 1-4 | Humans (host on 1). The authored Black Dog side (the Recycler, the two Bobcat wingmen, the Nav Alpha beacon) stays on team 1: shared, host-run. Extra starting recyclers are disabled. |
| 5 | The Chinese: the two cloaked ambushers and every wave unit. The body still says team 2; the runtime maps `BuildObject(..., 2, ...)` to team 5 (the two direct-build paths below do the same by hand). Nothing on the map is authored on team 2. |
| 7 | Support (nothing uses it here). |

Only the authority (host, or the offline player) runs the body; guests only present. `SetAIControl(5, true)` runs
once at chunk load. This mission has no `SetAIP`: the enemy is entirely scripted. Starting scrap `SetScrap(1, 12)`
becomes `12 + 10 per guest` on the shared team-1 base (`scrapPerGuest = 10`, the runtime default made explicit);
`SetPilot(1, 10)` is unchanged. Respawn rally point: the Recycler (`rallyPoints = {[0]="recycler"}`).

### Humans as the player

The DLL's "player" is `M.user = GetPlayerHandle()`, assigned every frame and read once: `Distance(M.user, M.beacon)
< 100` (the "you are at Nav Alpha" test). In co-op `GetPlayerHandle` is the runtime's nearest-human token and the
body's `Distance` is wrapped with `WrapDistance`, so any human within 100 m of the beacon counts. It is an approach
trigger (nearest human); `farthestTargets` is empty.

## Scaling and concealed arrivals [owner rules, mission decisions]

Scaled spawns: the ODFs `cvfigh` and `cvltnk` (the attack waves). They become *tickets*: the body gets a negative
request id and the unit is built by the runtime on the next frames, with the body's later orders replayed on it
(`Attack(h, recycler, 1)`, `SetCloaked(h)`, `Decloak(h)`; the two cloak calls go through the CR globals `CRSetCloaked` /
`CRDecloak` so the replay is the native one-argument call). Not scaled, built directly on team 5:

- the two **cloaked ambushers** at `spawn_attack_ambush` (they are cloaked in the same frame they are built, so there is
  no pop-in, and the body keeps their handles for patrol, retreat and `IsCloaked`);
- the first **wave-1 pair** at `spawn_attack_wave1`: the attack camera is aimed at the first of them
  (`CameraPath("camera_attack_view", ..., badGuy1_wave1)`) and the shot starts in the frame they are built, so the
  camera hides the arrival (the same reasoning as the platoon stage props in `MISNS2_COOP.md`).

A new scripted wave (a new frame or a new entry path) is a new scaling event, and the first unit of each event is
mirrored by `min(floor(humans / 2), 2)` extras of the same kind, entry and orders:

| Event | Source | Units | With 4 humans |
| --- | --- | --- | --- |
| Ambush | `Ambusher() x2` | 2 `cvfigh`, direct | 2 (never scaled: the body's retreat and Nav logic expects exactly two) |
| Wave 1 (camera pair) | `Attacker(..., "spawn_attack_wave1", true) x2` | 2 `cvfigh`, direct | 2 |
| Wave 1a (after the shot) | `spawn_attack_wave1a` | 2 `cvfigh` + extras | 4 |
| Wave 2 | `spawn_attack_wave2` | 2 `cvfigh` + 1 `cvltnk` + extras | 5 |
| Wave 2a | `spawn_attack_wave2a` | 2 `cvfigh` + extras | 4 |

| Humans | Extras per event |
| --- | --- |
| 1 (offline) | 0 |
| 2 or 3 | 1 |
| 4 | 2 |

Cap: at most **14** live scaled units (`liveCap`; the runtime default is 12): wave 1a plus wave 2 at four humans is
4 + 9. Extras are the only requests dropped for the cap, primaries always spawn.

No pop-in: a ticket is never built within 460 m of any human. If a human is near the authored entry, the next hidden
approach in `fallbackEntries` is used (`spawn_attack_wave2`, `spawn_attack_ambush`, `spawn_attack_wave1a`,
`spawn_attack_wave2a`, `spawn_attack_wave1`, `spawn_attack_wave1_1`, first that is clear), else the request waits (saved
in `M.crcca`, so a save/load neither loses nor duplicates it). Reinforcements stop for good when the mission has failed
(`endedFlags = {"failed"}`) or a result is queued.

Consequence of the geometry: `spawn_attack_wave2a` (west flank, 190 m from the Recycler's start, about 390-440 m from
the four start positions) is inside 460 m of anyone defending the base, so
with the humans at home wave 2a arrives from the `spawn_attack_wave2` approach together with wave 2 instead of from the
west. It uses the west flank only when nobody is within 460 m of it.

## Humans' result, timer, win and loss

- Win: the body's own flow. All eleven source enemies dead and `cameraComplete[1]` -> `bd01004` ("pull out") -> 4 s ->
  `SucceedMission(..., "bd01win.des")`. The co-op extras are not in the body's lists: the CR victory region holds the
  start of the congratulation while any runtime-built unit (a living extra, or a ticket still waiting) exists.
- Loss: Recycler dead -> `bd01005` -> `bd01lsea.des` (4 s). Never deployed: `bd01008`, `bd01009`, `bd01lseb.des`. Nav
  Alpha ignored: `bd01006`, `bd01007`, `bd01lsec.des`. Out of lives (every human out): `bd01lsea.des` for everyone.
  Leader departs: every guest fails.
- The body latches its failure (`M.failed`), so a victory cannot overwrite it; no `wonFlags` are configured (the body has
  no win flag, the result queue keeps the first request).

## Cinematics are shared and unskippable in a network game [owner]

Both shots (the opening arc over the base, and the attack view of the first decloaking fighter) are driven by
`CameraPath` every frame, so the runtime's camera stream carries them to every guest; `CameraCancelled` is false in a
network game, offline both stay skippable.

Unlike the `misns` films, **these shots end on `CameraPath`'s return value**. In a network game a skip releases only
the skipper's own native camera and the runtime then stops calling the native path, so a skipping host would never
"arrive" and the shot would hang for everyone. The CR `CameraPath` therefore also ends a network shot at its flight
time plus a margin: `1.25 * length / (speed / 100) + 3` seconds from the first call (opening 15.6 s -> 22.5 s, attack
view 7.3 s -> 12.1 s; `Test-Bdmisn01CoopContract.py` recomputes the two flight times from the map's paths). Without a
skip the native arrival wins well before that.

A save/load cannot resume a shot (the cameras are gone): the first `CameraPath` after a load reports arrival, so the body
runs its own arrival code (the opening starts the 90 s deployment clock; the attack view releases wave 1a).

## Restored content [owner decision 2026-11-01]

`BlackDog01Mission.cpp` (archived in `References/BlackDog01Source/`) contains **no cut gameplay**: `PORT_NOTES.md` states
"There are no other disabled gameplay blocks", and a line-by-line pass of the C++ finds only these dead items:

| Item | Source | Decision |
| --- | --- | --- |
| `//SucceedMission(GetTime(), "bd01win.des");` | the first-frame block of `Execute` | A debug instant win. Restoring it would end the mission on frame one. Not restored (and it stays a comment in the port). |
| `scavengers[2]`, `BD01003`, `delayTime3` | members never read | Dead state, kept in the saved table by the port. Nothing to restore. |
| Scavenger creation / `AddObject` test | `if (!scavengersCreated)` in `AddObject` | The hook body is empty in the source; the mission waits for Recycler deployment instead. Nothing to restore. |

So there is no `RESTORED_*` flag in `bdmisn01cr.lua`. Authored map content the script never uses, documented rather
than guessed:

- `edge_path`: the playable box (the weather reads it as bounds). `outer_limits`: a closed outline of the play area; no
  code, active or cut, names it.
- `spawn_attack_wave1_1`: a second point 21 m from `spawn_attack_wave1`. No source line uses it. It is **used as the last
  fallback approach** (a hidden enemy staging point is exactly what the fallback list needs); this is an inference, it
  does not change what the body spawns.

Unused voice lines: **none**. The catalogue for the mission is `bd01001`..`bd01009` (see
`Tools/TranscriptSources/GoombaBZ/campaigns.csv`), and the body plays all nine: 001 briefing, 002 Nav, 003 attack, 004
victory, 005 Recycler lost, 006/007 Nav reminders, 008/009 deployment reminders. Every one has a subtitle in `Text/`
(`Test-Bdmisn01CoopContract.py` asserts the full set). No `bd010x.wav` outside that range exists in the game's audio or
in the repository references.

## Stock bugs and co-op fixes in the CR layer (the faithful body is untouched)

- One player: see "Humans as the player" (a fixed single `GetPlayerHandle()` would ignore every human but the host).
- `GetNearestUnitOnTeam("spawn_nav_beacon", 0, 1)` only looks at team 1; humans are teams 1-4, so a guest's escort next
  to the beacon never completed Nav Alpha. The CR layer asks teams 1-4 and returns the nearest.
- `SetUserTarget(beacon)` selects the beacon for the calling player only. In a network game the CR layer also marks it
  (`SetObjectiveOn`, replicated by label) so every human gets the navigation marker. Offline it stays the plain native
  selection.
- The shared-shot hang on a skipping host: see "Cinematics".
- A load during a shot: see "Cinematics".
- The body returns early on most frames, so the runtime's `AfterUpdate` could not run at its end: the callbacks are
  wrapped (see "Layout").
- Victory ignoring the co-op extras: see "Humans' result".
- Orders on tickets: `Attack`, `SetCloaked` and `Decloak` are recorded on a waiting ticket and replayed on the real
  unit (the same on the extras); the body's checks on tickets (`IsValid`, `IsAlive`, `GetDistance`) answer "valid,
  alive, infinitely far".
- Objective rebuilds are coalesced by the runtime (a rebuild identical to the last published one is dropped).
- Audio: every line the body names has a subtitle in `Text/`; `audioSubstitute` is empty. The body's uppercase
  `BD01002.WAV` is the macro's original filename and is kept (the file system is case-insensitive).
- The body already carries its own documented port fixes (`References/BlackDog01Source/PORT_NOTES.md`: the audio array
  overflow, completed-objective reminder cancellation, missing-handle guards, latched failure).

## Weather: Ganymede

An icy, airless Jovian moon. `CREuropaWeather` (no new module) with `CRGanymedeSitesBD01`: orbit lighting
(`Environment.Init{lightingMode="orbit", orbit={period=1800, startHour=-40}}`, as `misn12cr`), the cryovolcanic plume,
quake and Jupiter-surge director, networked through the runtime's ops (`EuropaState`, `EuropaPlume`, `EuropaQuake`,
`EuropaSurge`): seeded timeline from the host, host-chosen events over the ordered stream, `Save`/`Load` state,
`AnnounceState`. The generated sites carry one vent, the base geyser `eggeizr11_geyser` (1049, 1411), and the frost
clusters. If the weather module or the sites module is missing, or any weather call errors, the mission runs without
weather and logs once. The director never damages and never touches perception or sensors; the runtime does not call
`BindWeatherSensors` (the `misn12cr` stealth mission does), so the sky is purely visual here.

Beats (host/offline only, each once, tied to the story; a site list without vents skips only the plume):

| Story moment | Beat |
| --- | --- |
| Quiet while the Recycler deploys | rung 1 (quiescent) |
| "Strange readings", Nav Alpha revealed (`beaconSpawned2`) | rung 2 (stirring) |
| "Where did they come from?": wave 1 decloaks (`wave1Ready`) | rung 3, a plume at the base vent, a 3 s ice quake (0.35) and a 6 s surge (0.8) |
| Wave 2 with the light tank (`wave2Ready`) | rung 4 |
| "Pull out" (`bd01004` starts) | release the forced level, back to rung 1 |

## Tests

```sh
lua5.1 Tools/Test-Bdmisn01Coop.lua            # offline == faithful, 1-4 peers, scaling, 460 m, fallback, cameras, results, weather
lua5.1 Tools/Test-Bdmisn01Presentation.lua    # E/A/C protocol on a guest
python Tools/Test-Bdmisn01CoopSourceParity.py # bdmisn01cr.lua minus CR regions == bd01.lua
python Tools/Test-Bdmisn01CoopContract.py     # labels/paths/teams/flight times in bdmisn01cr.bzn (skips with a message if the map is absent; ini/vxt/mpdes only when present)
lua5.1 Tools/Test-BlackDog01.lua && python Tools/Test-BlackDog01SourceParity.py   # the faithful port, unchanged
```

## Inferences and open questions

- Scaling is per (frame, entry path), a CR inference. The ambushers are not scaled because the body's retreat and Nav
  logic expects exactly two; the camera pair is a direct build because the shot starts in the frame it appears.
- `fallbackEntries` assumes the six `spawn_attack_*` points are all usable enemy approaches (the last, `wave1_1`, is
  unused by the source); most of them are inside the valley near the base, so a fully defended base pushes every
  approach east.
- The 1.25x + 3 s network shot fallback is a margin on the 1.5-source flight time; the Redux measurement of the camera
  speed (`speed/100` m/s) is documented in `BZR_LUA_AGENT_REFERENCE.md`, not re-measured on this map.
- `outer_limits` is unexplained and unused.
- `CRSetCloaked` / `CRDecloak` are mission globals the runtime calls by name (`_G[op]`); the engine's one-argument
  `SetCloaked`/`Decloak` are unchanged.
- The out-of-lives path is not exercised by the host tests (leader departure is).
- The bzn carries an `[AOI]` entry on team 2 that nothing reads.

## Live checklist (unrun)

1. Opening: the arc over the base is the same on every peer, ends on its own (skip it on the host: it still ends
   about 22 s in), cameras balanced, the 90 s deployment clock starts.
2. Deploy the Recycler (its start path ends 18 m from the base geyser): 20 s later Nav Alpha and the two cloaked ambushers; every peer hears
   `BD01002`, the beacon is named and marked for everyone.
3. A guest drives to the beacon (and a guest escort stands next to it): Nav Alpha completes.
4. Kill one ambusher: the survivor retreats cloaked, then the attack shot: the same on every peer, the fighters
   decloak over the base, the vent blows, the ground shakes.
5. Wave 1a, wave 2 and wave 2a with 2-4 humans: extras appear, nothing pops in view, the west flank comes from the
   east while the base is watched.
6. Kill everything but one extra: no `bd01004`; kill it: the line, the win 4 s later, one shared result.
7. Lose the Recycler (also while the congratulation plays): one shared failure with `bd01lsea`.
8. Never deploy / ignore the Nav: `bd01lseb` / `bd01lsec` for everyone.
9. Save during each shot and load: the shot ends, wave 1a is released, no second opening.
10. Ganymede sky and plume render on guests; no weather error in the log.
