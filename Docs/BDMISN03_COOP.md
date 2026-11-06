# Black Dog 3 co-op: Spilt Milk (bdmisn03)

Shared offline / 2-4 player co-op port of the Black Dog mission `bd03` (a damaged Recycler is escorted to the geyser at
Nav Delta, a base is set up there, and an APC full of pilots and wounded is brought in from the south past a series of
Chinese raids and ambushes). One `Missions/bd03cr.bzn` and one `Scripts/bd03cr.lua` serve both modes. Companion
to the faithful DLL port underneath (`Scripts/bd03.lua`, tested by `Tests/test_bd03.lua`) and
[`CCA_COOP_RUNTIME.md`](CCA_COOP_RUNTIME.md) (the shared runtime). Pattern: [`MISNS2_COOP.md`](MISNS2_COOP.md).
Status: **host-tested only**; nothing here has run in the game (see "Live checklist").

## Layout

| File | Role |
| --- | --- |
| `Scripts/bd03cr.lua` | The faithful port plus marked `-- CR ... >>` / `<<` regions. Outside them it is exactly `bd03.lua` (`Tools/Test-Bdmisn03CoopSourceParity.py`). Holds the runtime CONFIG, the native shadows and the restoration. |
| `Scripts/CRGanymedeSitesBD03.lua`, `Scripts/CREuropaWeather.lua` | Ganymede weather (the Europa director with the generated sites for this map: two cryovolcanic vents, the geysers `geyser1` and `eggeizr11_geyser`). |
| `Missions/bd03cr.{bzn,vxt}`, `bdmisn03.{hg2,lgt,mat,trn}`, `Config/bd03cr.ini` | Map, vehicle list and multiplayer listing (not part of this change). The map has **no enemy base**; the Chinese side is a handful of authored cloaked guards plus everything Lua spawns. |
| `Tools/Bdmisn03Fixture.lua`, `Test-Bdmisn03Coop.lua`, `Test-Bdmisn03Presentation.lua`, `Test-Bdmisn03CoopSourceParity.py`, `Test-Bdmisn03CoopContract.py` | Multi-peer fixture and tests (real map coordinates). `Tests/test_bd03.lua` still covers the faithful port, unchanged. |

## Teams and ownership

| Team | Use |
| --- | --- |
| 1-4 | Humans (host on 1). The authored Black Dog side (the Recycler, the escort wingmen, Nav Delta, the APC and its two razors, the restored scavenger and turret) stays on team 1: shared, host-run. Extra starting recyclers are disabled. |
| 5 | The Chinese: every raid unit, the turrets and the guards. The body still says team 2; the runtime maps `BuildObject(..., 2, ...)` to team 5. The map's own enemies (`evil_scout1..5`, `evil_tank1`, `badturret3/4`) are authored on team 5 already. |
| 7 | Support (nothing uses it here). |

Only the authority (host, or the offline player) runs the body; guests only present. `SetAIControl(5, true)` runs once at
chunk load. The mission has no `SetAIP` and no AIP: the enemy is entirely scripted. `SetScrap(1, 8)` becomes the shared
pool plus 10 per guest (`scrapPerGuest`); `SetPilot(1, 10)` is unchanged. Respawns rally on the Recycler.

### Humans as the player

The DLL's "player" is `GetPlayerHandle()`, one tank. In co-op the CR layer answers it with the runtime's nearest-human
token (`crcca_players`), so `M.user` is the token and:

- The gate "the player reaches the Recycler" (`Distance(user, recycler) < 75`, the green objectives and `bd03006`) fires
  for **any** human. It is an approach trigger (nearest human); `farthestTargets` is empty. The body's `Distance` is
  wrapped in the restored-content region and keeps its third (path point) argument for every other caller.
- The intro shot `CameraPath("camera_intro", 1000, 0, user)` needs a real object to look at: the CR layer targets the
  host's ship (the authority), else the first live human, else the Recycler.
- The body never aims an order at the player (the only such block, the hunt of the roadside guards, is cut: see below),
  and never reads a unit's team, so no other mapping is needed.

## Scaling and concealed arrivals [owner rules, mission decisions]

