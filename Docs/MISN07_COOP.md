# Mission 07 offline and co-op

Behind Enemy Lines shares `misn07.bzn` / `misn07.lua` between campaign
`MISSION6` and the strategy listing `CR: Behind Enemy Lines Coop`.
Use matching CR, EXU and OpenShim builds. Host on team 1, with guests on
distinct teams 2–4; select an NSDF tank or scout and start together.
Late join/rejoin requires a restart. Host departure ends the mission.

## Map

`Tools/Build-CoopMap.py --mission misn07` rebuilds `Missions/misn07.bzn` from
the Battlezone 1.5 original (`stockfiles2\misn07.bzn`, binary version 1032,
class `Misn07Mission`) exactly as for misn06 (see `MISN06_COOP.md`):
`TerrainName = misn07`, class `MultSTMission`, the 48 authored CCA objects
moved from team 2 to team 5 (`perceivedTeam 5`), and four zero-motion
`pspwn_1` team starts (`coop_spawn1`–`4`) 25 m apart at the authored start.
Terrain is the unsmoothed 1.5 cook (`misn07.hg2`).

The builder also drops authored objects named in `REMOVE_LABELS`. For misn07
that is `avtank2` and `avtank3`, the two "disguised" rendezvous tanks, which the
original keeps on team 3 (a guest team in co-op). Their authored positions are
recorded in the builder and the Lua: avtank2 (1426.3, 22.9, 99546.5) and avtank3
(1442.5, 21.6, 99570.4). The map keeps no other object on teams 2–4. misn06
output is byte-identical to before.

The converted map keeps every path the Lua reads, including the test-range
paths (`cam_spawn1`–`6`, `camera_path1`/`2`, `test_tank_spawn`, `m001`–`m110`)
and `edge_path`, whose endpoints (x 192..4106, z 97480..101299) bound the
playable area. `m000` is absent and the restored minefield skips it.

## Mission ownership

The Utah (`avrec7`), the unit factory, the navs, Razor One and the replacement
tanks stay on team 1. CCA units, soldiers, parked turret replacements, the base
tower and mines use team 5. Support units (the rendezvous convoy and the test
turret) use team 7, allied with every human team and hostile to team 5. EXU
suppresses the extra MultST starting recyclers. The DLL's `SetScrap(1, 10)`
becomes each human team's starting scrap, with native capacity reserved first
(as in misn05/misn06). The arrival bonus `AddScrap(1, 30)` / `SetPilot(1, 20)`
goes to team 1, the leader's base, where the Utah deploys; the CCA's
`AddScrap`/`SetPilot` and `SetAIP("misn07.aip", 5)` use team 5. The AIP is the
stock file from `bzone.zfs` (identical to Battlezone 1.5's); CR does not ship it.

Only the campaign leader runs AI, spawns, orders, timers and the win/loss
gates; the co-op preamble returns for guests before the mission body. Objectives,
markers, dialogue (the first line of a block plays and the rest queue — every
misn07 block is a single line), removals and results go to every peer through
the ordered, acknowledged E/A event stream. The C snapshot carries a camera
kind: `P` replays `camera_path1`/`2` and `O` the object shots. Each player can
skip their own film; the shared timing continues. misn07 reads no `IsInfo`
state, so there is no `I` relay.

## Alarm and stealth, per player

The alarm is one shared mission flag, but every trigger checks every player.

| DLL test | Co-op rule |
|---|---|
| Tank tripwire (`!out_of_car`, < 70 m of `turret1_spot`) | trips if **any** player who has **not** infiltrated is within 70 m, even after a teammate parachuted in |
| Parachute in (< 160 m of `camera_geyser`, alarm off) | recorded **per player** (keyed by CRCoop player id); `out_of_car` now means "any player has infiltrated". The radar objective is raised by the first infiltrator |
| `vehicle_stolen` (infiltrated in `svtank`/`svfigh`/`svturr`) | latched **per infiltrated player**; `vehicle_stolen` means every infiltrator has stolen one |
| `alarm_special` (soldiers) | when `trigger1` fires, if any infiltrated player has not stolen a Soviet vehicle |
| Soldiers, parked units `Attack(x, user)` | each attacks its nearest player |
| `parkturret != user` | no player holds that turret |
| Alarm sound (< 170 m of the radar array) | any player |
| Rendezvous (< 150 m of a tank), tower warning (< 90 m of `nav1`), rookie found (< 70 m), runner (< 50 m of a patrol) | any player |
| Jump-cam spawn (no player < 400 m of the geyser, no `svfigh` < 200 m) | no player within 400 m **and** no enemy fighter within 200 m of any player |
| Friendly-unit tripwires (`avfigh1`, tanks near the towers) | still gated by the global `out_of_car`, so they disarm once any player is inside; the rookie script uses the same flag |

`trigger1` (anything damaged while a player is inside) is unchanged. Win and
loss stay in the DLL logic: the radar and CCA recycler destroyed wins, losing
the Utah after arrival fails, and exhausting the five-life respawn service
(`COOP_RESPAWN.md`) fails everyone.

Respawns rally at the rendezvous nav (`cam3`) until the Utah is deployed, then
at the Utah. The leader sends a `Rally` presentation event carrying the Utah
handle (every peer sets its own respawn service; delivery waits for the
replica) and advances the CRCoop mission phase.

## Rendezvous convoy

`-- CR rendezvous convoy >>` regions. The leader spawns two `avtank` on the
support team (perceived as NSDF, independence 0, stopped) at (779, 99505) and
(779, 99525): 15% inside the west edge of the `edge_path` bounds at the
rendezvous latitude, about 660 m from `cam3`, away from every CCA route and out
of sight. When any player comes within 600 m of `cam3`, `Goto` sends them to the
authored avtank2/avtank3 positions; the order is repeated every 10 s until each
is within 25 m, so tanks that were stopped en route keep driving. 600 m is the
distance a player covers in about the minute a tank needs for the 660 m. They
take the DLL handles `wingtank2`/`wingtank3`, so the any-player rendezvous test
and the team-1 `avtank` replacement run unchanged; a convoy tank destroyed en
route is tolerated exactly as the DLL tolerates dead wingtanks. Offline play
uses the same convoy.

## Razor One's infiltration

`-- CR Razor One infiltration >>` regions. At the DLL's moment (0715 plus
`EjectPilot`) the pilot is captured: `EjectPilot` returns nothing, so
`AddObject` adopts the first person within 40 m of the rookie, with a
per-frame `ObjectsInRange` scan as a fallback (give up after 3 s). The empty
`avfigh` stays as the DLL leaves it.

