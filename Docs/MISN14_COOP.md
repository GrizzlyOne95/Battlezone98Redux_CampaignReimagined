# Mission 14 offline and co-op: The Three Beacons (Concept C)

Fury roster amendment (2026-10-16): recurring waves lead with restored `crfraz`
fighters, retaining a SAV and later SAT escalation. The controllable squad keeps
its existing identity. See [Fury fighter](FURY_FIGHTER.md) for the current roster;
earlier SAV-only descriptions below document the Concept C baseline.

The Three Beacons shares `misn14.bzn` / `misn14.lua` between the campaign mission (`crcampgn.ini`
MISSION13, Titan, retrospective `misn1422.wav`) and the strategy listing `CR: The Three Beacons
Coop`. Use matching CR, EXU and OpenShim builds. Host on team 1, guests on distinct teams 2-4;
select an NSDF tank, scout, light tank, rocket tank, bomber, or walker and start together. Late
join/rejoin requires a restart. Host departure ends the mission.

The rework is the owner's **Concept C**: the mission is rebuilt around the NSDF's own Furies. The Fury relics the
NSDF recovered on Io (misn10/11) come to Titan with the Liberty's platoon. Command activates them, the players
command them briefly, then lose control; the rogue Furies fall on NSDF and CCA alike, and the CCA surrender is a
consequence of that onslaught. The three beacons, the CCA scientists and the win are the stock mission's.

Starting choices follow [the co-op production progression](COOP_STARTING_UNITS.md).

## Story beats (host-triggered, shared by every human)

| When | What | Lines |
|---|---|---|
| Start | Stock intro (two path shots on the Texas); a dormant NSDF Fury squad stands beside the Texas, locked | 1401 |
| Intro end | Stock objective `misn1401.otf`; beacon 1 15 s later | 1416 |
| Intro end + 40 s | **Activation scene**: shared object camera on the squad lead, about 15 s | 1402 (Collins), 1423, 1424 (Buzz), queued |
| Scene end | **Control**: each Fury follows its own human at priority 0, so the player can select and order it; objective "Fury squad online" (green) | |
| + 75 s | **Loss of control**: a 7 s shared shot of the squad | 1425 (Buzz: "do you have control?") |
| Shot end | The squad re-teams to the Fury team (6) and attacks: odd slots the nearest CCA craft, even slots the nearest NSDF; objective turns red | 1426 (Collins: "Something's not right ... proceed with rescue operation") |
| Squad turned + 120 s | Once, while a beacon is still waiting | 1427 (Collins: "I know you have a situation on your hands ...") |
| A beacon waiting 180 s | Once per beacon | 1420 (Collins: "Get those men, Commander") |
| Intro end + 420 s, then every 180 s | Rogue Fury waves (see below) | 1403 on the first |
| Wave 3, or the Furies break the CCA earlier | CCA surrender | 1404, 1405 |
| Wave 4 (after rescue 3) | Collins' message and the base shot (only when no human is in a fight) | 1406 |
| Wave 5 (after rescue 3) | Rescue the CCA scientists; APC within 200 m of the barracks, 15 s, back within 300 m of the Texas wins | 1407-1411 |

## Team map (owner decision)

| DLL team | Co-op team | Why |
|---|---|---|
| 1 (player, Texas, nav pods, beacons) | 1 (host) + 2-4 (guests) | humans; the shared base is the host's team 1 |
| 2 (CCA) | **5** | `Build-CoopMap.py` moved the 13 authored CCA objects; `SetAIControl(5)` at chunk load, `SetAIP("misn14.aip", 5)`, `AddPilot(5, 30)`, `SetScrap(5, 45)` |
| 3 (Furies) | **6** | waves and the rogue squad; never allied with anyone |
| 1 (rescued pilots), 1 (surrendered base/towers) | **7** | survivors and the surrendered barracks, four towers and both power plants; allied with every human, never with 5 or 6 |

Every DLL team-2/3 literal is gone (the source-parity test asserts it). The surrender `AllCraft` loop flips only
team 5 craft, so a guest's team-2 craft is never neutralised. Pilot Mode never runs here and aiCore is not
loaded: no script manages a human team.

## The NSDF Fury squad

