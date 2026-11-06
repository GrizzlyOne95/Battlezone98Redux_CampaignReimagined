# Black Dog 14 co-op: Lifeline (bdmisn14)

Shared offline / 2-4 player co-op port of the Black Dog mission `bd14` (the last Chinese base on Ganymede that can build a
portal is mined and ringed with gun towers; a Chinese APC with the portal technology is on its way and must be stopped
before it reaches the base; then the Chinese Recycler must die). One `Missions/bd14cr.bzn` and one
`Scripts/bd14cr.lua` serve both modes. Companion to the faithful DLL port underneath (`Scripts/bdmisn14.lua`, see
[`BLACKDOG14_LUA_PORT.md`](BLACKDOG14_LUA_PORT.md), tested by `Tests/test_bdmisn14.lua`) and
[`CCA_COOP_RUNTIME.md`](CCA_COOP_RUNTIME.md) (the shared runtime). Pattern: [`MISNS2_COOP.md`](MISNS2_COOP.md) and
[`BDMISN08_COOP.md`](BDMISN08_COOP.md).
Status: **host-tested only**; nothing here has run in the game (see "Live checklist").

## Layout

| File | Role |
| --- | --- |
| `Scripts/bd14cr.lua` | The faithful port plus marked `-- CR ... >>` / `<<` regions. Outside them it is exactly `bdmisn14.lua` (`Tools/Test-Bdmisn14CoopSourceParity.py`). Holds the runtime CONFIG, the native shadows and the restoration. |
| `Scripts/CRGanymedeSitesBD14.lua`, `Scripts/CREuropaWeather.lua` | Ganymede weather (the Europa director with the generated sites for this map: five cryovolcanic vents, two of them the geysers `eggeizr13_geyser` and `eggeizr15_geyser` under the Chinese factory and Recycler). |
| `Missions/bd14cr.{bzn,vxt}`, `bdmisn14.{hg2,lgt,mat,trn}`, `Config/bd14cr.ini` | Map, vehicle list and multiplayer listing (not part of this change). The map carries the Black Dog base, the Chinese base with its towers, mines and howitzers, and nothing that is scripted: every attacker is made by Lua. |
| `Tools/Bdmisn14Fixture.lua`, `Test-Bdmisn14Coop.lua`, `Test-Bdmisn14CoopSourceParity.py`, `Test-Bdmisn14CoopContract.py` | Multi-peer fixture and tests (real map coordinates). The mission has **no cameras**, so there is no Presentation suite. `Tests/test_bdmisn14.lua` still covers the faithful port, unchanged. |

## Teams and ownership

| Team | Use |
| --- | --- |
| 1-4 | Humans (host on 1). The authored Black Dog side (the Recycler, the wingmen, the four gun towers) stays on team 1: shared, host-run. Extra starting recyclers are disabled. |
| 5 | The Chinese: the base, the cloaked starting units and every attacker, the APC and the scavengers. The body still says team 2; the runtime maps `BuildObject(..., 2, ...)`, `SetScrap(2, ...)` and `SetAIP(...)` to team 5, and one CR shadow does the same for `SetPilot(2, 100)`. The map is authored with the Chinese on team 5 already. |
| 7 | Support (nothing uses it here). |

Only the authority (host, or the offline player) runs the body; guests only present. `SetAIControl(5, true)` runs once at
chunk load. `SetAIP("bdmisn14.aip")` reaches team 5. `SetScrap(1, 4)` becomes the shared pool plus 10 per guest
(`scrapPerGuest`); `SetPilot(1, 10)` goes to every human team (each human respawns from its own pool) and the Chinese 100
pilots go to team 5. Respawns rally on the Recycler.

### Humans as the player

The DLL's "player" is `GetPlayerHandle()`, one tank, used in exactly one place: the two proximity ambushes
(`GetDistance(user, "trigger_attack_1") < 150`, `"trigger_attack_2"`). In co-op the CR layer answers it with the runtime's
nearest-human token (`crcca_players`), so the ambushes fire for **any** human of any team, whoever is closest. They are
approach triggers (nearest human); `farthestTargets` is empty. Two shadows make that work:

- `IsValid(token)` is true (the body's `Valid(user)` guard). With no living human the token is infinitely far, so nothing
  springs and nothing errors.
- `GetDistance` forwards its third argument. The runtime's `WrapDistance` passes two arguments only; the CR shadow
  answers the nearest-human token and calls the native with all arguments for everything else. (The body's APC arrival
  test now reads `GetPosition` for the craft and the last waypoint instead.)

Nothing else reads the player. The body has no player-death loss; the shared lives are CRCoop's.

## Scaling and concealed arrivals [owner rules, mission decisions]

Scaled spawns: the ODFs `cvfigh`, `cvhraz`, `cvhtnk`, `cvltnk`, `cvwalk`, `cvtnk`, `cvtnkc` (every attack wave, ambush and
the APC's escort) and the restored `cvturr`. They become *tickets*: the body gets a negative request id and the unit is
built by the runtime on the next frames (two per frame), with the body's later orders replayed on it (`Follow(cargo tank,
walker)` is rewritten to the real walker; `Defend2(escort, apc)` to the real APC; `SetCloaked` waits for the real unit).
Not scaled: the APC (`cvapcc`, the body keeps its handle for the marker, the route and the loss test) and the two
scavengers (`cvscav`).

Events: **a new frame or a new entry path is a new scaling event**, and the first scaled unit of an event is mirrored by
`min(floor(humans / 2), 2)` extras of the same kind, entry and orders.

| Humans | Extras per event |
| --- | --- |
| 1 (offline) | 0 |
| 2 or 3 | 1 |
| 4 | 2 |

| Event | Where | Primaries |
| --- | --- | --- |
| Initial raid (at the start) | `spawn_initial_attack` | 3 `cvfigh`, 1 `cvhraz` |
| The big assault (4 min) | `spawn_attack_waves` | 2 `cvhtnk`, 4 `cvfigh`, 1 `cvltnk`, 2 `cvtnk` |
| APC escort (9 min) | `spawn_apc` | 4 `cvtnk` |
| APC attackers (9 min) | `spawn_attack_waves` | 2 `cvhraz`, 1 `cvltnk`, 2 `cvfigh`, 3 `cvwalk`, 3 `cvtnkc` |
| Restored turret convoy (9 min) | `spawn_turrets` | 3 `cvturr` |
| Base ambush (human within 150 m of `trigger_attack_1`) | `spawn_attack_1`, `spawn_defend` | 2 `cvhraz` + 2 `cvltnk` + 2 `cvtnk` + 2 `cvfigh`; 2 `cvwalk` + 5 `cvltnk` |
| Western ambush (within 150 m of `trigger_attack_2`) | `spawn_attack_2` | 3 `cvltnk`, 2 `cvtnk` |

Cap: at most **24** live scaled units (`liveCap`; the runtime default is 12). The nine-minute convoy alone is 21 primaries
and 24 with a single extra each; extras are the only requests dropped for the cap, primaries always arrive.

No pop-in: a ticket is never built within **120 m** of a human (`safeRadius`; the runtime default is 460 m). The Chinese
waves leave from inside their own base, `spawn_attack_waves` is 23 m from `trigger_attack_1`, and the ambush fires at 150 m,
so the default ring would hold back every wave of a siege. 120 m keeps a unit from appearing in a human's face while the
siege waves still leave the base. If a human watches the authored spawn, the next hidden eastern staging point in
`fallbackEntries` is used (`spawn_attack_1`, `spawn_apc`, `spawn_turrets`, first that is clear), else the request waits
(saved in `M.crcca`, so a save/load neither loses nor duplicates it). Nothing more is built once the result is decided
(`endedFlags = { "wonLost" }`). The wave units are cloaked, so a pop-in would also be invisible; the ring is for the
extras and the uncloaked escorts, turrets and cargo tanks.

Known exception, not concealed: the APC, built where and when the DLL builds it (`spawn_apc` is on the far east edge,
about 1700 m from the Black Dog start); the two scavengers.

## Humans' result, win and loss

- Win: unchanged. The Chinese Recycler dies -> `bd14006` -> `SucceedMission(..., "bd14win.des")` once (the runtime holds
  the result until every guest acknowledged the preceding events). A late out-of-lives failure is ignored
  (`wonFlags = { "objective3Complete" }`). The Recycler win beats a simultaneous Black Dog Recycler loss, as in the DLL
  (SOE #8 before #10).
- Loss, APC: the APC reaches the last waypoint of `path_apc_travel` alive -> `bd14007` -> red objectives ->
  `bd14lsea.des`. A dead APC (the intercept) is no loss even if its wreck lies at the end, see below.
- Loss, Recycler: the Black Dog Recycler dies -> `bd14008` -> `bd14lseb.des`.
- Out of lives (every human out): `bd14lose.des`, the stock generic debrief the DLL never names (its text is the APC
  debrief). Leader departs: every guest fails.
- The intercept is the APC dying (`bd14005`, the Recycler objective, the scavengers 4 min later). It is not required for
  the win, as in the DLL.

## Cinematics

None. The DLL declares `cameraReady`/`cameraComplete` and never uses them; the CR layer wraps no camera call.

## Restored content [owner decision 2026-11-01]

Cut-content restorations live only in the CR layer, apply offline and in co-op, and each has a flag (`RESTORED_*` at the
top of the runtime region of `bd14cr.lua`). Each is gated on what `bd14cr.bzn` carries.

| Restoration | Cut block it comes from | Status in this map |
| --- | --- | --- |
| Turret convoy (`RESTORED_TURRET_CONVOY`) | the `#if 0` block of SOE #5, kept as a comment in the Lua port: `// turrets`, then three times `h = BuildObject("cvturr", 2, "spawn_turrets"); Goto(h, "path_turrets");` | The map has the two paths: `spawn_turrets` (2180, 101371, beside the APC's `spawn_apc`) and `path_turrets` (five points to 1848, 101193, east of the Chinese base). Three Chinese turret tanks are built in the frame the body builds the APC and drive in behind it, as concealed, head-count-scaled tickets. They get no cloak (the cut block has none). Built once (latched in `M.crcca.r`), never after the result. |

Skipped, with the reason:

- `// SOE #4 (missing)`: nothing was ever written for it; there is nothing to restore.
- Dormant state the DLL declares and never reads (`objective1Complete`, `cameraReady`, `cameraComplete`): no behaviour.
- The cut block's rationale is unknown. The map and the audio are coherent with it (the APC briefing talks about "the equipment",
  the towers are a stated threat in `bd14001`), so it is restored; set `RESTORED_TURRET_CONVOY = false` to drop it.

