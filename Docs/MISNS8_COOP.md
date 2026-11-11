# Mission S8 co-op: Punishing the Black Dogs (misns8)

Shared offline / 2-4 player co-op port of the CCA mission `misns8`. The Black Dogs (an AI-run American base: Unit
Factory, Recycler, gun towers, construction rigs) first expand around the centre geysers, move their factory in a
convoy, then (plan C) pack the Recycler and run for the escape route. The humans' CCA base is already there; General
Romeski joins late with the Furies, the SAVs the humans build turn on him, and the mission is won when the Black Dog
Recycler dies. One `Missions/misns8cr.bzn` and one `Scripts/misns8cr.lua` serve both modes. Companion to
[`CCA_COOP_RUNTIME.md`](CCA_COOP_RUNTIME.md) (the shared runtime) and [`MISNS1_COOP.md`](MISNS1_COOP.md) (the template);
the faithful port underneath is `Scripts/misns8.lua` (`Tools/Test-Misns8.lua`, `Tools/Test-Misns8SourceParity.py`).
Status: **host-tested only**; nothing here has run in the game (see "Live checklist").

## Layout

| File | Role |
| --- | --- |
| `Scripts/misns8cr.lua` | The faithful port plus marked `-- CR ... >>` / `<<` regions. Outside them it is exactly `misns8.lua` (`Tools/Test-Misns8CoopSourceParity.py`). Holds the runtime CONFIG, the native shadows, the restoration and the Titan weather beats. |
| `Scripts/CRCCARuntime.lua` | Shared co-op runtime, including the CCA mission's NSDF-to-Black-Dog ODF remap. |
| `ODF/crns8.aip` | Black Dog variant of stock `misns8.aip`; its constructor build slot uses `bvcnst`. |
| `Scripts/CRTitanWeather.lua`, `Scripts/CRTitanSitesS8.lua` | Titan weather and the generated sites for this map (the sites table has no pools and an empty wet mask; the weather runs without them). |
| `Missions/misns8cr.{bzn,vxt}`, `misns8.{hg2,lgt,mat,trn}` | Map and companions (built by `Tools/Build-CoopMap.py`, not part of this change). |
| `Tools/Misns8Fixture.lua`, `Tools/Test-Misns8Coop.lua`, `Tools/Test-Misns8CoopSourceParity.py`, `Tools/Test-Misns8CoopContract.py` | Multi-peer fixture and tests. The one camera (the betrayal cutscene, below) is covered by `Test-Misns8Coop.lua` through the real presentation transport; there is no separate presentation test. |
| `ODF/savfury.odf`, `Assets/ModelFixes/savfury.*` and `csf11*.geo`, `Assets/Textures/savfury_{d,e}.dds`, `Materials/savfury.material`, `Tools/Build-SavFury.py`, `Tools/Test-SavFuryAssets.py` | The infected Fury-blue SAV the betrayal swap builds (see "Betrayal cutscene"). |

## Teams and ownership

| Team | Use |
| --- | --- |
| 1-4 | Humans (host on 1). The authored CCA Recycler (`svrecycle`, mission-only ODF `svrecy8`: stock `svrecy` with the Fury factory `savmf` as its factory build item, so a rebuilt factory still makes `savtnk`) and Factory (`svmuf`), the nav beacons (`cam`, `basecam`, the restored Choke Point beacon) and Romeski (`svtank`) stay on team 1: shared, host-run. Extra starting recyclers are disabled. |
| 5 | The Black Dogs (the authored team 2: labels `avrecycle` and `avmuf` now use ODFs `bvrecy` and `bvmuf`, plus the powerplants, base towers, and everything the AI builds). The body still says team 2; the CR layer maps it to 5 for every call that names it (below). |
| 7 | Support (allied to humans; unused here). |

Only the authority (host, or the offline player) runs the body; guests only present and run weather. `SetAIControl(5,
true)` runs once at chunk load; `SetAIP` is called only from the body's `Update`, always with team 5 (`crns8.aip` for
`misns8.aip`, then `misns8a/b/c/d/f/g.aip`).

