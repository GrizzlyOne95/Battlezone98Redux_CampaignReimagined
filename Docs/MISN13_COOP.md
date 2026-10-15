# Mission 13 offline and co-op

Total Destruction shares `misn13.bzn` / `misn13.lua` between the campaign mission (`crcampgn.ini`
MISSION12, Europa, retrospective `misn1305.wav`) and the strategy listing `CR: Total Destruction
Coop`. Use matching CR, EXU and OpenShim builds. Host on team 1, guests on distinct teams 2-4;
select an NSDF tank, scout, light tank, rocket tank, bomber, or walker and start together. Late
join/rejoin requires a restart. Host departure ends the mission. There is no intro cutscene (the
original has none).

The mission is the second half of the Europa pair: the CCA base is the same one misn12 infiltrates (a
different heightmap), and now the Liberty's platoon, with the Texas Recycler, has to tear it down.

Starting choices follow [the co-op production progression](COOP_STARTING_UNITS.md).

## Map

`Tools/Build-CoopMap.py --mission misn13` rebuilt `Missions/misn13.bzn` from the Battlezone 1.5
original: class `MultSTMission`, the 48 authored CCA objects (Unit Factory `svmuf`, six turrets, nine
tanks, six fighters, four howitzers, four scavengers, the Self-Loader, four silos, barracks, cafe,
comm tower, hangar, checkpoint towers) moved from team 2 to team 5, and four zero-motion `pspwn_1`
team starts (`coop_spawn1`-`4`) 25 m apart at the Drop Zone. Team 1 keeps only the Texas Recycler
(`avrecycle`), the player placeholder and the Drop Zone nav (`apcamr20_camerapod`). Nothing is authored
on teams 2-4. The terrain companions (`.trn/.mat/.lgt`) are Redux's own; the heightmap is the 1.5
(unsmoothed) one. Europa has no lightning key to strip.

The 1.5 BZN is a **mid-play snapshot**, so the builder also strips snapshot state:

| Stripped | Why |
|---|---|
| 133 of 147 `[AiPath]` blocks (every unnamed one) | the engine's runtime unit paths; the 14 named paths stay (`artil_path1`, `artil_point1-4`, `choke_point1-3`, `turret_path1-3`, `slf_path`, `silo_spot`, `edge_path`) |
| `what`/`who`/`where`/`priority` on 28 objects | commands the DLL had already issued (turrets walking their paths, tanks following the factory, the first wave attacking the Recycler, the Self-Loader on its path); the script re-issues every order it needs |
| velocity of the moving units | they were mid-drive |
| duplicate labels | three wingmen were all `svtank0_wingman` (and one `svtank8_wingman`, `svtank3_wingman`), so `GetHandle` was ambiguous; they are now `artil_escort1-3` and `cca_reserve1-2` (matched by position) |

`edge_path` is the play boundary (a two-point rectangle), not cut content. The hangar is the object
labelled `svguntower2` (odf `sbhang`); the east checkpoint tower is `svguntower1` (`sbhqt1`).

## Ownership and rules

