# Mission S7 co-op: Reclaim our Base (misns7)

Shared offline / 2-4 player co-op port of the Soviet mission `misns7` (take the APC to the northern outpost, destroy
the Black Dog prison, rescue the engineers, restore the Recycler, the Unit Factory and the supply depot, then destroy
the NSDF Recycler). One `Missions/misns7cr.bzn` and one `Scripts/misns7cr.lua` serve both modes. Companion to
[`MISNS7_SOURCE_PORT.md`](MISNS7_SOURCE_PORT.md) (the faithful DLL port underneath, `Scripts/misns7.lua`) and
[`CCA_COOP_RUNTIME.md`](CCA_COOP_RUNTIME.md) (the shared runtime). Status: **host-tested only**; nothing here has run
in the game (see "Live checklist").

## Layout

| File | Role |
| --- | --- |
| `Scripts/misns7cr.lua` | The faithful port plus marked `-- CR ... >>` / `<<` regions. Outside them it is exactly `misns7.lua` (`Tools/Test-Misns7CoopSourceParity.py`). Holds the runtime CONFIG, the native shadows, the restorations and the Titan beats. |
| `Scripts/CRCCARuntime.lua` | Shared co-op runtime (unchanged by this port). |
| `Scripts/CRTitanWeather.lua`, `Scripts/CRTitanSitesS7.lua` | Titan weather director and the generated sites for this map. The S7 sites tables are EMPTY (no methane pools, no wet mask); the weather still runs (sky and haze ladder, rolls). |
| `Missions/misns7cr.{bzn,vxt}`, `misns7.{hg2,lgt,mat,trn}` | Map and companions (built by `Tools/Build-CoopMap.py`, not part of this change). |
| `Tools/Misns7Fixture.lua`, `Test-Misns7Coop.lua`, `Test-Misns7Presentation.lua`, `Test-Misns7CoopSourceParity.py`, `Test-Misns7CoopContract.py` | Multi-peer fixture and tests. `Test-Misns7.lua` / `Test-Misns7SourceParity.py` still cover the faithful port, unchanged. |

One deliberate difference from `misns1cr.lua`: the body's own `AddObject` does real work (it fills the NSDF unit
slots), so the wrapper does NOT define a second `AddObject` at the end of the file. The CR layer forwards to the
runtime from inside the body's `AddObject` (`-- CR co-op callback >>` region) and the file-end region defines only
`CreatePlayer`, `AddPlayer`, `DeletePlayer` and `Receive`.

## Teams and ownership

| Team | Use |
| --- | --- |
| 1-4 | Humans (host on 1). The Soviet side the body builds (engineers, the restored Recycler and Factory, the supply cache) is team 1: shared, host-run. Extra starting recyclers are disabled. |
| 5 | The NSDF (the authored team 2: prison, Recycler, rig, scavengers, towers, fighters). The body still says team 2; the layer maps it to 5 everywhere (below). |
| 7 | Support (nothing uses it in this mission). |

Only the authority (host, or the offline player) runs the body; guests only present. `SetAIControl(5, true)` runs
once at chunk load (runtime). The body's `Start` calls `SetAIControl(2, true)`: the layer shadows it to a no-op
(AI control belongs at chunk root and on the co-op enemy only). `SetAIP` is called only inside `Update`.

Every literal enemy team 2 in the body goes through the layer:

| Body call | CR layer |
| --- | --- |
| `BuildObject(odf, 2, ...)` | runtime `Spawn` maps 2 -> 5 |
| `SetScrap(2, 40)`, `SetAIP("misns7*.aip")` | runtime `SetScrap` / `SetAIP` (team 5) |
| `AddScrap(2, ...)` | shadow: 2 -> 5. `AddScrap(1, 20)` rewards stay on the shared base |
| `SetPerceivedTeam(h, 2)` | shadow: 2 -> 5 (and skipped when the tower/recycler is gone). The map carries five Soviet objects (`guntower1`, `guntower2`, `svrecycle`, `stuff1`, `stuff2`) already authored with perceived team 5; the body re-applies the disguise to the towers and the Recycler. |
| `CountUnitsNearObject(apc, 200, 2, nil)` | shadow: 2 -> 5 (the "no enemy near the APC" briefing gates) |
| `SetPilot(2, 40)` | team 5 |

## Humans as one trigger

