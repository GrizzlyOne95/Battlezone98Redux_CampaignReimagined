# Mission 11 offline and co-op

Bring it Home shares `misn11.bzn` / `misn11.lua` between the campaign mission (`crcampgn.ini`
MISSION10, Io, retrospective `misn1100.wav`) and the strategy listing `CR: Bring it Home Coop`. Use
matching CR, EXU and OpenShim builds. Host on team 1, guests on distinct teams 2-4; select an NSDF
tank, scout, or light tank and start together. Late join/rejoin requires a restart. Host departure
ends the mission. There is no intro cutscene (the original has none).

Starting choices follow [the co-op production progression](COOP_STARTING_UNITS.md).

## Map

`Tools/Build-CoopMap.py --mission misn11` rebuilt `Missions/misn11.bzn` from the Battlezone 1.5
original: class `MultSTMission`, the eight authored CCA objects (five `svturr`, two `svartl`, one
`svwalk`) moved from team 2 to team 5, four zero-motion `pspwn_1` team starts (`coop_spawn1`-`4`), no
authored object on teams 2-4. The three haulers, the three wingmen, the armory, the bases and the nav
beacons stay team 1 (host-owned allies; the wingmen keep following the host). The terrain companions
are Redux's own plus the painted lava below; the heightmap is the 1.5 (unsmoothed) one.

There is no AIP and no CCA base: the whole CCA is script-driven (`BuildObject` strike waves, the
ambush and the backup squad below). Nothing calls `SetAIControl` or `SetAIP`.

## Ownership and rules

