# CRCCARuntime: shared co-op runtime for the CCA missions (misns1..misns8)

`Scripts/CRCCARuntime.lua` is the mission-agnostic runtime extracted from `CRMisn18.lua` (which is unchanged).
A mission keeps its faithful DLL port byte-for-byte and adds `-- CR ... >>` / `<<` regions (the source-parity test
strips them and demands the original). The pattern is `Scripts/misns1cr.lua` (first user); copy it:

The eight Soviet CCA missions opt into `blackDogUnits`. Their original NSDF ODF requests resolve to matching Black Dog
ODFs for scripted spawns and `IsOdf` checks; authored map labels stay unchanged so mission logic and save states still
find the same objects. The map files use Black Dog ODFs directly.

1. Chunk-root region, after `M = NewState()` and before the helper locals:
   `local campaignRuntime = not CR_TEST_FAITHFUL and require("CRCCARuntime").Create(function() return M end, CONFIG)`
   then `local X = campaignRuntime and campaignRuntime.X or X` for every native the body calls (list below).
   `Create` runs `SetAIControl(enemyTeam, true)` at chunk load: nowhere else.
2. `-- CR co-op callback >>` regions: after `M = NewState()` in `Start` (`campaignRuntime.Start()`), first line of
   `Update` (`if campaignRuntime and not campaignRuntime.Update(dt) then return end`), last line of `Update`
   (`AfterUpdate()`), in `Save` (before `return M`) and `Load` (after `M = state`); plus the engine callbacks
   `AddObject/CreatePlayer/AddPlayer/DeletePlayer/Receive` at file end (`-- CR co-op callbacks >>`).
3. `-- CR co-op scaling >>` with `campaignRuntime.BeginEvent()` before the first scaled spawn of an event.
4. Mission-specific restorations: define them in a chunk-root `-- CR restored content >>` region (after the body's
   helpers so they can use them) and call a `Step()` from a region in `Update`. Gate each on a `RESTORED_*` flag
   and on `R.PathExists(path)` / `Valid(handle)` for map content.

Rules the runtime enforces: only the authority runs the body (`Update` returns false on guests, on a departed
leader, before the session is ready, after a result); nothing scripted spawns within `safeRadius` of a human;
cutscenes are shared and unskippable in a network game; every optional subsystem is `pcall`'d.

## CONFIG