`GetPlayerHandle` returns the token `crcca_players`; `Distance` (the body's helper) is wrapped with the runtime's
`WrapDistance`, so "the player" is the NEAREST human for every use in this mission: prison found (<150 m), locked
supply hut (<70 m), NSDF rig removed only when every human is more than 400 m away, rig rebuilt when any human is
within 400 m of the NSDF Recycler, the silo message (<90 m). `farthestTargets` is empty: no gate here needs every
human.

`Attack(fighter, player)` cannot take a token: the layer resolves it to the living human nearest `muf_point`
(else the APC) when the order is issued, so every fighter, scaled or extra, gets a real target.

## Scaling and concealed arrivals [owner rules, mission decisions]

Scaled spawns: the ODF `bvraz` (`scaledOdfs`): the NSDF fighters. They become *tickets* (negative request ids) built
by the runtime on the next frame with the body's later orders replayed on them. Scavengers, turrets, the NSDF
Factory, the walker, the rig and every Soviet-side build are never scaled; the units the AIPs build are the engine
AI's own and cannot be scaled.

Five `BeginEvent()` sites (`-- CR co-op scaling >>`), one before each `BuildObject("bvraz", ...)` of the body: the
three escalation fighters (`nsdf_adjust` path: prison found + 120 s, or an early attack on the NSDF) and the two
factory fighters. Each event gets `min(floor(humans / 2), 2)` extras of the same kind, entry and orders:

| Humans | Extras per event |
| --- | --- |
| 1 (offline) | 0 |
| 2 or 3 | 1 |
| 4 | 2 |

Cap: at most 12 live scaled units; only extras are dropped for it. Scrap: the shared base (team 1) gets 10 extra
starting scrap per guest through `AddScrap(1, ...)` on the first frame (the body never sets team 1's starting
scrap); enemy scrap (team 5) is the body's 40/20.

No pop-in: no scripted fighter is built within 460 m of a human. `muf_point` is 100 m from the prison where the
players stand, so the authored fallback approaches are used in order: `muf_spawn` (the NSDF's second site), then
`escape` (the far edge). If a human is near all of them the request waits (saved in `M.crcca`: a save/load neither
loses nor duplicates it). Unscaled builds at `muf_point` (scavengers, the turret, the Factory) are scenery of the
authored base and pass through.

## Pilots and lives

In a network game `SetPilot(1, 8)` and `AddPilot(1, +-1)` (humans' team range 1-4) are skipped: CRCoop owns the
humans' lives (native lives are raised and respawn is shared), and the DLL's engineer bookkeeping would overwrite
them. Offline the body keeps its pilot arithmetic exactly. The NSDF reserve `SetPilot(2, 40)` is team 5.

## Win, loss, ending

- Win: the NSDF Recycler (`avrecycle`) destroyed -> `misns712` -> `SucceedMission(+10 s, "misns7w1.des")` once on
  every peer (the runtime holds the result until every guest acknowledged the preceding events). The layer latches
  `cr_won`, after which `FailMission` is ignored: nothing can fail a won mission.
- Loss: all three engineers dead before boarding (`misns711`, `misns7f1.des`); the APC destroyed before either
  producer was restored (`misns716`, `misns7f2.des`). The source's success-first tie order is preserved.
- Out of lives (every human out): the mission fails for everyone with `misns7f1.des`.
- Leader departs: every guest fails the mission.

## Cinematics are shared and unskippable in a network game [owner]

The body has three kinds of shot: the prison fall (one `CameraObject` on `geyser1`, held 3.5 s), and the three
engineer deliveries (`CameraObject` every frame on the Recycler, Factory and supply hut). All are leader-driven and
streamed on the C channel; guests follow. `CameraCancelled` is false in a network game, so a skip never shortens
shared timing. Offline every shot stays skippable (the body's `CameraCancelled()` tests work as in the DLL; a skip of
the delivery shot completes the delivery exactly as arrival would). The prison shot is one call in the DLL, so
`holdCamera` re-issues it every frame (a CR inference, same as misns1).

## Restored content [owner decision 2026-11-01]

Cut-content restorations live only in the CR layer, apply offline and in co-op, and each has a flag
(`RESTORED_*` at the top of the runtime region of `misns7cr.lua`). Each is gated on what `misns7cr.bzn` carries.

| Restoration | Flag | Cut block it comes from | Status |
| --- | --- | --- | --- |
| Alternative AIP switch | `RESTORED_PLAN_D` | the commented `plan_d` block after `plan_a`: `if ((plan_a) && (!IsAlive(avrig)) && (!plan_d)) { SetAIP("misns7a.aip"); if both scavengers dead AddScrap(2,20); plan_d = true; }` | Restored on team 5; a rig removed offscreen (`new_rig`) does not count as a dead rig. Uses the AIP the body already loads. |
| Factory retreat | `RESTORED_MUF_RETREAT` | the commented `muf_redirect` block: an attacked (health < 0.50) NSDF Factory goes to `geyser3` while `M.muf_deployed` is unset (the body sets it only once `avtank1` is alive, so the condition is "no tank built yet", not a deployment check; copied from the cut block) | Restored; `geyser3` ships in the map. Once only. |
| Later power/tower expansion | `RESTORED_EXPANSION` | the commented `b3`/`b4`/`rig_show2`/`rig_show3` block: the rig builds `abwpow` and drops it at `power2_spot`, then builds `abtowe` and drops it at `tower3_spot` | Restored; both paths ship in the map. Runs only once the Soviet Recycler is back (`camera_off_recycle`) and the rig has taken its barracks order (`blah`), so it never competes with the earlier build chain. Reuses the body's own unused state fields (`b3`, `b4`, `rig_show2`, `rig_show3`, `b5_time`..`b7_time`). |

Skipped, with the reason:

- **APC stop / pickup cameras** (`con_pickup`, `Stop(apc)`, `Retreat(con, apc)`, `pick_up` blocks and the
  `CameraObject(geyser1, ...)` for pickup): they would take a human's vehicle away from them or stack a second
  shared shot over the prison shot; the active `GetIn` + 20 m boarding already does the rescue.
- **Immediate rig replacement** (`avrig = BuildObject("avcnst", 2, "barrack_spot"); Build(avrig, "abbarr")` on
  removal): the active flow rebuilds the rig when a human returns within 400 m, which is the intended behaviour;
  restoring it would build a second rig.
- **Enemy scrap top-up** (`scrap < 19 && IsAlive(avrig) -> SetScrap(2, 20)`): an unbounded AI economy; it would change
  the balance the active `AddScrap` rewards were tuned for.
- **Main tower build at start** (`main_tower = BuildObject("abtowe", 2, "main_tower")`): the map already authors the
  `main_tower` object.
- **Perceived-team reset** (`SetPerceivedTeam(guntower, 1)` after the Recycler delivery): would expose the Soviet
  towers to the NSDF.
- **Extra objective** (`AddObjective("misns702.otf", WHITE)`) and the commented `CameraFinish`: duplicates of what
  the active code does a few lines later.
- **Per-engineer pickup lines** (`// con 1 on board sir! 726`): the body plays `misns702.wav` for each; `misns701`,
  `misns726` and `misns703` have subtitles but whether their wavs ship in every language archive was not checked
  from this tree, so no wav is switched.
- **`misns713`/`misns719`** (duplicates of `misns704`/`misns718` in the subtitles): never named by the DLL.

## Stock bugs fixed in the CR layer (the faithful body and `misns7.lua` are untouched)

- **Unskippable engineer cutscene hangs.** Each delivery shot ends only when the engineer reaches its building
  (supply: only while the engineer is alive; no other way out in a network game). A killed or stuck engineer left
  the shared shot running for ever. After `ENGINEER_GUARD` (75 s) with a dead or missing engineer, or
  `ENGINEER_STUCK` (180 s) with a living engineer that never arrives, the layer removes any remaining engineer and
  sets the same flag arrival would (`svrecycle_on`, `svmuf_on`, `supply_on`), so the body's own completion code runs. Offline the
  player can still skip earlier.
- **Native calls on destroyed handles.** `SetPerceivedTeam` (destroyed towers or Recycler) and `GetIn` are skipped
  for invalid handles: an invalid-handle native error closes the host.
- **`Attack(ship, player)`** cannot take the shared player token: resolved to a real human (above).
- **`SetAIControl` in `Start`** and `SetPilot`/`AddPilot` on the humans' teams: see Teams and Pilots.
- **Body `AddObject` slot sharing.** A scaled fighter built by the runtime enters `AddObject` before its ticket is
  replaced, so it can briefly also fill the next empty `avfight` slot; the body overwrites that slot when its own
  fighter is requested. Benign (the slot only changes who the plan_a silo order reaches); left as is.
- The body carries its own documented port fixes (see `MISNS7_SOURCE_PORT.md`).

The `.aip` files (`misns7.aip`, `misns7a.aip`, `misns7b.aip`, `misns7c.aip`) are stock and are not in this tree; the
layer only issues them with `team = 5`. Unlike `misns1` (whose stock plans build Soviet units) the NSDF plans
build `bv*` units the NSDF base can produce; this was not verified against the plan files here.

## Weather: Titan

`CRTitanWeather` with the generated `CRTitanSitesS7` through `CONFIG.weather` (ops `TitanState`, `TitanRoll`; start
level 1, target 2). `environment = false`: the Titan director runs on its own renderer path (the Environment titan
preset is for missions that opt in; the misns5-8 documentation says they do not load Environment). The S7 sites
tables are empty (no pools, no wet mask): the director draws no methane pools and no wakes, but its haze ladder,
drizzle and roll events run. The weather is networked as in the other CCA missions (seeded timeline from the host,
rolls over the ordered stream, `Save`/`Load`, `AnnounceState`). A missing weather or sites module, or any weather
error, runs the mission without weather and logs once.

Beats (host/offline only, `state` flags of the body):

| Event | Beat |
| --- | --- |
| prison found (`jail_found`) | `Roll(60, 0.7)`: a haze bank rolls over the prison |
| prison destroyed or NSDF escalates (`jail_dead` / `nsdf_adjust`) | level 3 (drizzle) |
| Recycler restored (`camera_off_recycle`) | level 2, `Roll(50, 0.6)` |
| Factory restored (`camera_off_muf`) | level 3 |
| supply cache delivered (`supplies_spawned`) | `Roll(45, 0.6)` |
| victory (`cr_won`) | level 1 |

The director never damages anything.

## Map content the script never uses

Paths: `apc_wait_spot`, `recycle_spawn`, `base_turret_spot2`, `edge_path` (the playable bounds, used by the weather
generator), `world`. `escape` and `muf_spawn` are used only as `fallbackEntries`. Objects: the scrap fields, extra
geysers (`geyser2`, `geyser4`, `eggeizr1*`), the storage buildings, `wind_power2`, `absupp1_supplydepot`, `stuff1` and
`stuff2` (disguise targets of the map, not touched by the script), `player0_wingman` and the spawn buoys are
authored scenery/defences the script does not touch.

## Tests

```sh
lua5.1 Tools/Test-Misns7Coop.lua            # offline == faithful, 1-4 peers, scaling, 460 m, cameras, audio, results, restorations, weather
lua5.1 Tools/Test-Misns7Presentation.lua    # E/A/C protocol on a guest (object cameras, Titan ops)
python Tools/Test-Misns7CoopSourceParity.py # misns7cr.lua minus CR regions == misns7.lua
python Tools/Test-Misns7CoopContract.py     # labels/paths/teams/ODFs/subtitles in misns7cr.bzn, Titan config and sites
lua5.1 Tools/Test-Misns7.lua && python Tools/Test-Misns7SourceParity.py   # the faithful port, unchanged
```


## Inferences and open questions

- The fallback approaches (`muf_spawn`, `escape`) are guesses at usable alternative entrances; `muf_spawn` is the
  NSDF-side site of the Soviet Factory (`svmuf`), so fighters arriving from there pass the player's own Factory.
- The 75 s (dead engineer) / 180 s (stuck live engineer) guard and the nearest-human `Attack` target are CR inferences.
- The held prison shot (`holdCamera`) is a CR inference; `CameraObject` is a one-shot in the DLL.
- Rescued engineers are narrative in co-op: the shared base gets no extra pilots.
- `rallyPoints = {[0] = "svapc"}`: respawns go to the APC; if the APC is destroyed the mission is usually lost anyway.
- Fighters built at a fallback entry are far from the players and may take a while to arrive.
- The out-of-lives path is not exercised by the host tests (leader departure is).

## Live checklist (unrun)

1. 2-4 humans spawn at the four `coop_spawn*` buoys; the APC is drivable; the briefing (`misns700`) plays once.
2. Prison found -> `misns722`, haze roll visible on every peer; 120 s later 1 + extras fighters arrive from `muf_spawn`
   or `escape`, never in front of a human, and attack a human.
3. Prison destroyed: every peer sees the same geyser shot; three engineers board the APC (any human may drive it).
4. All three deliveries: shared shot, engineer walks out, building restored; a killed engineer ends the shot after
   75 s, a stuck live one after 180 s; the supply cache appears 15 s after the shed opens.
5. NSDF rig/barracks/turret behaviour with several humans; restored factory retreat, plan_d AIP and the late
   power/tower build (do they make the mission too hard?).
6. `misns7*.aip` actually build and send NSDF units for team 5.
7. Titan sky renders on guests with the empty sites file; no weather error in the log.
8. Win (NSDF Recycler) and both losses end on every peer once; out-of-lives and leader-leaves paths.
