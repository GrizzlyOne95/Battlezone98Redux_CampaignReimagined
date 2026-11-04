# Chinese 01 co-op: New Kids on the Block (chmisn01)

Shared offline / 2-4 player co-op port of the Chinese (CRA) mission `ch01`: infiltrate the CCA hangar, destroy the comm
array, take delivery of a Recycler, snipe the CCA tug and drive it back, then bring it into the CCA base disguised under
an escort, load the relic and run to the safe distance before the device goes off. One `Missions/chmisn01cr.bzn` and one
`Scripts/chmisn01cr.lua` serve both modes. Companion to [`Scripts/ch01.lua`](../References/Chinese01Source/README.md) (the
faithful DLL port underneath) and [`CCA_COOP_RUNTIME.md`](CCA_COOP_RUNTIME.md) (the shared runtime). Pattern:
[`BDMISN01_COOP.md`](BDMISN01_COOP.md), with the disguise handling of [`BDMISN04_COOP.md`](BDMISN04_COOP.md).
Status: **host-tested only**; nothing here has run in the game (see "Live checklist").

## Layout

| File | Role |
| --- | --- |
| `Scripts/chmisn01cr.lua` | The faithful port plus marked `-- CR ... >>` / `<<` regions. Outside them it is exactly `ch01.lua` (`Tools/Test-Chmisn01CoopSourceParity.py`). Holds the runtime CONFIG, the native shadows, the co-op state, the restorations and the Ganymede weather. |
| `Scripts/CRGanymedeSitesCH01.lua`, `Scripts/CREuropaWeather.lua` | Ganymede weather: the generated sites for this map (seven geysers) and the shared icy-moon director (no new module). |
| `Missions/chmisn01cr.{bzn,vxt}`, `chmisn01.{hg2,lgt,mat,trn}`, `Config/chmisn01cr.ini` | Map and companions (not part of this change). The CCA base and its guards are authored on team 5; the Chinese side is only the on-foot player; everything else is built by Lua. |
| `Tools/Chmisn01Fixture.lua`, `Test-Chmisn01Coop.lua`, `Test-Chmisn01Presentation.lua`, `Test-Chmisn01CoopSourceParity.py`, `Test-Chmisn01CoopContract.py` | Multi-peer fixture and tests (real map coordinates). `Test-Chinese01.lua` still covers the faithful port, unchanged. |

The CR regions, in file order:

| Region | Where | What |
| --- | --- | --- |
| `co-op layer` | file header | The pointer comment. |
| `co-op runtime` | after `local M = NewState()` | The runtime CONFIG (including the weather), the `RESTORED_*` flags, the shadowed natives, the `BuildObject` router. |
| `co-op fixes` | after `Airborne` | The nearest-human wrap of the body's `Distance`. |
| `restored content` | after `co-op fixes` | The `Restored` table: the escort cover, the disguise, the countdown, the objective memory, the inspection relay, the loads and the restorations. |
| `co-op callbacks` | end of file | The runtime's per-frame calls wrapped around the body's `Start/AddObject/Update/Save/Load`, and the engine's player callbacks (plus the mission's one packet kind). |