Authored paths the script never uses (documented, not wired): `edge_path` (used by the weather as the playable box),
`path_walk_1`, `path_walk_2` and `path_walk_3` (two-point stubs inside the Chinese base), `path_1` (two paths of this
name: a 23-point route from the east edge to the Black Dog base, and a single point beside the Black Dog base), `path_2`
(likewise: a 29-point route from the east edge, and a single point), `path_3` and `path_4` (single points beside the
Black Dog base) and `path_recycler` (four points leaving the Black Dog base). None of them is named by the C++ source or
by any block, active or cut; the `bdmisn14.aip` the DLL loads is not in this tree, so the strategic AI may use some of
them. The intent is undocumented, so nothing is guessed from them. Unlabelled paths in the map (two points each, no
name) are leftover AI scratch routes.

### Voice lines [owner decision 2026-11-01]

The shipped lines are `bd14001`..`bd14008` (wavs plus `Text/` transcripts, durations in `Config/durations.csv`; the game's
own audio manifest lists no other `bd14` line). The faithful body plays **all eight**, so there is no unused voice line to
slot in. The contract test asserts the script (body plus CR layer) names exactly the lines the repo has transcripts for.
The unused shipped debrief `bd14lose.des` is the out-of-lives failure.

## Stock bugs fixed in the CR layer (the faithful body is untouched)

