# Mission S1 co-op: The Convoy Trap (misns1)

Shared offline / 2-4 player co-op port of the Soviet mission `misns1` (the Americans move their forces from one
geyser field to another through three passes; the Soviet player ambushes the Colorado convoy and then destroys the
American outpost). One `Missions/misns1cr.bzn` and one `Scripts/misns1cr.lua` serve both modes. Companion to
[`MISNS1_SOURCE_PORT.md`](MISNS1_SOURCE_PORT.md) (the faithful DLL port underneath, `Scripts/misns1.lua`) and
[`CCA_COOP_RUNTIME.md`](CCA_COOP_RUNTIME.md) (the shared runtime this mission is the first user of).
Status: **host-tested only**; nothing here has run in the game (see "Live checklist").

## Layout

| File | Role |
| --- | --- |
| `Scripts/misns1cr.lua` | The faithful port plus marked `-- CR ... >>` / `<<` regions. Outside them it is exactly `misns1.lua` (`Tools/Test-Misns1CoopSourceParity.py`). Holds the mission's runtime CONFIG, the native shadows and the restorations. |
| `Scripts/CRCCARuntime.lua` | Shared co-op runtime for all eight CCA missions (the generic parts of `CRMisn18.lua`, which is untouched). |
| `Scripts/CRVenusSitesS1.lua`, `Scripts/CRVenusWeather.lua` | Venus weather and the generated sulphur/vent sites for this map. |
| `Missions/misns1cr.{bzn,vxt}`, `misns1.{hg2,lgt,mat,trn}` | Map and companions (built by `Tools/Build-CoopMap.py`, not part of this change). |
| `Tools/Misns1Fixture.lua`, `Test-Misns1Coop.lua`, `Test-Misns1Presentation.lua`, `Test-Misns1CoopSourceParity.py`, `Test-Misns1CoopContract.py` | Multi-peer fixture and tests. `Test-Misns1.lua` / `Test-Misns1SourceParity.py` still cover the faithful port, unchanged. |

## Teams and ownership

| Team | Use |
| --- | --- |
| 1-4 | Humans (host on 1). The authored Soviet recycler (`svrecy2_recycler`) and the units the body builds for the Soviet side (walker, camera pods, two tanks, a fighter, two turrets) stay on team 1: shared, host-run. Extra starting recyclers are disabled. |
| 5 | The Americans (the authored team 2: Colorado, escorts, factory, silo, towers). The body still says team 2; the runtime maps `BuildObject(..., 2, ...)`, `SetScrap(2, ...)` and `SetAIP(name)` to team 5. |
| 7 | Support (allied to humans; nothing uses it in this mission). |

Only the authority (host, or the offline player) runs the body; guests only present (`Update` returns before the
body on guests). `SetAIControl(5, true)` runs once at chunk load; `SetAIP` only inside the body's `Update`.
`misn09.aip` / `misn14.aip` are issued with team 5, and the CR layer swaps them for `crns1a.aip` / `crns1b.aip`
(see stock bugs below).

The body never reads the player's ship: every trigger is NPC against NPC (Colorado, the walker, the cavalry,
`GetNearestEnemy(colorado)`). The nearest-/farthest-human wrapper (`PLAYERS` token + `WrapDistance`) is therefore
wired (`MissionDistance` is wrapped) but this mission has no use for it; the runtime test covers it for the
missions that do. `GetNearestEnemy(colorado)` now sees every human, so the retreat starts when ANY human comes
within 200 m of Colorado.

## Scaling and concealed arrivals [owner rules, mission decisions]

Scaled spawns: the ODFs `avfigh` and `avtank` (`scaledOdfs`). They become *tickets*: the body gets a negative
request id and the unit is built by the runtime on the next frame, with the body's later orders replayed on it.
Scavengers (`avscav`), turrets (`avturr`), the walker, pods and all Soviet-side builds are never scaled.

Events that get extras (one `BeginEvent()` each, in `-- CR co-op scaling >>` regions): the first cavalry craft, and
the first unit (a tank) of each of the three factory reinforcement waves. The first scaled unit the body then
builds is mirrored by `min(floor(humans / 2), 2)` extras of the same kind, entry and orders:

| Humans | Extras per event |
| --- | --- |
| 1 (offline) | 0 |
| 2 or 3 | 1 |
| 4 | 2 |

A wave of three therefore grows to 3 + extras. Cap: at most 12 live scaled units; extras are the only requests
dropped for it (primaries always spawn). Scrap: team 1's starting scrap is `20 + 10 per guest`; enemy scrap
(team 5) is 50.