The body never returns early, so the callbacks follow the `bdmisn04` pattern: the runtime's `Update` first, the body, then
`Restored.Run()` (the authority's step) and the runtime's `AfterUpdate` (objective flush, scaling-event close).

## Teams and ownership

| Team | Use |
| --- | --- |
| 1-4 | Humans (host on 1), all on foot (`csusera`) at the four `coop_spawn` buoys. Everything the body builds for the Chinese side (the `CCA Base`, tug and safe-distance navs, the armoury, the Recycler, the two captured escort fighters, the decoy tanks) stays on team 1: shared, host-run. Extra starting recyclers are disabled. |
| 5 | The CCA: the authored base and guards, and every unit the body builds on its team 2. The runtime maps `BuildObject(..., 2, ...)` to team 5. Nothing on the map is authored on team 2. |
| 0 | The relic (`obdata`), neutral. |
| 7 | Support (nothing uses it here). |

Only the authority (host, or the offline player) runs the body; guests only present. `SetAIControl(5, true)` runs once at
chunk load. This mission has no `SetAIP`: the enemy is the authored base plus scripted waves. `SetScrap(1, 0)` stays 0
(`scrapPerGuest = 0`): the mission starts without scrap on purpose, and the body's `AddScrap(1, 99)` / `AddScrap(1, 50)`
come from the armoury and the Recycler. `SetPilot(1, 10)` goes to every human team (as `bdmisn04`). Respawn rally point: the
`recycler` path, the Chinese beachhead.

### Humans as the player

The DLL's "player" is `M.user = GetPlayerHandle()`, assigned every frame and read for: the 150 m detector test, the 300 m
decoy test, the blast-radius test for the finale film, and the escort tests. In co-op `GetPlayerHandle` is the runtime's
nearest-human token and the body's `Distance` is wrapped (keeping its three-argument path overload), so any human within
the radius counts. These are approach triggers (nearest human); `farthestTargets` is empty. For the finale film that is
the right sense: the nearest human beyond the blast radius means everybody is. `IsValid(token)` is true while any human has
a handle.

## Scaling and concealed arrivals [owner rules, mission decisions]

Scaled spawns, built as head-count-scaled concealed tickets: the CCA ground waves (`svfigh`, `svtank`, `svltnk`, `svhraz`,
`svturrb`), including the two fighters that guard the tug. The body's later orders (`Goto`, `Defend2`) are recorded on the
ticket and replayed on the real unit. Built directly, never as tickets:

- the **tug** (`svhaula`, team 5): an objective the body tests every frame, with its handle kept;
- the **escort fighters** (`svfigh`, **team 1**): the body perceives them as the CCA at once, and only team 2 is routed to the
  runtime (the router builds every other team directly);
- the **paratroopers** (`sspilo`, `sssold`): built at a height over a path point, a position and not a path, so they cannot
  be tickets; direct on team 5 (not scaled);
- the navs, armoury, Recycler, decoys and relic (teams 1 and 0).

A new scripted wave (a new frame or a new entry path) is a new scaling event, and the first unit of each event is mirrored by
`min(floor(humans / 2), 2)` extras of the same kind, entry and orders:

| Event | Source | Units | Extras (4 humans) |
| --- | --- | --- | --- |
| Wave 1 | `wave_1`, 60 s after deployment | 4 `svfigh` + 4 `svtank` | +2 `svfigh` |
| Wave 2 | `wave_2`, +300 s | 4 `svtank` + 3 `svltnk` + 2 `svfigh` | +2 `svtank` |
| Wave 3 | `wave_3`, +300 s | 9 `svtank` + 3 `svhraz` | +2 `svtank` |
| Wave 4 | `wave_4`, after the air drops | 4 `svtank` + 4 `svhraz` + 4 `svltnk` | +2 `svtank` |
| Tug guards | `tug_defend` | 2 `svfigh` | +2 `svfigh` |
| Base reinforcements | `wave_5`, when the tug is home | 4 `svtank` + 4 `svhraz` + 4 `svltnk` + 4 `svturrb` | +2 `svtank` |

| Humans | Extras per event |
| --- | --- |
| 1 (offline) | 0 |
| 2 or 3 | 1 |
| 4 | 2 |

Cap: at most **50** live scaled units (`liveCap`; the runtime default is 12): the waves can pile up when the players do not
kill them. Extras are the only requests dropped for the cap, primaries always spawn.

No pop-in: a ticket is never built within 460 m of any human. If a human is near the authored entry, the next hidden CCA
approach in `fallbackEntries` is used (`wave_2`, `wave_3`, `wave_4`, `wave_1`, `wave_5`, first that is clear), else the
request waits (saved in `M.crcca`, so a save/load neither loses nor duplicates it). Reinforcements stop for good when the
mission is won or lost (`endedFlags`) or a result is queued. Geometry: waves 1-4 enter within a few hundred metres of each
other, so a human at one of them sends the wave to `wave_5`, the base centre; a human at `wave_1` and one at `wave_5`
together hold every approach and the wave waits. The four start buoys are 1.6 km from every entry, so a normal game
never defers a wave.

## The disguise

The body's cover story: from the moment the tug is home, the player must be escorted by the two captured fighters (they
`IsFollowing` the player) or be seen. `SetPerceivedTeam(user, 2)` while escorted, `1` otherwise, every frame, until the relic
is aboard; within 150 m of a living detector and not escorted the cover is blown (`ch01008`, then `ch01lsec.des`).