Scaled spawns: the ODFs `cvfigh`, `cvfighf`, `cvltnk`, `cvtnk` (every enemy craft). They become *tickets*: the
body gets a negative request id and the unit is built by the runtime on the next frames, with the body's later orders
(`SetCloaked`, `Goto`, `Attack`, `Hunt`, `Follow`, `Defend2`) replayed on it; `Hunt` and `SetCloaked` are added to the
runtime's order list for that. Not scaled: the two enemy turrets (`cvturr`, static) and every team-1 unit (the APC, its
razors, the restored scavenger and turret).

Events. The runtime region wraps `BuildObject` once: **a new frame is a new scaling event**, and the first scaled unit of
an event is mirrored by `min(floor(humans / 2), 2)` extras of the same kind, entry and orders. The events are the four
guards (one frame), raid 1, raid 2, raid 3, the fast fighter that hunts the APC, each random raid and the ambush pair.
The first unit of an event is the one that is mirrored; the random raid builds from four different entries, so its extras
copy the first unit's entry.

| Humans | Extras per event |
| --- | --- |
| 1 (offline) | 0 |
| 2 or 3 | 1 |
| 4 | 2 |

Cap: at most **16** live scaled units (`liveCap`; the runtime default is 12) because the guards, raid 1 and raid 2 can
all be alive when the first random raid arrives. Extras are the only requests dropped for the cap; primaries always spawn.
Build rate is two per frame, so a five-unit raid takes three frames.

No pop-in: a ticket is never built within 460 m of any human. If a human is near the authored entry, the next clear
authored enemy approach in `fallbackEntries` is used (`spawn_attack_apc`, `spawn_random_1`, `spawn_random_4`,
`spawn_random_2`, `spawn_random_3`, first that is clear), else the request waits (saved in `M.crcca`, so a save/load
neither loses nor duplicates it). Reinforcements stop for good when the APC has arrived or the mission is lost
(`endedFlags = won, lost`); the body itself would keep spawning random raids until the result screen.

## Humans' result, win and loss

- Win: unchanged. The living APC within 75 m of Nav Delta -> `bd03009` -> `SucceedMission(..., "bd03win.des")` once
  (the runtime holds the result until every guest acknowledged the preceding events). The faithful port already requires a
  positive APC health, so a wreck never wins.
- Loss: the Recycler dies -> `bd03012` -> `bd03lsea.des`; the APC dies -> `bd03010`, `bd03011` -> `bd03lseb.des`. Once the
  APC has arrived, a Recycler lost during the radio line is ignored (`wonFlags = won`), as in the body.
- Out of lives (every human out): `bd03lose.des`, the stock generic debrief that the DLL never names. Leader departs: every
  guest fails.
- No timers or cockpit timer exist in this mission.

## Cinematics are shared and unskippable in a network game [owner]

The intro (`camera_intro`, `bd03001`) and the Recycler shot (`camera_recycler`, `bd03002`) are driven by `CameraPath`
every frame, so the runtime's camera stream carries them to every guest; `CameraCancelled` is false in a network game,
offline both stay skippable (a skip stops the line and the body finishes the shot). The shots' end is the body's own
audio-gated test (`IsAudioMessageDone`), host-side. A save/load cannot resume a film (the cameras are gone): on load the
unfinished shot is ended as the body would end it (the intro: complete; the Recycler shot: complete, the two escort units
removed, the `bd03003` timer armed), and the next phase starts normally.

## Restored content [owner decision 2026-11-01]

Cut-content restorations live only in the CR layer, apply offline and in co-op, and each has a flag (`RESTORED_*` at the
top of the runtime region of `bd03cr.lua`). Each is gated on what `bd03cr.bzn` carries.

| Restoration | Cut block it comes from | Status in this map |
| --- | --- | --- |
| Base start units (`RESTORED_BASE_START`) | `//BuildObject("bvscav", 1, "spawn_scav"); //BuildObject("bvturr", 1, "spawn_turret");` inside `if (!recyclerDeployed && isDeployed(recycler))`, beside `spawnRecyclerAttackTime1 = GetTime() + 30.0f` | The map has the paths `spawn_scav` and `spawn_turret`, 34 m and 27 m from the geyser the Recycler deploys on: the authored spot for a scavenger and a turret tank beside the new base. Built once, on the frame the body notices the deployment, as team-1 units (shared, never scaled). It fits the briefing ("Set up a base to receive it", `bd03007`) and gives a one-player base a first scavenger. Skipped silently when a path is absent. |