- **One human as "the player"**: the ambush triggers take one tank. See "Humans as the player".
- **A waypoint index lost by the human-distance wrapper**: see "Humans as the player" (a trap in the shared helper,
  neutralised here; the runtime is untouched).
- **The Chinese pilots on team 2**: `SetPilot(2, 100)` would give a human slot 100 pilots and the Chinese none; the CR
  shadow maps it to team 5. The other team-2 calls (`BuildObject`, `SetScrap`, `SetAIP`) go through the runtime.
- **A nil audio handle**: every win and loss gate tests `sound ~= nil and Done(sound)`, so a line that returns no handle
  would strand the ending for ever. The CR `AudioMessage` yields 0 instead of nil and `IsAudioMessageDone` counts nil/0 as
  done.
- **The late warning**: `bd14004` ("that APC's getting a little too close for comfort") is on a 50 s timer after the APC is
  built and plays even when the APC was destroyed seconds after it appeared (right after "Good work", `bd14005`) or when
  the mission is decided. The CR layer drops it for a destroyed APC or a decided result.
- **Cloaks on tickets**: the body cloaks each unit right after building it; for a ticket the cloak waits for the real unit
  (and for the extras that mirror it). `SetCloaked` of a build refused after the result (nil) is ignored.
- **Objectives and the APC marker after a load**: the runtime's `Load` resets the presentation (objective list,
  `SetObjectiveOn`), and the body publishes them only when a stage begins. After a load (authority, first frame) the CR
  layer rebuilds the whole list from the mission state with the body's own names and colours: raid launched `bd14001`
  white; SkyEye reported `bd14001`, `bd14002` white; APC intercepted `bd14002` green, `bd14003` white; Recycler down both
  green; loss narration pending `bd14001`, `bd14002` red; and marks the living APC again.
- **Reinforcements after the result**: pending tickets are dropped once the mission is won or lost.
- Objective rebuilds are coalesced by the runtime (a rebuild identical to the last published list is dropped).
- Audio: every line has a subtitle in `Text/` (`Test-Bdmisn14CoopContract.py`); `audioSubstitute` is empty. The `.des`
  debriefs ship with the game.
- The body already carries its own documented port fixes ([`BLACKDOG14_LUA_PORT.md`](BLACKDOG14_LUA_PORT.md): the walkers
  are cloaked instead of the last light tank, a destroyed APC cannot also lose the intercept, missing handles count as
  zero health, the native `isAtEndOfPath` is the TRO 1.3 12 m 2D distance to the last waypoint).

## Weather: Ganymede

`Environment.Init` in `orbit` mode (the sun's real path, a short eclipse, Jupiter-shine at night: the same options as
`bd03cr`..`bd12cr`) plus `CREuropaWeather` with `CRGanymedeSitesBD14`, networked through the runtime (seeded
timeline from the host, host-chosen plumes/quakes/surges over the ordered stream as
`EuropaState`/`EuropaPlume`/`EuropaQuake`/`EuropaSurge`, `Save`/`Load` state, `AnnounceState`). No new weather module:
Ganymede reuses the Europa director for an icy, airless Jovian moon. `Environment.BindWeatherSensors("Ganymede", ...)` is
registered once per start from the runtime's update hook on every peer. If the module or the sites module is missing, or
any weather call errors, the mission runs without weather and logs once. The site file has five vents (two beside the
Black Dog start, `eggeizr13_geyser` under the Chinese factory and `eggeizr15_geyser` under the Chinese Recycler, whose
positions match the buildings), so plumes stay enabled.