Co-op rule (a CR inference, not the DLL's): **one cover for the party.**

- The *escorted human* is the one that **both** fighters follow (the host can command team 1; the target may be any human).
- The party is covered while every living human is within **100 m** of the escorted one (`CONVOY_RADIUS`). A human with no
  live ship is not counted; no escorted human, or one fighter only, means no cover.
- The body asks `IsFollowing(escort, user)` twice with the token; the shadow answers both from one per-frame computation.
- `SetPerceivedTeam(user, 2)` becomes a cover to team **5** for every human; `SetPerceivedTeam(user, 1)` means each human is
  perceived as their own team (guests are teams 2-4, never "2"). The effect is local engine state, so it runs on **every
  peer** through the stream (`CH1Disguise`), only when the value changes or a human's handle changes (a respawn).
- The escorts themselves keep `SetPerceivedTeam(escort, 5)`.

Detection and the paratroopers use the nearest human, as written: one human walking up to a detector without cover is enough.

## Humans' result, timer, win and loss

- Win: the body's own flow. The relic aboard the tug starts the 180 s countdown (`StartCockpitTimer(180, 15, 5)`); at zero the
  white flash and the blast; if the relic is farther from the hangar than `Distance(navEnd, hangar) - 50`,
  `SucceedMission(+3 s, "ch01win.des")`, else `ch01lsee.des`.
- Loss: tug destroyed -> `ch01011` -> `ch01lseb.des`; tug reaches `tug_fail` uncaptured -> `ch01lsea.des`; Recycler lost
  before the tug is home -> `ch01lsed.des`; cover blown -> `ch01008` -> `ch01lsec.des`. Out of lives (every human out):
  `ch01lsea.des` for everyone. Leader departs: every guest fails.
- The body latches `lost` / `won`; `wonFlags = {"won"}` keeps a late failure from overwriting a victory, `endedFlags` stops
  reinforcements.
- The countdown: the map runs `MultSTMission`, whose engine timer restarts upward every frame (the live finding recorded in
  `Misn18Fixture`), so the host counts the three minutes itself (`Restored.TimerLeft`, saved) and every peer shows the
  countdown through the stream. The body's two reads (`<= 0`, `<= 2.0`) use that clock.

## Cinematics are shared and unskippable in a network game [owner]

There is one shot, the finale: `CameraReady(); CameraPath("cut_end", 3000, 0, bb_tower)` two seconds before the blast, held until
three seconds after it. It is driven by `CameraPath` every frame, so the runtime's camera stream carries it to every guest
(the tower by its map label `bb_tower`); `CameraCancelled` is false in a network game, so a skip releases only the skipper's
own camera, and the shot ends on its own timer. Offline it stays skippable. The film is only shown when every human is outside
the blast radius (nearest human > radius, see above), as in the body.

A save/load cannot resume a shot (the cameras are gone): the first step after a load opens the camera again while the body's
`focusOnExplosion` is still set; the body then ends it at its own time.

## Restored content [owner decision 2026-11-01]

`Chinese01Mission.cpp` (archived in `References/Chinese01Source/`) has these disabled or unused items:

| Item | Source | Decision |
| --- | --- | --- |
| `#if 0` first-frame block (relic and tug at the player, `SetPerceivedTeam(user, 2)`, `SetObjectiveOn(hangar)`) | `Execute` | A debug start-up. Restoring it would skip the whole mission. Not restored. |
| `//failedSound = AudioMessage("ch01011.wav");` after detection | the `detectedSound` block | `ch01008` already ends in "wait for a political officer"; a second "you have failed us" line contradicts the capture. Not restored. |
| Unused members (`objective5Complete`, `cameraReady/cameraComplete`, `sound12Played`, `wave5Time`, `explodeTime`, `tugDiedSound`) | `Setup` | Dead state, kept in the saved table by the port. Nothing to restore. |
| Unused paths `camera_end`, `edge_path`, `mobile_patrol_1`, `confine_1`, `confine_2`, `patrol_path_1`, `patrol_path_2`, `patrol_path_3`, `patrol_path_4`, `patrol_path_5`, `patrol_path_6`, `patrol_path_7`, `patrol_path_8`, `patrol_path_9`, `patrol_path_10`, `patrol_path_11`, `patrol_path_12`, `patrol_path_13`, `patrol_path_14` | map | The patrols and confinements belong to the authored guards; `edge_path` is the playable box (the weather reads it as bounds); `camera_end` is the one that could be a cut shot, but nothing says where it looked, so it is documented rather than guessed. |

Restored, each behind a flag in the `co-op runtime` region:

| Flag | What | Why it fits |
| --- | --- | --- |
| `RESTORED_RECYCLER_OBJECTIVES` | The objectives `ch01006.otf` "Deploy your Recycler." (white, appended when the Recycler arrives) and `ch01007.otf` "Protect your Recycler. Build Turrets to help." (white after deployment, with `ch01006` green), both listed before the body replaces the list at the tug nav | Both ship with the game (`StockODFFiles`) and the body never lists them, although deployment starts the whole wave clock and losing the Recycler fails the mission (`ch01lsed`). The body gave the player no hint to deploy. |
| `RESTORED_VOICE_LINES` | `ch01010.wav` "Shield your eyes, Major. This should cover our tracks sufficiently." once, six seconds before the blast (the 4.1 s line ends ahead of the flash) | The one shipped line of this mission the DLL never plays (`ch01001`..`ch01011` ship; the body plays `ch01001`..`ch01009` and `ch01011`). It is command's remark on the nuclear device the player is leaving behind. Played through the runtime (`AudioMessage`: replicated, queued behind a line still playing), latched in `M.crcca.r`. The body now also plays it at T-5 s as TRO 1.3 does (outside the blast radius only); the restoration sets `M.sound12Played` so it is heard once. |

No other `ch01` voice line ships in the game files (`StockODFFiles`, `mods`).

## Stock bugs and co-op fixes in the CR layer (the faithful body is untouched)

- **`BuildObject("cvrecyd", 1, "M.recycler")`**: the C++ path is `recycler`; the port's rename slipped into the string, and
  `M.recycler` is not a map path. The `BuildObject` shadow builds it at `recycler` (the mission's Recycler arrival), in both modes.
- **`MakeExplosion("xpltrsn", "spawn_explosion1")`**: the map has no path `spawn_explosion1`, so the blast had no place. The shadow
  uses the path if it exists and falls back to `relic_loc`, the relic's own spot at the hangar.
- One player: see "Humans as the player" (a fixed single `GetPlayerHandle()` would ignore every human but the host).
- Escort cover and perceived team for several humans, and the local disguise state on every peer: see "The disguise".
- `GetTeamNum(tug) == 2` is "the CCA still has it". The co-op enemy is team 5 and the guests are teams 2-4, so the shadow
  answers 2 for team 5 and 1 for teams 2-4: a guest who steals the tug is not "got away".
- The decoy order `Goto(h, detectors[random])` can name a destroyed detector (an invalid handle); the runtime's order shadow drops
  orders at invalid targets. Likewise `Attack(h, recycler)` after the Recycler dies.
- `IsInfo` (the hangar inspection) is the local player's info panel: a guest reports the ODF to the host (packet `I`, 0.25 s),
  which counts it for one second.
- The 180 s `GetCockpitTimer`: see "Humans' result". `ColorFade`, `MakeExplosion` and `EnableAllCloaking(false)` are local effects
  and run on every peer through the stream.
- A line the engine cannot start has no handle and the body's gates only advance on a handle that reports done: a missing line is a
  finished line (`AudioMessage` returns 0, `IsAudioMessageDone(nil or 0)` is true).
- A load during the countdown or the finale: the objective list, the remaining countdown, the disguise and the blast shot are
  published again from the saved state (the runtime's load resets the presentation).
- Orders on tickets (`Goto`, `Defend2`) are recorded on a waiting ticket and replayed on the real unit (the same on the extras).
- Objective rebuilds are coalesced by the runtime (a rebuild identical to the last published one is dropped).
- The body already carries its own documented port fixes (`References/Chinese01Source/README.md`: handle guards, the latched
  failure, the stationary camera pump).

## Weather: Ganymede

An icy, airless Jovian moon. `CREuropaWeather` (no new module) with `CRGanymedeSitesCH01`: orbit lighting
(`Environment.Init{lightingMode="orbit", orbit={period=1800, startHour=-40}}`), the cryovolcanic plume, quake and Jupiter-surge
director, networked through the runtime's ops (`EuropaState`, `EuropaPlume`, `EuropaQuake`, `EuropaSurge`): seeded timeline from
the host, host-chosen events over the ordered stream, `Save`/`Load` state, `AnnounceState`. The generated sites carry seven
geysers: three in the CCA base (vents 1-3) and four at the Chinese beachhead (vents 4-7). If the weather module or the sites module
is missing, or any weather call errors, the mission runs without weather and logs once. The director never damages and never
touches perception or sensors; the runtime does not call `BindWeatherSensors`, so the sky is purely visual and the cover story
is not affected by it.

Beats (host/offline only, each once, tied to the story; a site list with fewer vents skips only the plume):

| Story moment | Beat |
| --- | --- |
| Quiet while the base is scouted | rung 1 (quiescent) |
| The comm array falls (`objective2Complete`) | rung 2, a 3 s ice quake (0.3) |
| The Recycler deploys (`recyclerDeployed`) | rung 3, a plume at the beachhead geyser (vent 5) |
| The tug reaches the nav (`tugNearNav`) | rung 3 held, a 6 s surge (0.8) |
| The relic is aboard (`objective4Complete`) | rung 4, a 4 s quake (0.4) |
| The blast (`doingExplosion`) | a plume at the base vent (vent 1), a 5 s quake (0.7), a 6 s surge (1.0) |
| Victory (`won`) | release the forced level, back to rung 1 |

## Tests

```sh
lua5.1 Tools/Test-Chmisn01Coop.lua            # offline == faithful (6 outcomes), 1-4 peers, scaling, 460 m, fallback, cover, cameras, results, loads, weather
lua5.1 Tools/Test-Chmisn01Presentation.lua    # E/A/C protocol on a guest, the mission's local ops
python Tools/Test-Chmisn01CoopSourceParity.py # chmisn01cr.lua minus CR regions == ch01.lua
python Tools/Test-Chmisn01CoopContract.py     # labels/paths/teams/vents/subtitles in chmisn01cr.bzn (skips with a message if the map is absent; ini/vxt/mpdes only when present)
lua5.1 Tools/Test-Chinese01.lua               # the faithful port, unchanged
```

## Inferences and open questions

- The party cover (one escorted human, 100 m convoy radius) is a CR design decision; the DLL has one player. The tests cover the
  rule, not whether command and allied `Follow` orders work in the engine across teams 1 and 2-4.
- A guest cannot command team-1 fighters in the stock game; the host orders `Follow` on whichever human drives the tug. Whether an
  ally can be followed is unconfirmed.
- Scaling is per (frame, entry path), a CR inference. The tug, the escorts and the paratroopers are not scaled (see above).
- The restored blast place (`relic_loc`) and the 6 s lead of `ch01010` are inferences.
- The decoy tanks (team 1) and the escorts are the only mission units on the human team; they are shared, host-run.
- The out-of-lives path is not exercised by the host tests (leader departure is).
- The blast (`MakeExplosion`) runs on every peer as an effect; whether the engine applies its damage once or once per peer is unknown.
- The bzn carries an `[AOI]` entry on team 2 that nothing reads.

## Live checklist (unrun)

1. Opening: `ch01001` plays for everyone, 5 s in; the `CCA Base` nav is named and marked on every peer.
2. A guest inspects the hangar: the host's objective turns green on every peer (`I` packet), `ch01002`, then the armoury 15 s later.
3. Comm array destroyed: the Recycler arrives at the beachhead path (not at the origin), the objective list adds "Deploy your Recycler.";
   deploying changes it to "Protect your Recycler."
4. Waves 1-4, the paratroopers and the tug with 2-4 humans: extras appear, nothing pops in view.
5. Snipe the tug as a guest, drive it to the Recycler: no "got away" failure; the escorts, the 16-unit base wave and the relic appear.
6. Order the fighters to follow the driver; the other humans stay within 100 m: no detection near the towers; one human walking off
   past 100 m, or a missing fighter order, is detected (`ch01008` and `ch01lsec`) for everyone.
7. Relic aboard: the countdown shows on every peer, the nav `Safe Distance` is marked; the decoys come when any human nears a detector.
8. At T-6 s `ch01010`; at T-2 s the same finale shot on every peer (a skip does not end it), the white flash, the blast at the hangar,
   one shared result.
9. Tug lost / Recycler lost / relic too near the hangar: one shared failure with the right debrief.
10. Save during the countdown and during the finale shot and load: the clock, objectives, cover and shot come back.
11. Ganymede sky and plumes render on guests; no weather error in the log.