* **Glide.** Each frame the leader sets his velocity toward the landing point:
  40 m past `camera_geyser` toward the parked vehicles, (2781, 99542), clear of
  the radar array, huts, parked tanks and APC. Horizontal speed is limited to
  22 m/s (easing near the target), descent to 5 m/s. A wall assist climbs just
  fast enough (at most 10 m/s) to clear the highest terrain on the next 90 m by
  10 m. Steering stops within 8 m of the target; he lands when within 1.5 m of
  the ground. Fail-safes: pilot lost or dead, no landing within 60 s or no
  capture within 3 s drops the behaviour.
* **Theft.** After landing he is ordered with `GetIn` into the nearest empty
  parked Soviet vehicle among `parked1`–`3` (empty, team 5, not held by a
  player; turrets and the APC are excluded). The chosen handle is cleared from
  the CCA alarm code, so later `Retreat(pilot, parkedN)` / `Attack(parkedN, …)`
  / damage triggers never see it. If it is destroyed, taken, or he is not in it
  within 40 s, the handle is given back and the next nearest is tried.
* **Fight.** Once he has entered (he vanishes beside the vehicle) the vehicle is
  forced to team 1 and NSDF-perceived if the engine did not do it, and follows
  the nearest player (refreshed every 10 s). Humans alone are infiltrators, so
  his theft never sets `out_of_car` or the alarm; if the alarm is already on he
  just fights. Offline play is identical.
* **Regeneration.** Whatever he is flying heals: his avfigh before the ejection and
  the stolen Soviet vehicle afterwards (also on the test-range trip). Never the pilot
  on foot, the empty avfigh after the ejection, or anything dead. After 4 s without
  his health dropping (tracked frame to frame) it restores 2% of max health per
  second (`AddHealth`, scaled by `GetMaxHealth`), clamps at max, and any new damage
  restarts the 4 s. His weapons and AI are unchanged. Tunables `RK_HEAL_QUIET_S` and
  `RK_HEAL_PER_S` sit at the top of the script.
  *Why 2%/s, 4 s:* a CCA `svfigh` fires two `gminisov` guns (bullet2, 70 damage every
  0.30 s), about 467 damage/s at perfect aim and roughly 230 in practice; the
  ambush pair is about 470 effective. Razor One's ships have 1800 (avfigh), 2375
  (svfigh) and 4062 (svtank) health in CR's ODFs, so 2% is 36-81 health/s: under 20%
  of one fighter's realistic fire. It cannot out-heal an ambush (the pair kills a
  2375 svfigh in about 5 s, and nothing heals while he is being hit), but over the
  30-45 s a player needs to reach him the quiet stretches restore roughly 50-80% of
  his health, so skirmish chip damage no longer accumulates into a death before the
  scripted beats.