Beats (host/offline only, each once, tied to the mission's own moments; the director never damages):

| Moment | Weather |
| --- | --- |
| Start | level 1 (Quiescent) |
| The first raid leaves (`initialTime` fired) | level 2 |
| The big cloaked assault (`wavesTime` fired, 4 min) | level 3 and a quake (0.35, 3 s) |
| The base ambush springs (`attack1`) | a quake (0.3, 2.5 s) and a plume from the factory's geyser |
| The western ambush springs (`attack2`) | a quake (0.3, 2.5 s) and a plume from the Recycler's geyser |
| The APC is built (`apc`, `bd14003`) | level 4, a quake (0.5, 3.5 s) and a surge (5 s, 0.9) |
| The APC is destroyed (`objective2Complete`, `bd14005`) | level 3 and a quake (0.4, 3 s) |
| The Chinese Recycler falls (`objective3Complete`, `bd14006`) | a quake (0.5, 3.5 s), a plume from the Recycler's geyser, then level 2 for the debrief |
| The mission is lost (`wonLost`, no win: the pegasus arrives or the Black Dog Recycler is gone) | a surge (6 s, 0.8) and a quake (0.35, 3 s) |

## Tests

```sh
lua5.1 Tools/Test-Bdmisn14Coop.lua            # offline == faithful, 1-4 peers, scaling, 120 m, fallback, results, load, weather
python Tools/Test-Bdmisn14CoopSourceParity.py # bd14cr.lua minus CR regions == bdmisn14.lua
python Tools/Test-Bdmisn14CoopContract.py     # labels/paths/teams in bd14cr.bzn (skips with a message if the map is absent)
lua5.1 Tests/test_bdmisn14.lua                # the faithful port, unchanged
```

The workflow `.github/workflows/campaign-validation.yml` is not edited by this change; the three co-op commands above are
the step to add. The contract test checks `Config/bd14cr.ini` and `Missions/bd14cr.vxt` only when they are in the
tree.

## Inferences and open questions

- Scaling is per (frame, entry path), a CR inference shared with the other missions: a group mirrors only its first unit,
  so a 14-unit APC wave grows by two units at four players. `liveCap = 24` and `safeRadius = 120` are CR choices.
- The APC arrival radius is the TRO 1.3 `isAtEndOfPath` value: 12 m, measured in the (x, z) plane to the last
  waypoint. With several humans nothing about it changes.
- The restored turret convoy is untested against the real map: whether three turret tanks at `path_turrets` make the
  intercept feel unfair (they park east of the base) is a playtest question.
- The three fallback staging points are all on the eastern edge. A human who watches the west spawn (`spawn_attack_2`)
  gets that ambush from the east.
- The mock `GetDistance` models only the last waypoint of `path_apc_travel`.
- The out-of-lives path is not exercised by the host tests (leader departure is).

## Live checklist (unrun)

1. Start: `bd14001`, one white objective at once; the six cloaked starters stay put; the first raid (5 cloaked craft plus
   1-2 extras) heads for the Black Dog base from the east; Ganymede sky at level 1 then 2.
2. 2 min: `bd14002`, the objective list shows both lines on every peer.
3. 4 min: the big cloaked assault leaves the Chinese base (level 3, a quake); with 2-4 humans each wave has twins; none on
   team 2; the attackers are hostile to every human team.
4. A human of ANY team within 150 m of the north gate springs the base ambush (quake, plume under the factory); a human
   at the west gate springs the other; with a human standing on the defenders' spawn they arrive from the east instead.
5. 9 min: the APC appears on the far east edge, marked on every peer, `bd14003`, level 4 with a quake and surge; four
   escort tanks defend it, three turret tanks (restored) ride in behind; 50 s later `bd14004`.
6. Destroy the APC: `bd14005`, objective 2 green, marker gone, `bd14004` never plays late; the scavengers return 4 min later.
7. Let the APC reach the Chinese base alive: `bd14007`, red objectives, `bd14lsea.des`, one shared failure. A wreck at
   the end of the route is not a loss.
8. Destroy the Chinese Recycler: `bd14006`, both objectives green, one shared victory (`bd14win.des`), the geyser under
   the Recycler erupts, the sky eases. Losing the Black Dog Recycler plays `bd14008` and fails with `bd14lseb.des`.
9. A save/load mid-mission: the objective list and the APC marker come back, nothing is built twice; no weather error in
   the log.