Only the campaign leader runs spawns, orders, timers and the win/loss gates. Objectives, markers,
dialogue, removals and results reach every peer through the ordered, acknowledged E/A stream
(label-aware markers, bounded guest waits: the #186 pattern). `SetUserTarget` is local, so it rides
the same stream. The base is host-only (`SetScrap(1, 50)`). Respawns rally at the start of the convoy
road (`base1`) until the convoy moves out (mission phase 1), then at the lead tug; the rally is
dropped once that tug is gone.

| DLL | Co-op |
|---|---|
| CCA team 2 | team 5 |
| `GetPlayerHandle` triggers (first waypoint, pad ambush) | any player |
| Arrival at pad 2 (player within 200 m, latched) | **every** human within 200 m, latched per human; a player who leaves the session is not waited for. Both tugs must still be alive |
| `svfigh` scans retask every fighter on any team | only CCA (team 5) fighters that are not the backup squad |
| Last fighter attacks the player | the human nearest launch pad 2 |
| Pursuit warning `~= 0` | any player (still always true while the first turret lives) |
| Convoy restart: blockade turret dead | blockade turret **and** walker dead |

## Scaling (marked `-- CR CCA scaling`)

Each extra human (cap 4 players, so at most +3) adds one `svfigh` to the first strike, the second strike
and the final wave, and one `svtank` to the launch-pad ambush (the DLL's "both ambush tanks died" test
still reads only its own two). The backup squad also gains one `svfigh` per extra human.

## Ambush: the idle CCA units go hostile (marked `-- CR ambush`)

The map parks CCA units that the DLL never orders. They now hunt (re-evaluated every 3 s, re-issued
every 6 s; targets are the nearest human craft or convoy tug):

| Unit | Trigger | Why there |
|---|---|---|
| `svturr0`, `svturr1` (pickets beside the convoy road) | a convoy tug or any human within 380 m | they stand 50-175 m off `base1`, where the convoy must pass |
| `svwalk` (beside the second blockade) | the convoy halts at `check2` | it stands 40 m from `second_blockade` and `base2`; the DLL's "heavy forces ahead" includes it. The convoy restarts only when blockade turret and walker are both dead |
| `svartl` x2 (outpost artillery) | after the defection, shell any human within 650 m | they stand on the `openheimer` path beside `svturr2`/`svturr3`; they cover the defector, not the convoy road (600 m away) |

## Betrayal (marked `-- CR betrayal`)

The DLL's tug simply turned and drove off. Now:

1. **Build-up.** When Oppenheimer's tug is within 250 m of Waypoint 1 (after the convoy has moved out) a
   CCA backup squad (2 `svtank`, 1 `svfigh`, +1 `svfigh` per extra human) is built at the far west end
   of the `openheimer` path (906, 98614): on the CCA side, beyond the road, out of sight. It drives to
   the CCA outpost beside the artillery. Radar sees it arrive before the tug breaks off.
2. **Defection** (stock timing: break off at Waypoint 1, announcement and team change 15 s later). The
   squad forms up on the tug through `SetCommand(unit, AiCommand.FORMATION, 1, tug)` (the stock Lua `Formation()` binding reads its second argument as an integer priority and passes it as the leader, so `Formation(unit, leader, 1)` raises "bad argument #2 (number expected)" and in co-op the error alert then closes the host), and the strike scans never take it.
3. **Chasers.** Every 2 s the squad looks for human craft within 350 m of the tug and attacks the
   nearest (priority 1); when nobody is near it returns to following the tug. The artillery shells humans in
   its 650 m range. Oppenheimer's +300 health per tick is kept (he cannot be killed).
4. **misn1114** (Collins: do not recover Transport 3, Sky-Eye sees a massive force) plays once when any
   human comes within 450 m of the defector.
5. **misn1115** (Corbett: "information recorded, continue on your mission") plays once, at least 12 s
   after misn1114, when every human has stayed more than 700 m from the defector for 8 s (or the squad
   is dead): chase, then break off. misn1106 stays as in the DLL.

`edge_path` is the map's play boundary (a two-point rectangle), not cut content, and nothing routes along
it. Other findings from the BZN: the `openheimer` path is flanked by the CCA outpost (two turrets, two
artillery) and ends near the south-west edge; both launch pads ship with pre-built bases; the armory
(`avslf`) stands on a geyser in the middle of the map and is never referenced by the DLL.

## Weather (`CRIoWeather`, `CRIoSites11`)

Every peer inits and updates the director; the leader decides. Beats, each once: level 2 at the start,
3 on the betrayal, 4 on the second strike, a 60 s level-5 burst plus a quake (0.9 for 8 s) when the launch
pad dies, calm on the win. `Scripts/CRIoSites11.lua` is generated by `Build-IoSites.py misn11 --source-dir
Missions` from the painted lava.

## Lava

Stock misn11 never paints the molten tile and its `.trn` has no `Lava=` key, so the engine treated no
ground as lava. `Tools/Build-Misn11Lava.py` (reproducible, deterministic, from Redux's originals) repaints
`Missions/misn11.mat` and sets `Lava=1` in `Missions/misn11.trn` (TextureType 1, "Lava Pool"). Engine
behaviour (decompiled BZ 1.5): craft over a lava tile take heat damage scaled by the surrounding lava tiles
and by hover height, so lava damages (roughly 100-140 hp/s for a hovering tank), it does not block; AI
units and tugs path around it; walkers and pilots will not cross it.

Preview: `Docs/MISN11_LAVA_PREVIEW.png` (heightmap shading, lava, shoreline tiles, paths, objects).

* Lava fills the low basins (tile height under 21 m plus seeded noise), the whole central area enclosed
  by the escort route, the launch_attack/escape route and the start, and barriers south of the start and
  north of the escort loop. 52 percent of the playable box (misn10: 29 percent); the straight line from the
  start to the launch pad crosses 910 m of lava.
* The only dry way from the start to the east side (launch pad 2, `last_camera`, the green escape route)
  is the escort loop: north via `strike1`, `base2`, `strike2`, `launch_attack`, then down the escape
  route. The tool asserts that removing that corridor disconnects the start from launch pad 2
  (start -> pad 2 dry route: 2715 m).
* Corridors stay dry and reachable along every escort and strike path (75-110 m), around the start
  (150 m), pads (170 m), bases, CCA outposts, spawn points, and a corridor from the defection waypoint to
  the head of the `openheimer` path. The tool verifies every key point is reachable over dry ground and
  none is on lava.
* The armory and its geyser stand on a minimal island pad in the lava, reached by a narrow (about 40 m)
  dry trail from the start (583 m). It is deliberately a detour: a spur, not a shortcut to the pad.
* Sulphur (the walkable continent) cannot touch lava, so each lake has a two-tile crust moat; the shoreline
  uses the tileset's edge/corner tiles, derived empirically and checked against all 3168 stock rim tiles.

## Focused checks

```sh
lua5.1 Tools/Test-Misn11.lua
lua5.1 Tools/Test-Misn11Coop.lua
lua5.1 Tools/Test-Misn11Presentation.lua
lua5.1 Tools/Test-CRIoWeather.lua Scripts
python Tools/Test-Misn11SourceParity.py
python Tools/Test-Misn11CoopContract.py
python Tools/Test-CoopAuthoredLabels.py
python Tools/Test-SetupMissionShell.py
python Tools/Validate-CampaignRepository.py
python Tools/Build-Misn11Lava.py --dry-run     # lava plan + reachability assertions
```

## Not yet verified

No live run (two- and four-client co-op, campaign progression). Live-verified 2026-10-14: `Lava=1` damages a hover tank on molten tiles at about 159 HP/s. Specifically unproven: that `Goto`/`Attack`/
`SetCommand` FORMATION orders drive the CCA units as intended (the backup squad's formation on an
enemy-team tug, the walker advancing on the convoy); AI pathing around the lava (tugs and wingmen on the
escort route, the CCA squad from the far end of `openheimer`); the dry trail to the armory being drivable
(40 m); the `planet = "io"` campaign key; the Io sky/weather feel and the pad quake; the strike and ambush
difficulty at four players.