## Restored cut content

`-- CR restored VO >>` regions (`RESTORED_VO` gates them; the source parity test
strips them, checks the DLL body is otherwise unchanged and that every restored
wav has its shipped `Text/misn07NN.txt`). Only shipped assets are used.

* The test range (the disabled C++ block, retimed so it never collides with the
  infiltration). **Nothing starts before the radar array is destroyed.** After that
  it waits until the Utah has deployed (or 150 s after 0714 if it has not) and no
  dialogue is still playing (0714 and 0719 are tracked with `IsAudioMessageDone`).
  Then:
  1. If Razor One is alive (his stolen vehicle, or his pilot if he never got one)
     he stops following the players and is ordered to `cam_spawn6`, the Testing
     Range east of the outpost beyond the minefield (repeated every 10 s). 0703
     plays when he is within 60 m of it, after a 90 s timeout, or at once if he is
     gone (the radio-only version), and the test tank and turret spawn with it.
  2. 15 s later the "Testing Range" Nav Beacon (`apcamr` at `cam_spawn6`) appears,
     as in the DLL.
  3. The DLL's 120 s later, when no player is within 400 m of `cam_spawn1`
     (`mine_geyz` is gone, so that spawn point stands in), two CCA `svfigh` spawn at
     `test_tank_spawn` and are ordered onto Razor One, so "I'm under attack" is
     true; then 0704 plays and the "Mine Field" beacon appears at `cam_spawn1`.
     With no Razor One only the radio call and beacon happen. If a player has
     already reached him there is no ambush and no distress line (the beacon still
     drops).
  4. When any player is within 70 m of the Mine Field beacon, the four "Mine Path
     1-4" beacons appear at `cam_spawn2`-`5`. As in the DLL, `mine_pathed` stops
     further runner retreats.
  He returns to following the nearest player once a player comes within 100 m or
  the ambush is cleared.
* The streamed minefield: `proxmine` (team 5) at path nodes `m001`-`m110`
  whenever any player is within 400 m of a node, removed when none is, and
  marked dead once destroyed; ten nodes per frame by round robin
  (`mine_check`). Missing nodes (`m000`) are skipped via `GetPathPointCount`.
  It streams from the start, as in the DLL's top-level block. **Phase-1 safety:**
  the nodes span x 2671..3620, z 98393..98949. None lies within 400 m of the
  start-to-rendezvous, rendezvous-to-overlook, overlook-to-outpost or
  rendezvous-to-outpost routes; the closest is `m001`, 420 m from the straight
  start-to-overlook line, and no node is nearer than 464 m to the overlook,
  outpost, huts, parked vehicles, radar array, gun towers or the runner camera.
  So no mine can even spawn while players infiltrate.