| | |
|---|---|
| ODF | `ODF/avsav14.odf` (CR), a full copy of the cut stock NSDF Fury `avsav` (1.5 stock: 3500 hp, `gbolt`, slow hover, `baseName = "avsav"` mesh) |
| Why a copy | Stock `avsav` names `aiName = "SAVFriend"`. Redux 2.2.301 registers no such AI process (the exe has `SAVEnemy` and `.?AVSAVEnemy@@` but no `SAVFriend` string or RTTI), so on a human team the stock unit has no AI and cannot take orders (a craft ODF with an unknown/missing aiName has `CanCommand` false). The copy is `classLabel = "wingman"` with `TankFriend` / `TankEnemy`, the commandable tank AI `hvsat` uses. Redux has no ODF inheritance, so every key is spelled out |
| Size | two per human team, built on that team (8 with four humans) |
| Dormant | `Stop(unit, 1)`: visible, not commandable |
| Handover | `Follow(unit, <its human>, 0)` (priority 0 = player-commandable) |
| Loss of control | `SetTeamNum(unit, 6)` plus `Attack(unit, target, 1)`, re-picked every 6 s when the target dies and every 30 s anyway |

**Why re-team instead of swapping in hostile `hvsav`:** the Furies the players just commanded are the ones that
turn on them, with their damage, positions and selection intact, and nothing pops in under the camera. A
re-teamed unit keeps the AI process it was built with (the friendly tank AI), so the script drives its targets;
`hvsav` waves keep their own `SAVEnemy` AI.

## Rogue Fury waves (owner decisions 6/7)