Only the campaign leader runs spawns, orders, timers and the win/loss gates. Objectives, dialogue,
markers, removals and results reach every peer through the ordered, acknowledged E/A stream (label-aware
markers, bounded guest waits: the #186 pattern, as in misn11). The base is shared and host-run
(`SetScrap(1, 40)`, `SetPilot(1, 10)`): the authored Texas is the only recycler (the starting recycler of
every human team is disabled) and the host builds. Respawns rally at the Texas until it dies.

| DLL | Co-op |
|---|---|
| CCA team 2 (scrap 200, pilots 40, spawns, AIPs) | team 5 |
| `AddObject` first-come slots: `svapc13`/`svhr13`/`svtk13` | only when team 5 |
| `AddObject`: `abtowe` (last wins), `abcomm`, `avmuf`, `avcnst`, `avscav` x3 | only when a human team (1-4); first-come order kept; `AddObject(nil)` is safe |
| `CountUnitsNearObject(ccamuf, 400, 1)` below 2 | units of **every** human team within 400 m, minus (humans - 1), below 2 (a threshold of 1 + humans) |
| `GetWhoShotMe` warning (misn1302) for the Recycler/factory/scavengers | also fires when a tracked howitzer shoots **any** human's craft |
| `AudioMessage`, `ClearObjectives`, `AddObjective`, `SetObjectiveName`, `RemoveObject`, `SucceedMission`, `FailMission` | through the CR presentation adapter |
| `M.user = GetPlayerHandle()` | kept (it is the host's own handle and nothing reads it) |

Pilot Mode never runs here and aiCore is not loaded: no script manages a human team.

## The CCA strategic AI

The stock AIPs are the CCA's brain, so the script follows the AIP rules proven in misn09 (runtime-
verified under `MultSTMission`): `SetAIControl(5, true)` is a single chunk-root call (never in `Start`,
which kills the host), `SetAIP(..., 5)` stays in `Update` with the DLL's timing (`misn13.aip` 60 s after the
second wave, repeating every 240 s unless held; `misn13a.aip` while a player gun/comm tower stands;
`misn13c.aip` when the factory is hurt), the BZN keeps its `[AiMission]` block, and the team has a
factory (`svmuf13`) and scrap (200). `svmuf13` builds `svtk13`, `svlt13`, `svapc13` and `svhr13`, which
is everything `misn13.aip` and `misn13a.aip` ask for; `misn13c.aip` also asks for `svltnk`, which the
factory cannot build (the 1.5 original skips it too). `misn13b.aip` is older and unused, as in the DLL.

The stock AIPs and `b_misn13.odf` live in Redux's `bzone.zfs` (and its language archives), so the AIPs
are **not** copied into the mod: `Manage-CampaignFiles.ps1` has no `.aip` classifier, and misn09/misn10
rely on the archive the same way. `ODF/b_misn13.odf` (byte-identical) is shipped.

## Win and objectives (owner decision)