Calls the body makes with a literal enemy team 2 that the CR layer remaps to team 5: `SetScrap(2, 40)`,
`SetPilot(2, 60)`, `GetScrap(2)` (about ten reads), `AddScrap(2, ...)` (including the `AddScrap(2, 2)` trickle),
`CountUnitsNearObject(..., 2, ...)` (the plan C defence test and the rig maintenance counts), `SetPerceivedTeam(x, 2)`,
`BuildObject(..., 2, ...)` (scavengers, scout, artillery, retaliation tanks, replacement factory, the hostile `savs8`) and
`SetAIP(name)`. The first five are not covered by the runtime and are wrapped in the mission's runtime region.
**Without the count/scrap remap plan C would start at once** (the defence test would see no team-2 towers): the test
suite asserts every `CountUnitsNearObject` is for team 5.

## Humans as one trigger

`GetPlayerHandle` returns the token `crcca_players`. The body uses `M.user` in five places; each is handled:

| Body use | Co-op meaning |
| --- | --- |
| `Distance(M.user, M.avmuf) < 100` (convoy warning), `Distance(M.user, M.key_tank) < 150` (Romeski arrives) | The NEAREST human decides (`WrapDistance`). |
| `Distance(M.key_tank, M.user) < 130` (Romeski asks for help) | The token is the second argument; the CR layer swaps it, so the nearest human decides. |
| `M.user == GetWhoShotMe(M.key_tank)` (the player shot Romeski) | `GetWhoShotMe` is wrapped: a shot from ANY human's ship returns the token. |
| `Attack(M.key_tank, M.user, 1)` (revenge), `Follow(M.key_tank, M.user, 1)` (asks for protection) | The token is replaced by the human nearest to Romeski, as a real handle. |

## Scaling and concealed arrivals [owner rules, mission decisions]

