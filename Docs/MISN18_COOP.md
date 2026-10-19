# Mission 18 co-op: The Ultimate Quake

Shared offline / 2-4 player co-op port of Battlezone 98 Redux mission 18 (Stars and Stripes, "The Ultimate
Quake"). One `Missions/misn18.bzn` and one `Scripts/misn18.lua` serve both modes. Companion to
[`MISN18_SOURCE_PORT.md`](MISN18_SOURCE_PORT.md) (the faithful DLL port underneath) and
[`FURY_FIGHTER.md`](FURY_FIGHTER.md). Status: **host-tested only**; nothing here has run in the game
(see "Live checklist").

## Layout

| File | Role |
| --- | --- |
| `Scripts/misn18.lua` | The faithful port plus marked `-- CR ... >>` / `<<` regions. Outside them it is exactly the DLL source (`Tools/Test-Misn18SourceParity.py`). |
| `Scripts/CRMisn18.lua` | Co-op runtime: ownership, concealed Fury arrivals, presentation transport, storm hook. Adapted from `CRMisn17.lua`. |
| `Missions/misn18.{bzn,hg2,lgt,mat,trn,vxt}` | Map and companions, built by `Tools/Build-Misn18CoopMap.py`. |
| `Config/misn18.ini`, `misn18.des`, `Assets/Graphics/misn18.bmp`, `Config/crcampgn.ini` `[MISSION17]` | Lobby listing and campaign entry (voice `misn1800.wav`, planet `titan`: the menu has no Achilles icon). |
| `Tools/Misn18Fixture.lua`, `Test-Misn18Coop.lua`, `Test-Misn18CoopContract.py` | Four-peer fixture and contract tests. |

The map is the 1.5 original (22 objects, 46 named paths), converted to Redux 2016 text, class `MultSTMission`,
four `pspwn_1` start buoys (teams 1-4, 25 m apart). Heightmap: the unsmoothed 1.5 `.hg2` from commit `ce18e89`;
`.trn/.mat/.lgt` from Redux `bzone.zfs`. The seven scrapfields that all carried the stock label
`sfield0_scrapfield` are now `cr18_scrap1..7` (label-based co-op resolution needs unique labels). The map is
not a mid-play snapshot: no velocities, orders or runtime paths needed stripping.

## Teams and ownership

| Team | Use |
| --- | --- |
| 1-4 | Humans. The authored Texas (`avrecy2_recycler`), factory and two `avtank` wingmen stay on team 1 and are shared and host-run. Extra starting recyclers are disabled (`exu.DisableStartingRecycler`). |
| 6 | Furies: the transport `hbtran0038_i76building`, thrusters `hbtrn20049-52_i76building` (authored team 2, moved by the builder) and every script-built `hvsat` / `hvsav` / `crfraz`. |
| 7 | Allied support (alliances configured; nothing is placed on it). |

Only the campaign leader runs the body: spawns, orders, `AddHealth`/`Damage`, `SetScrap`, the countdown and the
result. Guests receive presentation only (objectives and markers, audio and subtitles, cameras, the quake, the
cockpit timer, the storm events) through the ordered E/A + C stream adapted from mission 17. `SetAIControl(6, true)`
runs once at chunk load; no AIP is used.

### Humans as one trigger

The body asks `Distance(M.player, ...)`. In the CR layer `GetPlayerHandle()` returns a token and the wrapped
`Distance` turns it into "the humans" with `CRCoop.ForEachPlayerHandle`:

* approach, shortcut, `transfound`, `dontgo*`, `return*` triggers: **nearest** human (AnyPlayerSatisfies);
* the recycler gates (`> 400` timer failure, `< 200` win): **farthest** human (AllPlayersNear). A human with no
  live ship counts as far (and the check waits for the session to be ready). No live human is infinitely far.

Discovery (transport found), thruster kills and `GetNearestEnemy(transport)` stay shared: any player counts.

## Fury scaling and concealed arrivals [owner]

* Every scripted spawn event opens with `BeginEvent()` (15 marked sites: three route waves in both their
  proximity and discovery forms, three timed raids, three don't-go ambushes, the first and the replacement
  recycler assault, the return wave). The first Fury the event builds is mirrored by `floor(humans / 2)` extras
  of the same kind, route, orders and entry: 1 human 0, 2-3 humans 1, 4 humans 2.
* All Furies are team 6 and go through a saved arrivals queue (`M.cr18`). Entry is the authored path if no human
  is within 460 m, else another authored approach (`spawnrand`, `spawnrand2`, `spawn1b`, `spawn2b`, `spawn3b`,
  `spawnalt2b`, `spawnalt3b`), else the request waits. Requests survive save/load without duplicating, and are
  held for the whole opening cinematic. Orders issued to a pending request (`Goto`, `SetIndependence`,
  `Attack`) are recorded and replayed on the real unit; `IsAlive` is true for a pending request, so the
  recycler assault is not re-spawned while one is waiting.
* Cap: at most **12** live scripted Furies. Only the co-op extras are dropped at the cap; the faithful primary
  Furies are never refused. `CRFuryRoster.Select` runs at queue time for primaries and extras, so two thirds of
  all Furies are the restored `crfraz` fighters with the saved counter (`M.crFuryIndex`).
* Starting scrap is shared: `SetScrap(1, 80 + 10 per extra human)`.

## Timer, win and loss [owner]

* One leader-owned 180 s countdown (`StartCockpitTimer(180, 120, 30)`) is presented on every peer's cockpit
  timer; only the leader reads it. It starts when the transport-destroyed shot ends (below), not at the fourth
  thruster; until then the gates see a full clock, so an idle timer never reads as an expired one. The body's
  hurry lines (`misn1809-1812`, +60/85/115/140 s) still count from the fourth thruster, so they arrive about
  8 s earlier relative to the clock. Peer displays may trail the leader by network latency.
* Win: **every** human within 200 m of the Texas after the thrusters are gone. Fail on expiry: **any** human past
  400 m. The 200-400 m band neither wins nor loses, exactly as the DLL.
* Other failures are unchanged and shared: transport not found in 600 s (`misn1806`, `misn18l1`), recycler lost
  (`misn18l3`), and, co-op only, all humans out of lives (`misn18l2`).
* Results are published once, after a flush of preceding narration; the first result wins.

## Cinematics are not skipped [owner]

The opening (`opencam3` -> `opencam1` -> `opencam2` with `misn1801`) plays on every peer. The leader streams its
shot (path, height, speed, target label) on the C channel; guests resolve targets by label. `CameraCancelled`
returns false in network games, so one player's skip cannot shorten the shared clock; the opening ends with the
narration. Arrivals are held until it ends.

**Left behind** (timer expiry with a human past 400 m): the faithful body's `CameraObject(M.player, 1, y, 1000,
M.player)` becomes a frame kind `L` that carries only the rising height. Each peer, the leader included, films
**its own ship** (`GetPlayerHandle()` on that machine); nothing about a ship is replicated. The camera ends with
the result.

## Restored and changed content

All restorations are inside CR-marked regions, so the parity test still proves the DLL port outside them. The
host suite's faithful run (`CR_TEST_FAITHFUL`) leaves all of them off.

| Restoration | Evidence | Behaviour |
| --- | --- | --- |
| `misn1817.wav` | Transcript row (`Tools/TranscriptSources/GoombaBZ/campaigns.csv`): "the Furies are trying to take out the Texas. Protect that Recycler"; `Docs/ORIGINAL_GUIDE_LORE_AND_CUT_CONTENT_20261016.md` lists it with no call site; the file ships in every Redux language archive (`bzone_en/de/es/fr/it/pt/ru.zfs`) and `Text/misn1817.txt` exists. | Plays once when the **first** recycler assault spawns (`savwaves` latch), not on replacements. |
| `misn1818.wav` for the Texas loss | Transcript row "the Texas has been destroyed"; the DLL really plays `misn1704.wav` (`Misn18Mission.cpp:791`, the misn17 line). | The faithful body keeps the `misn1704` line; the runtime's audio wrapper substitutes `misn1818.wav`. |
| Earthquake pulse | Disabled block at `Misn18Mission.cpp:326-336` with its comment "After four seconds the quake gets bigger for two seconds". `quake_level` is 2 from the start and 6 at the collapse, `quake_check` is already armed. | Every third second `UpdateEarthQuake(level * 0.9)`, with `level * 3` on every fourth pulse, on every peer. The spike is **bounded at 12**: 6 x 3 = 18 has never been run in the game. The cap is a CR safety choice, not source. |
| Return wave `sav2` / `sav3` | Commented lines `Misn18Mission.cpp:812-813` (`hvsat` and `hvsav` at `spawnreturn`); both handles are real state fields. | Built with `sav1`, no orders, like `sav1`. |

### Transport-destroyed shot (`transdestroyedcam`)

Inference, not source: the path name, its position around the transport and the immediate `Damage` of the
transport identify an explosion shot that was cut. CR plays it when the fourth thruster dies:

* The body's `StartCockpitTimer(180, 120, 30)` call becomes the trigger. `CameraReady`, then every update
  `CameraPath("transdestroyedcam", 1500, 600, transport)` (the opening's idiom: the transport as the look-at
  target). Height and speed are guesses; the live run must tune them.
* The body's `Damage(transport)` is deferred: the transport stands for 4 s of the 8 s shot, is blown up on
  camera, and the shot finishes on the path with no target (the camera wrapper drops a dead target).
* Replicated like the opening (leader streams the shot; guests resolve the target by label). Not skippable in
  network games (`CameraCancelled` is false); offline the native skip releases only the local camera, the
  8 s clock is unchanged.
* `collapse` is emitted at the start. Arrivals are held for the whole shot, like the opening. Craft are not
  frozen (the opening does not freeze them either).
* At the end the camera is released and the countdown starts on every peer, leader-owned.
* **Save/load mid-shot** cannot resume the cameras: the load blows the transport up and starts the countdown
  immediately (once). The start is persisted (`M.cr18.timerStarted`), the pending shot in `M.cr18.cin`.

### `misn1803.wav` stays out

"Good job, Grizzly One. Now get back to the transport." (2.2 s, speaker blank in the transcript) is not
referenced anywhere in the DLL. It is an alternate take of the active `misn1804` ("Good job, Grizzly One. Now get
back to the Texas. You have three minutes.") for the same moment, wrongly calling the Texas "the transport" after
the player has just destroyed the Fury one; playing both would be redundant and misleading, and it is absent
from every Redux language archive except English and Russian. The objective file `misn1803.otf` ("Return To Your
Recycler For Immediate Evacuation") is a different, active asset. `Tools/Test-Misn18CoopContract.py` asserts the
wav is not referenced.

## Map content the script never uses

Compared against the stock 1.5 BZN (22 objects, 46 paths):

| Item | Finding | Decision |
| --- | --- | --- |
| path `spawn1` | **Referenced by the DLL (three `hvsav` in the don't-go ambushes) but absent from the 1.5 map.** What the stock engine did with a missing path is unknown. | CR maps `spawn1` to `spawn1b` (the same west approach as the first wave) in the runtime. Inference, not source. |
| path `blastoffcam` | One point beside the Texas. The DLL films the blast-off with `CameraObject` on the player instead. | Not used. |
| path `transdestroyedcam` | Four points (about 40 m) circling the transport. No call, comment or audio refers to it; the DLL kills the transport with `Damage` the tick after the last thruster, which is the moment such a shot would film. | **Restored** (owner request) as the transport-destroyed shot, see below. Intent is inferred from the name and geometry, not source. |
| path `edge_path` | Two points across the map. No consumer. | Not used. |
| state `w4u*`, `w5u*`, `w6u*`, `wave4-6start`, `dg1c/d`, `dg2c/d`, `dg3c/d` | Declared and zeroed, never assigned or read in the C++. The map has no matching paths (`spawn4*`, `dgs*c`...). | No intent to recover; left as inert saved state. |
| objects `avmuf2_factory`, `avtank0_wingman`, `avtank1_wingman`, `eggeizr11_geyser`, `eggeizr12_geyser`, `myCar_hover` | Base furniture and the stock player; the script never fetches them. | Kept as authored (team 1 / neutral). The factory is the Texas's production path. |
| `cr18_scrap1..7` | Stock scrapfields. | Relabelled only. |

## Starting ships

Tank, Scout, Light Tank, Rocket Tank, Bomber (`avtank`, `avfimp`, `avltnk`, `avrckt`, `avhraz`; all exist in
`ODF/`). Owner-specified; see `COOP_STARTING_UNITS.md`.

## Storm interface

`Scripts/CRStorm18.lua` is built separately (branch `agent/misn18-storm`) and this branch deliberately does not
contain it. `CRMisn18` wires it the way `CRMisn17` wires `CRJungle17`, guarded: `pcall(require, "CRStorm18")`; if
the module is absent, throws on `Create`, or lacks a method, **every call is a no-op** and the mission is
unchanged. Calls are individually `pcall`-wrapped (a failure is printed once per method) because a Lua error can
close the host.

The module returns either `Create(api)` (`api = { exu = <exu>, state = function() return M end }`) giving a
director, or the director table itself. Every method is optional:

| Method | Called | Notes |
| --- | --- | --- |
| `Reset(saved)` | every `Start` and `Load`, all peers | `saved` is what `Save()` returned, or nil. |
| `SetPhase(name)` | **leader only** | See below. Must be idempotent: after a load the leader repeats the current phase. |
| `Update(dt, authority, send)` | every frame once the session is ready and no result has been published | `send(...)` queues an event on the ordered stream to all peers (and applies it locally). |
| `Apply(...)` | every peer, in order, with the arguments given to `send` | Keep payload strings short (<= 127 bytes each; CRWire chunks longer ones). |
| `Stop()` | when the result is applied | |
| `Save()` | when the engine saves | Returned value is stored in `M.cr18.storm`. |
| `Initialized`, `Enabled`, `Disabled`, `GetSeverity()` | `Environment.BindWeatherSensors("Achilles", director)` | Optional sensor coupling. |

Guests never see `SetPhase`; anything a guest must render comes from the director's own `send` events.

Phases, emitted once each, strictly in this order (a phase whose moment passed is skipped, never replayed late;
`won` / `lost` end the sequence and skip the rest):

| Phase | When |
| --- | --- |
| `opening` | Leader's first update: mission start, before the body's first frame. |
| `search` | The opening cinematic has finished. |
| `found` | The transport has been discovered. |
| `core1`, `core2`, `core3` | One, two, three thrusters destroyed. Simultaneous losses emit every phase between. |
| `collapse` | All four thrusters destroyed: the transport-destroyed cinematic **begins** (the transition into full apocalypse weather). The 180 s countdown starts when it ends, about 8 s later. |
| `final` | Countdown running and at 30 s or less (never before the countdown has started). |
| `won` | Victory latched. |
| `lost` | Any failure latched (not found, recycler destroyed, left behind, out of lives). |

`Tools/Test-Misn18Coop.lua` verifies the mission with the module absent, with a recording stand-in in both
module shapes (phase order, leader-only calls, event delivery to guests, save/load, `Stop`), and with a module
that cannot be built or throws.

## Tests

```sh
lua5.1 Tools/Test-Misn18.lua                  # faithful port, 163 checks (CR layer off)
lua5.1 Tools/Test-Misn18Coop.lua              # four-peer co-op layer, 777 checks
python Tools/Test-Misn18SourceParity.py       # strips CR regions, proves the DLL port underneath
python Tools/Test-Misn18CoopContract.py       # map, teams, paths, listing, campaign entry, shipping
lua5.1 Tools/Test-FuryRoster.lua              # shared roster
```

`Test-FuryRoster.lua` no longer loads `misn18.lua` through a stub (the production spawner is `CRMisn18.Spawn`);
`Test-Misn18Coop.lua` asserts the same cadence (8 fighters + 4 heavies per 12) and the saved counter through
four real peers. The suite was mutation-checked: raising the cap, dropping the `misn1818` substitution, using the
nearest instead of the farthest human, removing the `spawn1` mapping and replicating the leader's shot each fail it.

## Inferences and open questions

* `spawn1` -> `spawn1b`, the quake spike bound (12), the 460 m entry radius and the 12-Fury cap are CR choices.
* "Per spawn event" scaling mirrors the event's first Fury; a mixed event (don't-go: `hvsat` + `hvsav`) gets
  extras of its first unit's kind.
* Out-of-lives failure reuses `misn18l2`; there is no dedicated text.
* A human waiting to respawn has no ship: they count as far from the Texas, and the leader's body pauses while
  `CRCoop.IsSessionReady()` is false. Whether that pause interacts with the 180 s countdown (it is wall-clock)
  is untested.
* `transdestroyedcam` is a restored inference (see above); a vanished transport target ends the shot's look-at
  with a target-less `CameraPath`, which no live run has exercised.

## Live checklist (unrun)

Two and four clients, windowed, via the OpenShim harness. Check that: the opening plays on every client and
holds the arrivals; a guest crossing `spawn1a` releases wave one with no Fury visible within 460 m; the
the transport-destroyed shot plays on every client, the transport blows up on camera and the camera framing
is acceptable (height 1500, speed 600 are guesses); the countdown then shows on every cockpit and matches within
a second; a guest 450 m away at 0:00 gets the left-behind
shot of its own ship and the failure text; all four within 200 m win once; `misn1817` plays once with the first
assault and `misn1818` replaces `misn1704`; the quake pulses are tolerable at level 6; the don't-go hvsav
appears at `spawn1b`; the 12-Fury cap holds in a long four-player run; `M.coopUnresolved` stays 0; and, with
`CRStorm18` present, its phases arrive in order on the leader and its events render on every client.