The DLL won when the Unit Factory fell. The briefing (`misn13.des`) says "destroy the entire CCA base and
close down any possible escape hatches or supply lines", so the win is now **the Unit Factory, the hangar
(`svguntower2`) and all four silos destroyed** (any order, any human's kills). The DLL's one-shot silo
scrap clamp (150/100/50/0 as silos fall) and the +40 scrap when the factory is attacked are unchanged, so
losing silos still starves the AIP. `misn1303` ("Time to move this little operation on to Titan") plays on
the new condition; the recycler loss (`misn1304`) still beats a simultaneous win. A hangar the map never
provided counts as destroyed.

The stock objective (`misn1300.otf`: "Destroy soviet Unit Factory / Defend your Recycler") no longer
describes the win, so after the DLL's first-frame `AddObjective` the leader replaces it with four text
objectives that every peer shows and updates on change:

| Key | Text | Colors |
|---|---|---|
| `misn13_recycler` | Defend your Recycler | white, red when lost |
| `misn13_factory` | Destroy the CCA Unit Factory | white, green when dead |
| `misn13_hangar` | Destroy the CCA hangar | white, green when dead |
| `misn13_silos` | Destroy the CCA silos (n/4) | white, green at 4/4 |

`misn13.des` (lobby/briefing text) states the real win. The stock win/fail debriefings
(`misn13w1.des`, `misn13f1.des`) are unchanged.

## Restored reinforcement waves (owner decision, marked `-- CR restored waves`)

The DLL declares waves 2-4 (`wave2/3/4`, `*_done`, `*_move`), sets `next_wave_time` to +300 s at the start,
holds two unused spawn geysers (`spawn_geyser1/2`) and three unreferenced routes (`choke_point2`,
`choke_point3`, `turret_path3`), and never uses any of them. They are restored behind `RESTORED_WAVES`:

| Wave | Time | Spawn | Choke | Squad (1 human) |
|---|---|---|---|---|
| 2 | 300 s | `spawn_geyser1` (north-west) | `choke_point3` | 2 `svtank`, 1 `svfigh` |
| 3 | 600 s | `spawn_geyser2` (centre) | `choke_point2` | 2 `svtank`, 2 `svfigh` |
| 4 | 900 s | `spawn_geyser2` | `choke_point3` | 3 `svtank`, 2 `svfigh` |

Each squad is built on team 5 at the geyser and ordered to its choke point; when its lead is within 150 m
(or 120 s pass) every living member takes `turret_path3` toward the east tower; when the lead is within
225 m of `svguntower1` (or 240 s pass) they attack the Texas (the DLL's own first-wave target; the nearest
human if it is gone). Each extra human (cap 4 players, so at most +3) adds one `svtank` and one `svfigh`
to every wave, **and** to the opening rush (built at `choke_point1`, attacking the Recycler). Waves stop
once the Unit Factory is dead and wait 30 s at a time while 16 wave units are alive.

**No pop-in.** Nothing is built at a spawn point that any human is within 400 m of (`WAVE_CLEAR_M`;
`misn13.trn` has `VisibilityRange=250`, so a spawn is always past the fog). A wave whose geyser is watched
uses the other geyser and still drives to its own choke point. If both geysers are watched it waits 30 s and
tries again. The opening-rush extras try `choke_point1`, then `spawn_geyser2`, then `spawn_geyser1`;
`spawn_geyser2` is only about 280 m from `choke_point1`, so a team at the choke point gets its rush from
`spawn_geyser1`.

## Idle wingmen

Five `svtank` wingmen stand beside the artillery pad in the 1.5 map. The snapshot shows three on DEFEND
and two on AI command **14**. In the 1.5 command numbering (NONE 0, SELECT 1, STOP 2, GO 3, ATTACK 4,
FOLLOW 5, FORMATION 6, ... DEFEND 15; the Defend turrets and the artillery carry 15) command 14 is
`GET_BOMB`: a leftover of the snapshot, since no bomb pickup exists on the map and the DLL never orders
them.

| Group | Units | Role (host only) |
|---|---|---|
| Artillery escort (owner decision) | `artil_escort1-3` | Defend at the start; when the artillery march starts (15 min) they take `artil_path1` with it and the DLL's `escort_tank`; once the artillery splits at the geyser each follows its howitzer (1, 2, 3; the first living one if its own died) |
| Factory reserve (inferred) | `cca_reserve1-2` | Defend at the start; race to the Unit Factory when it is attacked (the DLL's `muf_attacked`), to `silo_spot` when a silo is; defend there; return to guard after 90 s so a later alarm calls them again |

## Other restored content

- **misn1301** (Collins: "you provoked the CCA Army ... use [the Texas] to set up your base of command and
  take out that Unit Factory") plays once, 25 s after the first attack, i.e. after the 22 s opening
  briefing (native audio also queues).
- **misn1305** is the campaign retrospective (`voice =` in `crcampgn.ini`), not an in-mission line.
- **misn1303** is *not* unused: it plays on victory. `Tools/TranscriptSources/GoombaBZ/campaigns.csv`
  annotates it "Unused voiceover." (upstream data kept verbatim; see that folder's README).
- The disabled bomber retreat/reload (with `avhraz` replacements) stays **disabled** (owner decision), as
  do the first-APC attack on the communications tower and the other commented DLL branches. The source
  parity test pins this.

## Weather

The shared Europa director (`Scripts/CREuropaWeather.lua`, `Docs/EUROPA_WEATHER.md`) runs on every peer; the
leader decides. `Scripts/CREuropaSites13.lua` is generated by `Tools/Build-EuropaSites.py misn13 --source-dir
Missions` (120 frost-haze anchors, 14 vents incl. the named geysers, the playable box). Beats, each once:
level 2 at the start, 3 when the artillery marches or wave 3 lands, a 60 s level-5 burst with an ice quake
(0.7 for 5 s) and a radiation surge when the Unit Factory falls, calm on the win. The director is cosmetic
(no damage, no radar or sensor change).

## Focused checks

```sh
lua5.1 Tools/Test-Misn13.lua
lua5.1 Tools/Test-Misn13Coop.lua
lua5.1 Tools/Test-Misn13Presentation.lua
python Tools/Test-Misn13SourceParity.py
python Tools/Test-Misn13CoopContract.py
python Tools/Test-CoopAuthoredLabels.py
python Tools/Test-SetupMissionShell.py
python Tools/Validate-CampaignRepository.py
python Tools/Build-CoopMap.py --mission misn13   # reproduces Missions/misn13.bzn
```

`Test-Misn13SourceParity.py` strips every `-- CR ... >>` / `<<` region and proves the DLL port is unchanged;
the substitutions outside the markers (team 2 -> `ENEMY_TEAM`, `SetAIP(..., team)`, the human-team factory
count, the whole-base win guard) are normalized and asserted explicitly.

## Inferences (not from the DLL or an owner decision)

- Command 14 is `GET_BOMB`; the reserve role for the two tanks that carried it is a design choice.
- The squad compositions (2+1 / 2+2 / 3+2), the 16-unit live cap, 150/225 m arrival radii and the 120/240 s
  timeouts are tuning guesses sized against the DLL's first wave (2 tanks + 2 fighters) and the AIP.
- Waves 3 and 4 spawn at `spawn_geyser2` (the centre, about 1.5 km from the east tower) and wave 2 at
  `spawn_geyser1` (the north-west corner, about 2.9 km out), so the first reinforcements are the slowest
  to arrive and the choke points alternate between the two routes.
- `Goto(unit, "turret_path3")` is assumed to run the path from its first point (by the CCA silos in the
  west). From `choke_point3` that is a 620 m detour back west; from `choke_point2` it is about 1.4 km west
  and then the whole path east again. If Redux starts a path at the nearest point instead, the waves simply
  cut the corner.
- The AIPs run under `MultSTMission` (runtime-proven in misn09); `misn13a.aip`'s bomber logic needs a
  human `abtowe`/`abcomm`, which guests' towers now satisfy (only if the host's Lua sees guest-built
  objects: guest-built objects are not in the host's `AllCraft`).
- `AddObject` is called on the host for the AIP's units and the shared base's objects; whether it is called
  for objects a guest builds is unverified, so the tower/muf/scavenger slots may stay empty in co-op.

## Live-harness checklist (not yet run)

1. 2- and 4-player co-op boot on `misn13`: no `[coop] unresolved`, `coopUnresolved == 0`, the nav pod
   "Drop Zone" marker appears on every peer.
2. `GetAIP(5)` reads `misn13.aip` about 70 s in, team 5 builds (`svtk13`/`svlt13`) from the factory and
   spends scrap; `misn13a.aip` after a gun/comm tower exists; `misn13c.aip` after the factory is hit
   (this is the AIP-under-MultST check on this map).
3. The first wave, then waves 2-4 at 300/600/900 s: spawn at the geysers, reach the choke points, take
   `turret_path3`, attack the Texas; extra humans add units. Check the path start behaviour (inference above).
4. misn1301 plays after misn1300 on every peer; the four objectives appear on every peer and progress
   (silos n/4, hangar, factory) updates.
5. The win needs the factory, hangar and four silos; victory plays misn1303 and the result reaches every
   peer; Recycler loss fails with misn1304.
6. The artillery escort follows the march; the reserve answers a factory/silo attack; the factory-safety
   count with 2-4 humans near the factory resumes the AIP.
7. Guest-built `abtowe`/`avmuf`/`avscav` and the bomber response (see inference above).
8. Europa weather on every peer; the factory-fall quake is shared; the Europa sky/fog feel.
9. Host loss, out-of-lives failure, restart-required warning for late joiners.
10. Campaign path: `planet = "europa"`, retrospective voice `misn1305`, the shared BZN loads offline.