Scaled/concealed ODFs (`scaledOdfs`): `bvtank` (the retaliation tanks; stock spelled it `bvtavk`, an ODF that does not exist), and, concealed only, `bvsca8` (scavengers),
`bvra8` (the scout), and `bvartl` (the Black Dog artillery replacing the body's `avart8` request). They become tickets: the body gets a negative request id and the
unit is built on the next frame with its orders replayed. Everything else is built directly: the replacement factory
(`bvmuf`; the body queries it with `IsDeployed`/`Pickup` and it is the AI's producer), Romeski, the nav beacons and the
hostile `savs8` built in place of a SAV.

The only scripted attack wave is the retaliation squad: when the Black Dog Factory dies mid-convoy the body builds two
`bvtank` at `t1post` and sends them against the CCA Recycler. One `BeginEvent()` (a `-- CR co-op scaling >>` region
before the first tank) mirrors the first tank with `min(floor(humans/2), 2)` extras of the same kind, entry and orders:

| Humans | Squad |
| --- | --- |
| 1 (offline) | 2 |
| 2 or 3 | 3 |
| 4 | 4 |

Cap: at most 12 live scaled units; extras are the only requests dropped for it. The rest of the Black Dog army is the
AIP's production, which cannot be ticketed; it grows with the enemy economy instead: enemy starting scrap is
`40 + 10 per guest` (`ENEMY_SCRAP_PER_GUEST`), the CCA's `25 + 10 per guest` (runtime default). Set the constant to 0
to disable the enemy bonus.

No pop-in: a scripted ticket unit is never built within 460 m of any human. If a human is near the entry path the next
authored entry in `fallbackEntries` (`a_post1`, `t2post`, `t3post`, `american_spawn`) is tried, else the request waits
(saved in `M.crcca`). Known exceptions (see risks): the replacement factory, Romeski and the beacons are built directly.

## Timer, win and loss

- Win: unchanged. The Black Dog Recycler dies -> `misns803` + `misns808` with Romeski alive, `misns814` otherwise ->
  `SucceedMission(..., "misns8w1.des")` once, on every peer. `game_over` is the won flag: nothing can fail a won mission.
- Loss: the stock mission has none. The runtime's out-of-lives path fails everyone (no description is passed; the stock
  set has no loss `.des` for this mission).
- Leader departs: every guest fails the mission (`HasLeaderDeparted`).

## Restored content [owner decision 2026-11-01]

Cut-content restorations live only in the CR layer, apply offline and in co-op, and each has a flag (`RESTORED_*` at the
top of the runtime region of `misns8cr.lua`). Each is gated on what `misns8cr.bzn` carries.

| Restoration | Cut block it comes from (`Scripts/misns8.lua`, same text in `References/Misns8Source/Misns8Mission.cpp:1440`) | Status in this map |
| --- | --- | --- |
| Choke Point nav beacon (`RESTORED_CHOKE_CAM`) | Plan C, in the `recycle_move` block: `if (GetDistance(avrecycle, dis_geyser2) < 100.0f) && (!recycle_message)` -> `AudioMessage("misns802.wav")`, `cam4 = BuildObject("apcamr", 1, "last_nav_spawn")`, named "Choke Point" | `dis_geyser2` and the `last_nav_spawn` path exist; the `escape_route` passes about 80 m from `dis_geyser2`. The cut guard (`recycle_message`) is already set by the live plan C block, so it could never fire; the restoration uses its own flag (`State().r.chokeCam`). The nav beacon is restored (so players can chase the fleeing Recycler); `misns802.wav` is NOT replayed because `misns815/816` already announce the retreat in almost the same words (802 differs only by the camera offer). `M.cam4` is kept in the mission state. Skipped when the path or `dis_geyser2` is missing. The Recycler must first have been seen more than 100 m from `dis_geyser2` (it starts about 1 km away in `misns8cr.bzn`), so the beacon cannot drop the instant the retreat begins. |

Unused shipped voice lines [owner decision 2026-11-01] (`RESTORED_VOICE_LINES`): the wav and `Text/misns8NN.txt` ship in the game but the DLL never plays them. They go through the CR `AudioMessage` (replicated to guests, queued behind a line still playing) and are latched in `M.crcca.r` (kept by Save/Load).

| Line | Transcript | Trigger | Why it fits |
| --- | --- | --- | --- |
| `misns806` | "Commander, any fool could see that those readings indicate no abnormalities in our new weapons. Perhaps, Commander, you cannot issue orders correctly." | The `danger_message` pair (`misns805`, then the body's `misns818`): the CR layer plays 806 in place of 818 | 806 is the whole of `misns818` plus Romeski's rebuttal (longer wav, same opening sentence), so queueing it after 818 would repeat the sentence. Same beat, same speaker, complete exchange. |
| `misns809` | "What the..." | Once, immediately before the first of `misns810` (Romeski cries for help) or `misns812` (his scream) | His reaction to the malfunctioning SAVs before he reacts to them. |
| `misns813` | "This does not look good, comrades." | When Romeski dies (`general_dead`, after the scream), once | The reaction to his death. |

Skipped, with the reason:

- Plan A turret orders (the `/* if ((IsAlive(avturret3)) && (!turret_move)) ... */` block, `misns8.lua` lines 354-476, and its
  plan B copy at 671-697): scripted `Goto(avturret1..3, "center_path..")`, `Defend`, `popartil` defend. The map authors no
  turrets (`bvtur8` comes from the AIP) and the block would fight the AIP for them; the live `new_turret_orders` flag
  already retires it. `center_path2`/`center_path3` exist only for this block and stay unused.
- Plan C escort block (`/* if ((!escort1_build) && ... bvraz ... Follow(escort, avrecycle) */`, lines 816-866, with its
  later `Follow` copy at 852): `escort_time` starts at 99999, so the cut condition `escort_time < Get_Time()` could never
  be true even in the original; restoring it would mean inventing its timing and extra enemy strength.
- `rigsabuildn` scrap > 18 rig Dropoff (lines 611-631): repeats the live `scrap > 14` block.
- SAVs follow the Recycler when there is no Romeski (lines 1187-1252): it orders the humans' own tanks to follow the
  ENEMY Recycler.
- Audio `misns806`, `misns809` and `misns813` are restored (table above). `misns811` (a variant of `misns818`
  ending "Continue with the operation") is audited and skipped: it duplicates the `misns805`/`misns818` exchange.

## Betrayal cutscene (CR addition, presentation only)

Gameplay is unchanged: the swap block of the faithful body still decides who is swapped, when its condition first
holds, and what the hostile twins do. The CR layer (`Restored.Cutscene`, in the `-- CR restored content >>` region)
wraps it in a short shared shot. Switches: `RESTORED_BETRAYAL_CUTSCENE` and `RESTORED_INFECTED_SAV`.

| Beat | Behaviour |
| --- | --- |
| Trigger | Leader/authority only, once, the first frame `general_spawn and (sav_attack or not IsAlive(key_tank))` holds and at least one SAV slot is alive and not yet swapped. State is `State().r.cs` (inside `M`, so it saves and an old save without it loads). A save whose swap is already done starts no shot. |
| Swap delay | The `savN_swap` flags of the alive SAVs are set to true for 3 s (`BETRAYAL_SWAP_DELAY`), so the body skips them; at +3 s they are set back to false and the body swaps in the same frame. Nothing else in the body reads those flags. |
| Shot 1 (0-3 s) | `CameraObject(key_tank, -2500, 1200, -4500, <first live SAV>)` every frame (offsets are centimetres: 25 m left, 12 m up, 45 m behind Romeski, looking at the SAV column). If Romeski is already dead, the first live SAV is the subject. |
| Shot 2 (3 s on) | The frame after the swap, the camera cuts to the nearest infected SAV (nearest to Romeski, else to the player): `CameraObject(twin, 3500, 1200, 4500, twin)`. If every twin dies, the shot ends early. |
| Hard cap | 11 s (`BETRAYAL_SHOT_SECONDS`) after the trigger, from `GetTime()`: `CameraFinish()` and the music restore always run, even when subject and target are gone (`holdCamera` stops re-issuing for an invalid handle, so the timer is the only thing that ends a frozen shot). |
| Camera | `holdCamera = true` in the runtime CONFIG; `CameraReady/CameraObject/CameraFinish/CameraCancelled` are the runtime's shadows, so guests follow the leader's shot through the existing camera stream. The shot is armed once through a local `camOn` flag, never stacked. Skip behaviour is the runtime's: offline a skip releases the camera but the swap and the 11 s timer continue; in a network game the skip is per player and the shared timing is untouched. No new skip rules. |
| Music | Presentation op `S8Music` (`config.presentationOps`) runs on every peer: `duck` = `exu.FadeMusic(0.25, 1.5)` at the start, `restore` = `exu.FadeMusic(1, 3)` at the end. `exu.UpdateMusic(dt)` runs once per Update on every peer (the runtime `update` hook) from the first duck until 3.5 s after the restore. Every call is guarded (`type(exu) == "table"` and `type(exu[name]) == "function"`, inside `pcall`): without EXU, or with an EXU lacking the calls, the mission is unchanged. `Bin/exu.dll` carries both names. No `SetTeamColor`, no `IFace_ConsoleCmd`. |
| Voice | `misns805` / `misns806` (and the other betrayal lines) are untouched and still fire from the body at the swap. |
| Load | A load keeps `r.cs` (start time included), so the swap still lands 3 s after the beat began and the hard cap is unchanged. Each peer re-arms its camera and duck once (`Restored.OnLoad`). It is never restarted. |

The swap builds `savfury` instead of `savs8`: the `BuildObject` shadow maps that one name (`odf == "savs8"`), so the
six faithful `BuildObject("savs8", 2, ...)` lines stay byte for byte. `savfury.odf` is stock `savs8.odf` (same stats,
`classLabel = "sav"`, weapons, sounds) with its own `baseName` and `unitName = "Infected Fury"`. As a new
CR craft with `gbolt`/`gwasp`, it is registered in `References/WeaponPresentation` the way `svsav` is (clone rows in
`inventory.json`, `recoil.csv`, `combat-models.json`, `craft-flash-offsets.json` with the same "hull hardpoint, no
flash" skip, `craft-gameplay-baselines.json`; `combat-coverage.json` and `Docs/COMBAT_WEAPON_EFFECTS.md` come from
`Tools/Build-CombatPresentation.py`). The weapons keep their stock presentation and the model has no weapon rig.

### savfury art

`Tools/Build-SavFury.py` builds it from stock `svsav` (sources and hashes under `References/SavFury`). Like `crfraz`
(`Docs/FURY_FIGHTER.md`) and the Fury mine (`Docs/BOLT_MINE_VARIANTS.md`): the VDF, skeleton and seven GEO companions
change only the part prefix `ssv11` -> `csf11`; the mesh changes only its material and skeleton links (`savfury`,
`savfury.skeleton`), so geometry, UVs, skinning, collision and animation stay stock. The textures are fresh 1024 BC1
mipped atlases (`savfury_d.dds`, `savfury_e.dds`) in the svsav UV layout, with the stock normal, specular and `ACT`
maps reused. The diffuse keeps the stock plate and vent luminance in dark Fury blue; stock lamps and red markings
become cyan. Panel seams, bevels and contour ribs come from the mesh's own edges (crease, boundary and UV-island
borders rasterised in UV space); the veins are ridged noise in an island-local frame (the island's own UV axes scaled
to its world size), never a world-space projection, and branch out of the seams. Tiny islands (pipes, muzzles) get
fewer veins and no glowing seams. `Tools/Render-SavFuryPreview.py` renders a Blender comparison against stock `svsav`
(an offline Cycles approximation, not the game's shader). Native rendering of `savfury` is unverified.

## APC retarget (CR addition, not cut content)

Stock gives the Black Dog APC (`bvapc`) `Attack(avapc1, ccarecycle)`, so it only drives at the
Recycler and never drops its soldiers on the units around it. The idea comes from a Workshop remake;
the method copies aiCore's `APCManager.UpdateAPC` (an APC `Attack` drives in and unloads), without
requiring aiCore, which the CCA ports avoid.
`Restored.TrackApc` (called from `AddObject`) records every `bvapc`. Every 5 s, `Restored.ApcRetarget`:
- drops dead APCs;
- leaves an APC alone while its command is `GET_RELOAD` or `GET_REPAIR`;
- orders `Attack` on the nearest enemy (`GetNearestEnemy`, not a building) within `APC_ATTACK_RANGE`
  (120 m, aiCore's value), unless it is already attacking that unit;
- sends an idle APC (command `NONE`) with no enemy near back at the CCA Recycler.

Team 5 only, the leader only. The list lives in `State().r.apcs`, so it survives Save/Load.
`APC_ATTACK_RANGE = 0` turns it off. Not tested in game.

## Breakthrough waves (CR addition, not cut content)

Stock goes quiet once the Black Dog base breaks (`M.plan_c`: its defences are gone and its Recycler
runs). The idea comes from a Workshop remake; the code is CR's own. `Restored.Breakthrough` records the
first frame of `plan_c` in `State().r.broke`, then:
- **Counterattack (at once):** 3 `bvhraz` and 3 `bvltnk` from `american_spawn`, each with `Attack` on the CCA Recycler.
- **Walker strike (+360 s):** 3 `bvwalk`, the same way, only while the Black Dog Recycler lives.
- **Allied Soviet waves (+60, +240, +390 s):** `svfigh`, `svtank`, `svwalk` on team 7 (the support team,
  allied with the humans), `2 + floor(humans / 2)` each, from `edge_path` (or `t3post` if that path is
  missing), with `Defend2` on the CCA Recycler, so they guard rather than steal the kill. Each wave plays a
  misn16 Soviet reinforcement line (`misn1606`/`1607`/`1608`). The script calls `UnAlly(5, 7)` both ways,
  because the runtime does not.

Black Dog units go through the scaled spawner: concealed arrivals, co-op extras on the first unit
(`BeginEvent`), and the runtime's 12-unit live cap. The first `bvhraz`/`bvwalk` the mission sees becomes
stock's `avbomb1`/`avwalker` when the AIP has not built one yet; stock only re-issues the same `Attack` on
the CCA Recycler, so that is harmless. Nothing fires after `game_over`. Every wave fires once, and the
state survives Save/Load. The leader runs it. `BLACK_DOG_COUNTERATTACK` and `SOVIET_ALLY_WAVES` (config, top
of the script) turn each half off. Not tested in game.

## Stock bugs fixed in the CR layer (the faithful body is untouched)

- The `M.user` comparisons and the reversed `Distance(key_tank, M.user)` argument order (see "Humans as one trigger"):
  without the fix Romeski never reacts to a shot, never asks for help and never turns on the shooter in co-op.
- The SAV betrayal replaces a SAV with `RemoveObject(sav)`. A SAV is any `savtnk` of any human team, so a human could be
  flying it: the CR layer never removes a ship a human is piloting (the hostile `savs8` twin is still built; the human's
  tank stays).
- The literal team-2 calls above (stock bug in co-op: team 2 is a guest slot).
- Audio: no stock-line substitution is needed; `audioSubstitute` is empty.
- The body already carries its own documented port fixes (see `MISNS8` source parity notes in `Scripts/misns8.lua`).

## Weather: Titan

`CRTitanWeather` with the generated `CRTitanSitesS8` (no pools, empty wet mask: drizzle, haze and rolls still run;
`edge_path` is not used by the Lua). Lighting is the runtime default (`Environment` auto-selects its Titan preset for
`misns8`). An `update` hook binds the sky dome to the haze ladder (`Environment.BindWeatherSensors("Titan", ...)`, as
`CRMisn15/16` do) once the weather has initialised, and again after a load. The wire ops are `TitanState`/`TitanRoll`.
Networked as in `misns1` (seeded timeline from the host, ordered stream, save/load, `AnnounceState`). A missing
module/sites table, or any failing call, disables the weather and logs once.

Beats (host/offline only, each once, saved in the runtime state): start on rung 2 (Hazy); the Factory convoy starts ->
rung 3 (Drizzle); the Recycler packs to flee -> rung 4 (Shroud) and a 70 s haze roll; the SAV betrayal (a SAV turns on
Romeski, or he screams) -> a 90 s heavy roll; victory -> back to rung 2. The director never damages.

## Map content the script never uses

Paths: `world`, `alien6`, `escape`, `mpower1`, `mtower1`, `mpower2`, `mtower2`, `rpower2`, `rtower2` (authored base
building spots the rigs no longer use), `center_path2`, `center_path3` (only the cut turret block), `edge_path` (playable
bounds, used by the weather). Objects: the extra geysers, the scrap fields, `player0_wingman` (the player's start
vehicle) and the base structures are scenery the script does not name. The shipped map has no `savtnk`, `bvtavk`,
turrets or rigs: they are produced by the humans and the AIP.

## Tests

```sh
lua5.1 Tools/Test-Misns8Coop.lua            # offline outcome and final voice line match the faithful port, 1-4 peers, team remap, player token, scaling, 460 m, SAV swap, betrayal cutscene (once, swap at +3 s, hard cap, music on every peer / without EXU, save/load, skip), beacon, weather
python Tools/Test-Misns8CoopSourceParity.py # misns8cr.lua minus CR regions == misns8.lua; every body native is shadowed
python Tools/Test-Misns8CoopContract.py     # labels/paths/teams in misns8cr.bzn, Titan sites, weather API, cutscene wiring (skips if the map is absent)
python Tools/Test-SavFuryAssets.py          # savfury: toolkit load, unchanged geometry, textures, ODF stats, shipping
lua5.1 Tools/Test-Misns8.lua && python Tools/Test-Misns8SourceParity.py   # the faithful port, unchanged
```

## Inferences and open questions

- The retaliation squad and enemy-scrap bonus are the only scaling this mission offers; the AI's own production is not
  scaled beyond the scrap bonus.
- `fallbackEntries` are the Black Dogs' forward posts; with a human at `american_spawn` the opening scavengers appear at
  an outpost instead of the base (they then path to scrap on their own).
- The replacement factory (`american_spawn`), Romeski (`romeski_spawn`, beside the Black Dog base) and the beacons can
  appear in front of a human (they are not ticketed).
- The `misns8.aip` stock plan's NSDF constructor slot is replaced by `crns8.aip` using `bvcnst`; the installed
  `misns8a` through `misns8g` plans already use Black Dog units.
- Romeski's payback `Attack` is dropped if no human has a ship at that moment (the nearest-human lookup returns nothing,
  `Scripts/misns8cr.lua` `Attack` shadow), so that payback order is lost. Known risk; no code change.
- Romeski's revenge and the SAV swap act on the nearest human/any human's tanks; whether that feels right with four
  players is untested.

## Live checklist (unrun)

1. Black Dogs build up and expand with `SetAIP(..., 5)`: rigs build towers/silos, the factory convoys out.
2. Convoy warning plays only when no human is within 100 m of the factory; the "Choke Point" convoy beacon (`M.cam3`, built at `cam_spawn`) appears. (`M.cam1`, `cam`, is the "Black Dog Base" beacon named at the start.)
3. Killing the factory mid-convoy sends 2-4 retaliation tanks at the CCA Recycler; none appear in view.
4. Plan C does NOT start at once (defence counts are for team 5); it starts when the towers fall and scrap is low.
5. Romeski arrives, any human within 150 m triggers him; shooting him from a guest makes him attack the nearest human.
6. SAVs follow him, then turn: loyal tank removed, hostile twin appears; a human piloting a SAV keeps their tank.
   The betrayal shot: Romeski's tank looking at the SAV column, the swap 3 s in, a cut to the nearest infected SAV
   (dark Fury blue, cyan veins; no engine alert for `savfury`), the camera released by about 11 s on every peer,
   the music ducked to a quarter and back (audible), the skip behaving as for other shared shots, and the voice lines
   `misns805`/`806` unmoved.
7. The Choke Point beacon drops when the fleeing Recycler passes `dis_geyser2`.
8. Titan haze/drizzle/shroud follow the beats on host and guests; no weather error in the log.
9. Victory closes with the right line (803+808 or 814) on every peer and the mission ends once.
10. When the Black Dog base breaks: the Razor/light tank counterattack arrives unseen and goes for the CCA
    Recycler; allied fighters, tanks and walkers enter from the west edge with their radio lines, guard the
    Recycler and fight the Black Dogs; the walker strike follows about 6 minutes later.