No pop-in: a scripted unit is never built within 460 m of any human. An entry that is a map path is checked; if a
human is near it the next authored approach in `fallbackEntries` (`cavpath1`, `cavpath2`) is tried, else the
request waits (saved in `M.crcca`, so a save/load neither loses nor duplicates it). Units built AT the factory are
production, not pop-in, and are always allowed.

## Humans as one trigger

`GetPlayerHandle` returns the token `crcca_players` (the body does not call it today), and `WrapDistance` answers
the nearest human for ordinary targets and the farthest for targets named in `farthestTargets` (empty here). A
human with no live ship counts as infinitely far for a reach gate.

## Timer, win and loss

- Win: unchanged. Colorado, the outpost factory and the silo destroyed -> `misns110` -> `SucceedMission(...,
  "misns1w1.des")` once, on every peer (the runtime holds the result until every guest has acknowledged the
  preceding events, then publishes it with a few seconds of slack).
- Loss: Colorado reaches the safe point (both radio lines, then `misns1l1.des`) or the Soviet recycler dies
  (`misns112/113`, `misns1l2.des`). `FailMission` is ignored once `missionwon` has latched (nothing can fail a won
  mission in co-op; offline this also applies, a deliberate difference from the DLL for the overlap frame).
- Out of lives (every human out): the mission fails for everyone with `misns1l2.des` (the stock set has no better
  description).
- Leader departs: every guest fails the mission (`HasLeaderDeparted`).

## Cinematics are shared and unskippable in a network game [owner]