| Key | Default | Meaning |
| --- | --- | --- |
| `id` | `"cca"` | Log prefix. |
| `leaderTeam` | 1 | The host's team (also the shared-scrap team). |
| `enemyTeam` | 5 | The co-op enemy. `SetAIControl(enemyTeam, true)` at chunk load; `SetAIP` always uses it. |
| `mapEnemyTeam` | 2 | The team the faithful body still says; mapped to `enemyTeam` in `Spawn`, `SetScrap`, `SetAIP`. |
| `blackDogUnits` | `false` | Resolve the CCA missions' original NSDF ODF names to their Black Dog equivalents for spawns and class checks. |
| `supportTeam` | 7 | Allied to humans. |
| `hostileTeams` | `{enemyTeam}` | Teams un-allied from the humans. |
| `rallyPoints` | nil | `{[0]="label"}` for the respawn service (the shared base). |
| `scaledOdfs` | `{}` | `{odf=true}`: spawns of these ODFs become tickets and take part in scaling/concealment. Others pass straight to `BuildObject` (team mapped). |
| `fallbackEntries` | `{}` | Authored paths tried (in order) when a spawn path is within `safeRadius` of a human. |
| `safeRadius` | 460 | No scripted build this close to any human. A spawn at an object (factory) is exempt. |
| `liveCap` | 12 | Max live scaled units; only extras are dropped for it. |
| `maxExtrasPerEvent` | 2 | `floor(humans/2)` is capped at this. |
| `scrapPerGuest` | 10 | Extra starting scrap on `leaderTeam` per guest. |
| `buildsPerFrame` | 2 | Arrivals built per frame. |
| `failDes` | nil | `.des` for the out-of-lives failure. |
| `wonFlags` | `{}` | State fields; once one is true `FailMission` is ignored. |
| `endedFlags` | `{}` | State fields; once one is true pending requests are dropped. |
| `farthestTargets` | `{}` | Labels or state-field names (e.g. `"avrec"`) for which the `PLAYERS` token's distance is the FARTHEST human (reach gates); all other targets are nearest. |
| `audioSubstitute` | `{}` | `{["wrong.wav"]="right.wav"}` for lines the DLL names wrongly. |
| `holdCamera` | false | Re-issue the last `CameraObject` every frame (for DLL one-shot object cameras). |
| `orders` | Goto, Follow, Attack, Defend, Defend2, SetIndependence, Retreat | Order names exposed as `R.<Name>`; orders on tickets are recorded and replayed (on the primary's extras too); an order targeting another ticket is rewritten to the real handle when that ticket is built. |
| `presentationOps` | `{}` | `{Name=function(...)}` ops run on every peer through the ordered stream (`Present("Name", ...)`). |
| `environment` | nil | `Environment.Init` options when there is no weather. |
| `weather` | nil | `{module="CRVenusWeather", sites="CRVenusSitesS1", environment=..., startLevel, targetLevel, ops={...}, beats=function(module, M, state)}`. Missing/failing modules disable weather, never the mission. `beats` runs on the authority each frame. |
| `hooks` | `{}` | `start(R)`, `load(R)`, `update(R, dt, authority)` (every peer), `afterUpdate(R)`, `save(R, state)`, `addObject(R, h)`, `chooseOdf(R, odf, M)`, `heldArrivals(R, M)`, `built(R, handle, request, id)` (a ticket was built; `request.extra`, `.where`, `.odf`, `.team`), `outOfLives()` (every human out of lives; overrides the default `Failure()`/`FailMission(failDes)` for a mission whose own ending is not a plain failure, e.g. `evolvecr`'s score-chosen `SucceedMission`). |

## API (`R`)

Natives to shadow: `Spawn` (for `BuildObject`), `IsOdf` (through `MapOdf`), `IsValid`, `IsAlive`, `GetDistance`, `GetNearestEnemy` (tickets are
valid, alive and infinitely far), `SetScrap`, `SetAIP`, the order names, `AudioMessage`, `StopAudioMessage`,
`CameraReady/Path/Object/Finish/Cancelled`, `ClearObjectives/AddObjective/UpdateObjective`,
`SetObjectiveName/On/Off`, `RemoveObject`, `SucceedMission`, `FailMission`.
`StartCockpitTimerUp` joins `StartCockpitTimer`/`StopCockpitTimer`/`HideCockpitTimer` in the plain native dispatch table
(presented, since the cockpit timer widget is local-client UI state, not team economy that the engine already
replicates). Also: `BeginEvent()`, `WrapDistance(original)`, `GetPlayerHandle()` (the `PLAYERS` token, also `R.PLAYERS`),
`PathExists(name)`, `HumanCount()`, `State()` (the saved `M.crcca` table; keep restoration state in `State().r`),
`Present(op, ...)`, `Start/Update/AfterUpdate/Save/Load/AddObject/CreatePlayer/AddPlayer/DeletePlayer/Receive`,
and `Coop/Exu/Native/Weather`. `R.MapOdf(name)` is the mission-scoped unit-name resolver used by `Spawn` and `R.IsOdf`.

Single-player difficulty (co-op locks it, so a network game ignores it): when `DiffUtils` loads, each scaled spawn
on the enemy team gets `enemy - 1` extras on average (Hard 0.5, randomly rounded; Very Hard 1), queued and capped like
co-op extras; like those, they receive only the orders queued while the ticket is pending. `SetScrap` gives the leader
`DiffUtils.ScaleRes(amount)` clamped to capacity (a fill to capacity stays a fill) and the enemy
`max(amount, DiffUtils.ScaleEnemy(amount))`, so a body's "at least N" top-up still holds on easier settings. Easier
settings never remove units (the body tracks their handles) and timers are not scaled. `Tools/RuntimeTests/Test-CRCCARuntimeDifficulty.lua`
covers it; fixtures that do not provide `DiffUtils` run unscaled.

State: everything the runtime saves lives in `M.crcca` (tickets, live list, weather seed/state). `M.coopResult`,
`M.coopFailed`, `M.coopPendingResult`, `M.coopUnresolved` are also written to the mission state.

## Pitfalls

- Helper locals in the body that test `IsValid(h)` before ordering (`Valid(h)`) must see tickets as valid: shadow
  `IsValid` BEFORE they are declared (the chunk-root region sits above them).
- `Update` only runs the body on the authority; guests call `Update` for presentation and weather only.
- Objective lists are coalesced: a rebuild identical to the last published one is dropped.
- Lua packet strings of 128-255 bytes crash peers: the runtime sends everything through `CRWire`.
- The test fixture for a new mission copies `Tools/MissionTests/Misns1Fixture.lua` (labels, paths, module stubs).
- Not carried over from `CRMisn18`: storm, extraction ending, left-behind camera, Fury roster, phases.