* The MAG-cannon test. The map no longer holds `test_tank`/`test_turret`, so
  0703 spawns them (not earlier). `test_tank` is an `svtnk7` (the DLL's MAG tank)
  at `test_tank_spawn` (3283.7, 99037.3), independence 0 and stopped. `test_turret`
  is an `svturr` (a CCA-model turret from the stock ODFs) on the support team,
  which never fires on players and is a legitimate enemy of the CCA tank, so the
  shot is an ordinary attack order. It stands at (3268.7, 99007.6): the
  midpoint of `camera_path2` (x 3288.0..3249.3 at z 99037.6, the shot that
  films the turret) moved 30 m south toward the Testing Range nav and away from
  the CCA factory at (3275.6, 99069.6). The coordinates come from the converted
  BZN paths and have not been checked against the terrain in game.
  When any player is within 65 m of the tank, with no other film running and the
  mission not over (the alarm is irrelevant after the radar), the film runs:
  object shot of the tank (6 s), `camera_path1` (8 s), `camera_path2` at the
  turret (swap the tank for a fresh `svtnk7` attacking the turret after 5 s, 6 s
  total), an object shot of the turret (10 s), then `CameraFinish`; the turret
  is pre-damaged 950 and the tank is released to fight. It plays once and
  replicates through the `O`/`P` snapshots; each player can skip their own view,
  an offline skip ends it and resolves the swap. **0711 (a developer joke) is
  not played.**
* Prototype svtnk7 production. When the film finishes (or the leader skips it), or
  the test tank is hurt or destroyed without a film, the CCA begins fielding the
  prototype `svtnk7` (weapon `ga7stab`: `charge6`, 1450 ballistic damage, 75 m/s,
  6 s reload). There is no voice line or objective text for it.
  *Route:* Lua on the leader, not the AIP. The stock `misn07.aip` (byte-identical
  in Battlezone 1.5 and Redux's `bzone.zfs`) is a text AIP whose build list could
  take a CR variant, but its factory `svmuf` has no `svtnk7` build item, and
  adding one to `svmuf.odf` would change every CCA factory in the campaign. So,
  while the CCA factory (`svmuf`) lives, the leader builds an `svtnk7` at it on a
  timer, charging team-5 scrap (`svtnk7.odf` scrapCost 8; no build without it),
  and orders each at the Utah (else the nearest player), refreshed every 30 s.
  Tunables sit at the top of the script: cap 2 live prototypes solo, +1 per extra
  human team, max 4; one build per 135 s; the first no sooner than 90 s after the
  trigger. Production stops when the factory is destroyed. Leader-only; the
  native objects replicate themselves.
  *Assets:* `svtnk7.odf`, `ga7stab.odf`, `charge6.odf` and `gatstab.odf` are all in
  Redux's stock `bzone.zfs` (as are `gatst03.wav`, `xmsl*.odf`, the `svtank` mesh
  `svtnk7` uses as its base, and `plasma_3.png` for the shot). Nothing is 1.5-only.
  CR already ships its own `ODF/svtnk7.odf` (3750 health, rocket-tank AI) and
  `gatstaba.odf`, both in the lock; no file was added.
* The overlook call (where the DLL plays 0702) is 0702 or its cut alternate take
  0717, picked once at random (50/50) by the leader through `math.random`, then
  played through the normal event stream so every peer hears and subtitles the same
  take (offline picks the same way). `Text/misn0717.txt` ships with the mod; the
  wav is in Redux's English, Portuguese and Russian archives (`bzone_en/pt/ru.zfs`) but
  not in the German, Spanish, French and Italian ones, where the alternate take has
  subtitles but no voice. The default path is the original 0702 line
  (`RESTORED_VO=false` restores it exactly).
* 0719 (Collins: rendezvous with the Utah) once, 120 s after 0714, if the Utah is
  still not deployed; the test range waits for it to finish.

## Focused checks

```sh
lua5.1 Tools/Test-Misn07.lua
lua5.1 Tools/Test-Misn07Coop.lua
lua5.1 Tools/Test-Misn07Presentation.lua
python Tools/Test-Misn07SourceParity.py
python Tools/Test-Misn07CoopContract.py
python Tools/Test-SetupMissionShell.py
python Tools/Validate-CampaignRepository.py
```

The offline suite keeps its 31 single-player checks. The host flow suite
(`Test-Misn07Coop.lua`, 593 checks) runs the whole script in four peers over the
real CRCoop and the E/A/C transport, plus an offline peer: startup and teams,
the convoy, per-player alarm, special alarm and nearest-player soldiers,
any-player triggers, rally and the Utah, win/loss, the restored arc, the
minefield, the MAG film (once, skips, no 0711), the phase-2 gating, Razor One's
glide, theft, fallbacks and fail-safes, his drive to the test range and ambush,
and the prototype svtnk7 program (trigger, cap scaling, scrap, factory loss). The presentation suite covers the
four-peer adapter (path/object cameras, rally, delayed replicas, skips, result
held for acknowledgements). The parity test pins the DLL source and lists each
co-op substitution as an explicit API-count delta. These mocks do not qualify
native wire serialization, AI navigation or voice queuing.

## Not yet verified

No live run: Windows GOG two- and four-client co-op and the campaign
progression from MISSION5. Specifically unproven: the parachute glide feel and
the wall clearance (velocity steering against real pilot physics), the pilot
entering the parked vehicle through `GetIn` and the engine's team change, the
convoy pathing to the rendezvous and its spawn terrain at (779, 99505), the
test turret/tank terrain at the derived coordinates, Razor One's drive to `cam_spawn6` and the ambush fighters' behavior, the prototype tanks' balance (3750 health, 1450-damage shots every 6 s), the film timing and shot
offsets over the converted map, mine density and the 400 m stream, and the
guest film skips. The stock AIP's behavior on team 5 (it was authored for team 2) is untested. Steam and Wine/Proton are unverified, and stock multiplayer kill-feed
messages remain visible.