Skipped, with the reason:

- The hunt of the roadside guards, `#if 0 // get the enemies into hunt mode: for (i = 0; i < 4; i++) Attack(evilGuys[i], user);`
  (the block the body keeps as a comment after the Recycler shot): the four are `evil_scout1..3` and `evil_tank1`. The
  APC route `path_apc_travel` passes 163 m from `evil_scout1` and 55 m from the team-5 turrets
  `badturret3/4` beside `evil_tank1`, so they are the APC's authored roadside ambush; hunting would pull them to the base in
  the first minute (and, with several humans, to an arbitrary one). The map and the audio (`bd03003`, "my wingmen down")
  keep the pace of the original.
- `//evilGuys[3] = GetHandle("evil_scout4"); //evilGuys[2] = GetHandle("evil_scout5");`: the body cloaks both scouts by
  label anyway, so the commented assignments add nothing.
- The unused debriefs `bd03wina.des` and `bd03winb.des` (a win with the Recycler alive, and "You allowed your Recycler to
  be destroyed ..." for a win without it): the DLL decides win and loss by `won`/`lost` and never names them. Restoring
  `bd03winb` would make a destroyed Recycler survivable, contradicting `bd03012`/`bd03lsea` ("The loss of it will end any
  chance you had"). Not restored. `bd03wina` is the same text as `bd03win`.
- Dormant state the DLL declares and never reads (`objective3Complete`, `firstRandomAttackDone`, `activateStuff` beyond its
  `#if 0` body): no behaviour to restore.

Authored paths the script never uses (documented, not wired): `edge_path` (used by the weather as the playable box).
Six unlabeled two-point paths in the map are leftover AI scratch routes and have no name to reference.

### Voice lines [owner decision 2026-11-01]

All twelve shipped lines `bd03001`..`bd03012` (wavs plus `Text/` transcripts, durations in `Config/durations.csv`) are
played by the faithful body; the contract test asserts the script names exactly the lines the repo has transcripts for.
There is **no unused shipped voice line** for this mission, so there is nothing to slot in (compare `MISNS2_COOP.md`'s
`misns211`). The restored base units do not need a line.

## Stock bugs fixed in the CR layer (the faithful body is untouched)

- **One human as "the player"**: the Recycler gate and the intro camera target a single tank. See "Humans as the player".
- **Orders on concealed spawns**: the body cloaks (`SetCloaked`) and hunts (`Hunt`) units it has just built; in co-op the
  unit may still be a ticket (waiting for concealment), and a ticket id would reach the native call. Both orders are in
  the runtime's replayed order list.
- **Setup publishes before the presentation resets**: `Setup()` names Nav Delta (`SetObjectiveName`). The runtime's
  `Start()` clears the presentation stream, so the CR callback runs `campaignRuntime.Start()` *before* `Setup()`; the name
  reaches every guest.
- **Enemy team**: the body builds on the map-native team 2; the runtime maps it to the co-op enemy 5 (nothing is built on
  team 2, and the map has none).
- **Reinforcements after the result**: raids and the random 90 s patrols stop when the APC arrives or the mission is lost.
- **Loads during the films**: ended as described above.
- Objective rebuilds are coalesced by the runtime (a rebuild identical to the last published list is dropped).
- Audio: every line the body names has a subtitle in `Text/` (`Test-Bdmisn03CoopContract.py`); `audioSubstitute` is empty.
  The `.des` debriefs ship with the game.
- The body already carries its own documented port fixes (`Distance` guard, `Health` of an absent object, the 25 m
  end-of-path approximation of the native `isAtEndOfPath`, and the APC wreck at Nav Delta not winning).

## Weather: Ganymede

`Environment.Init` in `orbit` mode (the sun's real path, a short eclipse, Jupiter-shine at night: the same options as
`misn12cr`) plus `CREuropaWeather` with `CRGanymedeSitesBD03`, networked through the runtime (seeded timeline from the host,
host-chosen plumes/quakes/surges over the ordered stream as `EuropaState`/`EuropaPlume`/`EuropaQuake`/`EuropaSurge`,
`Save`/`Load` state, `AnnounceState`). No new weather module: Ganymede reuses the Europa director for an icy, airless
Jovian moon. `Environment.BindWeatherSensors("Ganymede", ...)` is registered once per start from the runtime's update hook
on every peer, so the director slows radar as it intensifies, exactly as `misn12cr` does. If the module or the sites
module is missing, or any weather call errors, the mission runs without weather and logs once. The site file has two
vents (`geyser1`, major, and `eggeizr11_geyser`), so plumes stay enabled.

Beats (host/offline only, each once, tied to the mission's own moments; the director never damages):

| Moment | Weather |
| --- | --- |
| Start, the Recycler's long drive | level 1 (Quiescent) |
| The Recycler deploys on the geyser (`recyclerDeployed`) | level 2 and a plume from `geyser1` |
| The APC sets out (`apcSpawned`, after `bd03007`) | level 3 |
| The APC is first hit (`sound8Played`, `bd03008`) or springs the ambush at the pass (`triggerAmbush`) | level 4, a quake (0.35, 3 s) and a surge (6 s, 0.8) |
| The APC reaches Nav Delta (`won`) | forced level released, back to level 1 |

## Tests

```sh
lua5.1 Tools/Test-Bdmisn03Coop.lua            # offline == faithful, 1-4 peers, scaling, 460 m, fallback, films, results, weather
lua5.1 Tools/Test-Bdmisn03Presentation.lua    # E/A/C protocol on a guest
python Tools/Test-Bdmisn03CoopSourceParity.py # bd03cr.lua minus CR regions == bd03.lua
python Tools/Test-Bdmisn03CoopContract.py     # labels/paths/teams in bd03cr.bzn (skips with a message if the map is absent)
lua5.1 Tests/test_bd03.lua                    # the faithful port, unchanged
```

The workflow `.github/workflows/campaign-validation.yml` is not edited by this change; the four co-op commands above are
the step to add. The contract test checks `Config/bd03cr.ini`, `Config/crbd.ini` and `Missions/bd03cr.vxt` only
when they are in the tree and says which it skipped.

## Inferences and open questions

- Scaling is per frame, a CR inference; a raid whose units a branch spawns on different frames gets one more event.
  `liveCap = 16` instead of the default 12.
- `fallbackEntries` assumes the four `spawn_random_*` points and `spawn_attack_apc` are all usable enemy approaches; a raid
  can arrive from the east when the intended entry is watched, then fly or drive to its target.
- The recycler's rally label moves with the unit; the respawn service reads it at respawn time.
- The native `isAtEndOfPath` radius is unknown; the 25 m of the faithful port is kept and untested on the real map.
- The restored scavenger/turret positions sit a few tens of metres from the deployed Recycler; collision at the exact
  authored spots is unverified.
- The out-of-lives path is not exercised by the host tests (leader departure is).

## Live checklist (unrun)

1. Intro: the same shot on every peer, looking at the host's ship; cameras balanced; the Recycler shot follows.
2. The Recycler drives off alone; at the geyser two turrets and four cloaked guards appear far behind (none in view).
3. The Recycler deploys: scavenger and turret appear beside it, the geyser vents, `bd03006` plays when the first human
   (any team) reaches the Recycler.
4. +30 s raid 1 on the Recycler; +7 min cloaked raid 2 and the APC with two razors (marker on every peer); +9 min the
   fast fighter; +10 min random raids every 90 s; +11 min raid 3. With 2-4 humans each group has extras, none visible at spawn.
5. The APC passes the pass: two cloaked units follow it; the sky goes to level 4 with a quake.
6. The APC at Nav Delta: `bd03009`, one shared victory, no further spawns.
7. Recycler loss and APC loss each give one shared failure with the right debrief.
8. A save/load during each film; the weather sky and radar on guests; no weather error in the log.