The DLL's three spawn triplets (`alien1/2/5`, `alien3/4/1`, `alien5/6/3`) and its 180 s cadence stay; the first
wave comes 420 s after the intro (the DLL's 720 s is kept verbatim behind `FURY_WAVES` in the port).

- 3 `hvsav` plus **one per extra human**; from **wave 4**, one `hvsat` Fury Tank (two with 3+ humans).
- At most **12 live Furies** (squad included once rogue). A capped wave still counts, so the story (surrender at
  wave 3, Collins at 4, the CCA rescue at 5) never stalls; the cap keeps the Fury Tanks when it trims.
- **No pop-in**: nothing is built within 400 m of any human. `alien1/3/5` sit in the CCA base and `alien2/4/6`
  near the NSDF drop zone, so a watched point falls back to the spare alien points, then to the farthest
  unwatched corner of the `world` AOI (pulled 150 m inward). If every candidate is watched the wave waits 30 s.
- Each wave splits its first targets between the CCA and the nearest NSDF at priority 0 (the Fury AI keeps the
  initiative).

## The CCA surrender

Stock: the third wave. Concept C adds the consequence trigger: once the squad has turned, the CCA also surrenders
as soon as its Recycler (the DLL's unused `erecy`) or its Unit Factory is destroyed. The surrender itself is the
shipped 1.5 one: CCA craft go to team 0 (tanks/turrets/fighters retreat to `escape`), the barracks, the four
towers **and both power plants** (`sblpow1_powerplant`, `sblpow55_powerplant`, restored from the 1.5 exe) join
team 7.

## Rescues and the win

- Survivors: `BuildObject("aspilo", 7, "helpN")`, then the shipped 1.5 `SetIndependence(guy, 0)` and
  `Defend(guy, 1)`. `SetIndependence` is only ever called on a live stock `aspilo` (Docs/BZR_LUA_AGENT_REFERENCE.md
  rule 15).
- A rescue carrier is the tracked human-team APC or **any human piloting an `avapc`** (guests have no factory, but
  they can drive one). The APC camera follows the carrier that actually arrived.
- The beacon reminder (1415) fires for any human within 200 m. The CCA pickup takes whichever carrier reaches the
  barracks first; that carrier is frozen as `M.apc` and must reach the Texas (win stays stock: within 300 m).
- Razor tie (owner decision 8): the second beacon's first pilot is named **Razor Two**, Razor One's wingman from
  misn12's Razor flight; he is the pilot who speaks misn1418. No new mechanics.
- Briefing fix (owner decision 4): the stock `misn14.des` says "Recycler Utah" while 1414 and the debriefs say
  Texas. The CR root `misn14.des` (lobby/briefing text) names the Texas; `misn1401.otf` never named the Recycler.

## Shipped-1.5 behaviour restored (owner decision 2)

| 1.5 exe | Port before | Now |
|---|---|---|
| `GetHandle("sblpow1_powerplant")` / `("sblpow55_powerplant")`, surrender to team 1 | missing (power plants stayed CCA) | fetched at start, surrender with the base (to 7) |
| `SetIndependence(guy, 0)` before `Defend(guy, 1)` | missing | restored (allowlisted) |
| `SetAIP("misn14.aip", 2)` | `SetAIP("misn14.aip")` | `SetAIP("misn14.aip", 5)` |

## Titan weather hook (not owned here)

`Scripts/misn14.lua` has one guarded wiring point, region `-- CR Titan weather hook >>`. If a module
`CRTitanWeather` exists and exports `MissionHook(event, ...)`, it is called (always through `pcall`) with:

| Event | Where | Arguments |
|---|---|---|
| `init` | every peer, once the session is ready | `{ authority, mission = "misn14", send }`; `send(op, ...)` exists on the host only and queues `op` (must start with `Titan`) on the ordered presentation stream |
| `update` | every peer, every frame | `dt` |
| `beat` | host/offline | `"start"`, `"activation"`, `"rogue"`, `"wave"`, `"surrender"`, `"rescue_cca"`, `"win"`, `"lose"` |
| `net` | guests | `op, ...` of a received `Titan*` event |
| `save` / `load` | host/offline | return value stored in `M.titanWeather` / that value after a load |
| `object` | every `AddObject` | handle |
| `shutdown` | co-op re-initialisation | |

A missing module is a silent no-op; a module that throws is logged once and ignored. The mission does not load
`Environment.lua` (the weather agent owns that wiring).

**Wired to the merged director.** `CRTitanWeather` landed on main (#206, `Docs/TITAN_WEATHER.md`) with an
`Init`/`Update`/`ApplyNetEvent` API and no `MissionHook`, so the hook region adapts the events onto it (the mission
logic is unchanged): `init` -> `Init{authority, seed, sites = CRTitanSites14, startLevel 1, targetLevel 2, send}`;
`update` -> `Update(dt)` (plus one host `AnnounceState` once the co-op session is ready); `net` ->
`ApplyNetEvent` (`TitanState` / `TitanRoll` ride the ordered stream); `save`/`load` keep the seed and the director
state in `M.titanWeather`; beats: start `SetTargetLevel(2)`, activation `Roll(70, 0.9)`, rogue
`ForceLevel(3, 120, 15)`, surrender `SetTargetLevel(3)`, CCA rescue and win release the force and ease to 2 / 1.
Not live-verified with the real director (the live run above used no director).

## VO usage

| Line | Speaker | Stock use | Now |
|---|---|---|---|
| 1401 | Collins | intro | intro |
| 1402 | Collins | **cut** (commented out in the DLL) | opens the activation scene |
| 1403 | Buzz | first wave | first wave |
| 1404 / 1405 | Romeski / Buzz | surrender | surrender (third wave or the CCA broken) |
| 1406-1413 | | stock | stock |
| 1414 | Buzz | Texas lost | unchanged |
| 1415 | Buzz | APC reminder near beacon 1 | any human |
| 1416-1419, 1421 | | stock | stock (1418 = Razor Two) |
| 1420 | Collins | **cut** | rescue nag, once per beacon left 180 s |
| 1422 | Grizzly One | campaign-map narration (exe string table) | `voice =` in `crcampgn.ini` |
| 1423 / 1424 | Buzz | **cut** | activation countdown / transfer |
| 1425 | Buzz | **cut** | loss of control |
| 1426 | Collins | **cut** | after the squad turns |
| 1427 | Collins | **cut** | once, 120 s after the squad turned while a beacon waits |

Every Redux language archive (en/de/es/fr/it/pt/ru) ships 1402, 1420 and 1423-1427, so no wav is bundled.
A line that starts while another still plays is queued behind it (ScriptSubtitles `Play` would cut it off).

## Co-op ownership

Only the campaign leader runs spawns, orders, team switches, timers and the win/loss gates. Objectives, dialogue,
markers, removals, cameras and results reach every peer through the ordered E/A stream (label-aware markers,
bounded guest waits) and the C camera snapshot (the misn12 transport). The base is shared and host-run (team 1:
`SetScrap(1, 30)`); the Texas is the only recycler and respawns rally at it until it dies.

## Focused checks

```sh
lua5.1 Tools/Test-Misn14.lua
lua5.1 Tools/Test-Misn14Coop.lua
lua5.1 Tools/Test-Misn14Presentation.lua
python Tools/Test-Misn14SourceParity.py
python Tools/Test-Misn14CoopContract.py
python Tools/Test-CoopAuthoredLabels.py
python Tools/Test-SetupMissionShell.py
python Tools/Validate-CampaignRepository.py
python Tools/Build-CoopMap.py --mission misn14   # reproduces Missions/misn14.bzn
```

`Tools/Misn14Fixture.lua` is the shared mock world (authored coordinates). `Test-Misn14SourceParity.py` strips
every `-- CR ... >>` / `<<` region and asserts each substitution outside them.

## Inferences and tuning guesses

- FURY_ACTIVATE_S 40, FURY_CONTROL_S 75, first wave 420 s, the 12-Fury cap and the two-per-human squad are tuning
  guesses; the cap and scaling are owner decisions.
- The squad's slow 1.5 hover stats (25 m/s) are the stock cut unit's; Redux's own `avsav.odf` is a 200 m/s sav.
- The CcaBroken trigger only counts after the squad turned, so a human-led raid on the CCA before the Furies go
  rogue does not short-circuit the story.

## Live evidence (offline, 2026-10-14)

GOG Redux 2.2.301 in a private copy of the harness instance (`C:\BZRCoop\misn14sp`, OpenShim 51d9fbb, windowed),
the branch's `misn14.lua` with an appended Lua driver (test assists, labelled ASSIST: healing, a spawned APC moved
between beacons, waves forced every 6 s, the activation and control windows shortened). A command-line launch of
`misn14.bzn` loads the **stock** 144-object map from `bzone.zfs` (the mod folder is not searched for a CLI mission),
so the run used a copy named `m14t.bzn` in `addon\m14t\` (with the CR scripts beside it; the engine still looks for
`misn14.lua`, the TerrainName). Results (run of 12:18, mission clock):

| Check | Result |
|---|---|
| Stock `avsav` on team 1 | `CanCommand` **false**; Follow/Goto ignored (command stays 0, distance unchanged) |
| `avsav14` squad, dormant then handed over | `CanCommand` true; after handover command 5 (FOLLOW) on the player; a priority-0 Goto ran (56 m -> 4 m) and an Attack on a CCA scavenger took (command 4, target team 5) |
| Activation scene | 1402, 1423, 1424 played (native AudioMessage queues them); scene lasted its 15 s; objective "Fury squad online" shown |
| Loss of control | 1425 then 1426; both Furies `SetTeamNum` -> **6**, `CanCommand` false, attacking a CCA `svturr` (team 5) and the Texas (team 1) |
| Rogue waves | built on team 6, 3 per wave offline, `hvsat` joined at wave 4 (`hvsav=9, hvsat=1`) and wave 5; nearest Fury at least 518 m from the player when checked one second after a build |
| Surrender (third wave) | 1404/1405; CCA craft (recycler, factory) -> team 0; barracks, **both power plants** and the surviving towers -> team 7 |
| Rescues | three beacons by the APC (1409/1417/1418/1419), survivors held at the beacon |
| Win | 1406-1408, pickup at the barracks, APC back at the Texas: 1411 and `RUN_WAS_SUCCESS` (`misn14w1.des`) |
| Lua errors | none (the driver wraps Update in `pcall` and logs failures; none logged) |

Not verified live: the cinematic framing of the activation/loss shots (the window was in the background and its
captures stopped refreshing after the intro, so the screenshots show a stale cockpit frame), and everything co-op.
Redux logs one "mission issue": the `avsav` mesh is not preloaded (the squad loads it at run time); harmless but a
possible hitch when the squad is built 3 s in.

## Live checklist

1. Offline: the activation scene plays, the squad is selectable and obeys Follow/Goto/Attack, control loss
   re-teams it and it attacks, waves spawn on team 6 away from the player, the surrender flips the CCA craft to 0
   and the barracks/towers/power plants to 7, the win path completes. (See "Live evidence" below.)
2. Co-op (2-4): guests' squads on their teams; can a guest command a host-built unit on the guest's team? If not,
   the squad still follows its human (Lua Follow from the host).
3. `SetTeamNum` on the host replicates the re-teamed squad to guests.
4. `GetAIP(5)` = `misn14.aip`, team 5 builds from its factory before the surrender.
5. Every guest hears the scene lines in order, films the shared shots and shows the objectives; `coopUnresolved == 0`.
6. A guest driving an APC rescues a beacon and carries the scientists.
7. Host loss, out-of-lives failure, restart-required warning for late joiners.