The loss shot (`CameraReady` + one `CameraObject` on Colorado) and the restored opening film are leader-driven and
streamed on the C channel; guests follow. `CameraCancelled` is false in a network game, so a skip never shortens
shared timing (a player's skip button only releases their own camera, as in misn18). Offline both stay skippable.
The DLL calls `CameraObject` once and does not repeat it; the runtime re-issues the last object shot every frame
(`holdCamera`) so every peer, and the offline game, holds the loss shot until the result. This is a CR inference.

## Restored content [owner decision 2026-11-01]

Cut-content restorations live only in the CR layer, apply offline and in co-op, and each has a flag
(`RESTORED_*` at the top of the runtime region of `misns1cr.lua`). Each is gated on what `misns1cr.bzn` carries.

| Restoration | Cut block it comes from | Status in this map |
| --- | --- | --- |
| Opening cinematic | the disabled `cindone`/`cintime` block: `cinpath3`, `cinpath4`, `geyserpath`, `CameraObject` on `hidcam1/2/3`, `walker1`, `walkcam1`, `approach`, `cinpath1`, finish at +66 s | The map lacks `cinpath3`, `cinpath4`, `geyserpath`, `approach`, `cinpath1` (absent), so the film runs only the object shots: `hidcam1/2/3`, `walker1`, `walkcam1` (27 s to 50 s of the original timeline). It starts at its first available shot and ends at its last; with no shot available it does not start. The `walkcam2/3` shots are skipped (those pods stay cut). `geyser2` does not exist, so the geyser shot would target `eggeizr10_geyser`. |
| Extra convoy escorts | `Follow(et3/et4, colorado, 1)`, `SetIndependence`, and the startup `RemoveObject(et3/et4)` | The two extra tanks (`avtank7/8_wingman`) are kept and follow Colorado like the others. |
| Extra cavalry | `cav4`, `cav5` (two more `avtank` at `cavspawn`), their `Goto`, and their share of the `walkcam1` route-1 warning (`misns118`) | Built one frame after the wave as ordinary (concealed) requests; not scaled. |
| Attack-wave dispatch | the commented `aw1sent`..`aw3sent` blocks (`Attack(awNa/b/c, svrec)`, `SetIndependence`) | Each factory wave of three attacks the Soviet recycler together once all three exist; co-op extras join. Captured by a `built` hook, so the faithful body is unchanged. |
| `geyser2` lookup | the commented `geyser2 = GetHandle("geyser2")` | Tried; nil in this map, so the loss shot keeps its Colorado anchor. |

Skipped, with the reason:

- Extra walkers and their pods (`walker2` at `spawnwalker2`, `walker3` at `walkstart3`, `walkcam2/3`) and the
  alternate trap triggers on them: the briefing (`misns101`) gives the player one hidden Golem to send to the
  cut-off beacon, so a second and third Golem contradict it. Only `spawnwalker2` exists on this map; `walkstart3`,
  `walkcam2`, `walkcam3` do not. The route-2 cavalry warning (`misns119`) needs `walkcam2` and so stays unreachable.
- Walker `Attack` / `SetIndependence` commands on retreat: the walker is the player's tool.
- The third and fourth cavalry route warning sequences (`misns120/121`, `cavpath3/4`): unreachable in the DLL
  (routes 2 and 3 reuse paths 1 and 2; `cavpath3/4` are never set) and the map has no such paths.

## Stock bugs fixed in the CR layer (the faithful body is untouched)

- The objective list is rebuilt every frame once the outpost factory and silo are both destroyed
  (`possible1 and possible2` keeps `newobjective` true). In co-op that would grow the event stream without bound;
  the runtime coalesces a `ClearObjectives`/`AddObjective` rebuild and publishes it only when the list changed.
- Audio: no stock-line substitution is needed (every line the body names has a subtitle in `Text/`);
  `audioSubstitute` is empty. Which wavs ship in every Redux language archive was not checked from this tree.
- The enemy base never rebuilt anything (reported by the owner: no AIP activity while the player must destroy the
  base factory). The stock body loads `misn09.aip` and `misn14.aip`, which are Soviet plans: every build item is an
  `sv*` unit or structure, and the American factory and recycler on this map cannot build those. The CR layer maps
  them to `ODF/crns1a.aip` and `ODF/crns1b.aip`, byte copies of the stock plans with only the build items switched to
  their American counterparts (`svscav`->`avscav`, `svturr`->`avturr`, `svfigh`->`avfigh`, `svtank`->`avtank`,
  `svrecy`/`svmuf`/`svslf`->`avrecy`/`avmuf`/`avslf`). Priorities, counts and the building-match lists are unchanged.
- The body already carries its own documented port fixes (see `MISNS1_SOURCE_PORT.md`).

## Weather: Venus

`Environment.Init` subtle lighting plus `CRVenusWeather` with the generated `CRVenusSitesS1`, networked exactly as
in `misn07cr` (seeded timeline from the host, host-chosen strikes/eruptions over the ordered stream, `Save`/`Load`
state, `AnnounceState`). If the weather module or the sites module is missing, or any weather call errors, the
mission runs without weather and logs once. Beats (host/offline only): level 3 when the convoy retreats or is
lost, level 4 when the cavalry wave arrives, back to level 2 on victory. The director never damages.

## Map content the script never uses

Paths: `amatbase`, `cloradosucceds`, `edge_path` (used by the weather), `trigupper`, `trigmiddle`, `triglower`
(the original pass triggers; the DLL checks Colorado against the pods instead), `spawnwalker2`.
Cut paths absent from this map: `cinpath3`, `cinpath4`, `geyserpath`, `approach`, `cinpath1`, `walkcam2`,
`walkcam3`, `walkstart3`, `spawnwalker3`. Objects: `svtank0_wingman`, the three `avturr*_turrettank`, the towers,
power plants, scrap and the extra geysers are authored scenery/defences the script does not touch.

## Tests

```sh
lua5.1 Tools/Test-Misns1Coop.lua            # offline == faithful, 1-4 peers, scaling, 460 m, cameras, audio, results, weather
lua5.1 Tools/Test-Misns1Presentation.lua    # E/A/C protocol on a guest
python Tools/Test-Misns1CoopSourceParity.py # misns1cr.lua minus CR regions == misns1.lua
python Tools/Test-Misns1CoopContract.py     # labels/paths/teams in misns1cr.bzn (skips with a message if the map is absent)
lua5.1 Tools/Test-Misns1.lua && python Tools/Test-Misns1SourceParity.py   # the faithful port, unchanged
```

The workflow `.github/workflows/campaign-validation.yml` is not yet wired to run the four new tests (shared file).

## Inferences and open questions

- Cinematic timing is the DLL's, shortened to the shots the map supports; whether a ~23 s lock on all players suits
  the opening in play is untested.
- The held loss shot, the dispatch restoration and the extra escorts/cavalry are CR inferences; each can be
  switched off with its `RESTORED_*` flag.
- `fallbackEntries` assumes `cavpath1`/`cavpath2` start somewhere usable as an alternative entrance.
- Factory units may appear at the factory in front of a nearby human (treated as production).
- The out-of-lives path is not exercised by the host tests (leader departure is).

## Live checklist (unrun)

1. Cavalry arrives out of sight with 2-4 humans; extras follow the same route.
2. Opening film: guests see the same shots; all cameras balanced afterwards.
3. Loss shot holds and ends with the result on every peer.
4. `crns1a.aip` / `crns1b.aip` (the American replacements for `misn09.aip` / `misn14.aip`) actually build and send units for team 5; wave dispatch does not double-order them.
5. Walker cut-off still works with several humans (ordering the shared walker).
6. Venus sky renders on guests; no weather error in the log.
7. Objective list stable (no flicker) after both outpost structures fall.
