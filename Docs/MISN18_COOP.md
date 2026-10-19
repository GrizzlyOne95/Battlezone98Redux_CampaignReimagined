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
| `Scripts/CRMisn18.lua` | Co-op runtime: ownership, concealed Fury arrivals, presentation transport, storm hook, extraction ending. Adapted from `CRMisn17.lua`. |
| `Scripts/CRDrop18.lua` | The extraction ending's dropship choreography (pure functions of the plan and the clock). |
| `Missions/misn18.{bzn,hg2,lgt,mat,trn,vxt}` | Map and companions, built by `Tools/Build-Misn18CoopMap.py`. |
| `Config/misn18.ini`, `misn18.des`, `Assets/Graphics/misn18.bmp`, `Config/crcampgn.ini` `[MISSION17]` | Lobby listing and campaign entry (voice `misn1800.wav`, planet `titan`: the menu has no Achilles icon). |
| `Tools/Misn18Fixture.lua`, `Misn18RealStorm.lua`, `Test-Misn18Coop.lua`, `Test-Misn18CoopContract.py` | Four-peer fixture (with the real storm loader) and contract tests. |

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
* Win: **every** human within 200 m of the Texas after the thrusters are gone. The win does not end the mission at
  once: it opens the extraction ending (below) and the mission succeeds when that has finished. Fail on expiry: **any** human past
  400 m. The 200-400 m band neither wins nor loses, exactly as the DLL.
* Other failures are unchanged and shared: transport not found in 600 s (`misn1806`, `misn18l1`), recycler lost
  (`misn18l3`), and, co-op only, all humans out of lives (`misn18l2`).
* Results are published once, after a flush of preceding narration; the first result wins. Once the win has latched
  nothing can fail the mission: `FailMission` is a no-op, the loss lines are suppressed, the arrivals are dropped and
  the Furies are removed (see the extraction ending).
* The flush waits for the guests to acknowledge the presentation events queued up to the first pass after the result
  was requested, not for later ones: a storm that keeps sending (the ascent strikes every few tenths of a second)
  must never starve the result.

## Cinematics are not skipped [owner]

The opening (`opencam3` -> `opencam1` -> `opencam2` with `misn1801`) plays on every peer. The leader streams its
shot (path, height, speed, target label) on the C channel; guests resolve targets by label. `CameraCancelled`
returns false in network games, so one player's skip cannot shorten the shared clock; the opening ends with the
narration. Arrivals are held until it ends.

**Left behind** (timer expiry with a human past 400 m): the faithful body's `CameraObject(M.player, 1, y, 1000,
M.player)` becomes a frame kind `L` that carries only the rising height. Each peer, the leader included, films
**its own ship** (`GetPlayerHandle()` on that machine); nothing about a ship is replicated. The camera ends with
the result.

## Extraction ending [owner request, CR inference]

When the win latches the mission plays two unskippable, replicated shots and only then succeeds, so the normal outro
follows. Offline it is the same ending with one player. All numbers below are CR inferences that need a live tune
(`CRDrop18.lua` marks its guesses).

| Step | What happens |
| --- | --- |
| Win | The leader stops the countdown on every peer (`StopCockpitTimer` / `HideCockpitTimer`), drops the Fury arrivals, removes every team-6 craft, and plans the fleet. The storm is told `extract`. `misn1808` still plays at the win. |
| Fleet | One NSDF dropship per human ship plus one for the Recycler and Factory (when either lives; at the win the Texas is alive by definition, so a normal win always has the base ship), at most **5**. Sites are on a ring of 150, 180 or 210 m around the Texas (the flattest wins), sterns toward it and at least 120 m apart, so they sit inside the tornado's 300 m keep-clear circle. A dead Factory is simply not loaded. |
| Replication | The plan goes out as numbers, one `ExtractShip` event per ship and then `ExtractGo`, on the ordered stream. No pose is ever sent: it is a pure function of the plan and the seconds since `ExtractGo`, which every peer starts when it applies the event, so a guest can trail the leader by the stream latency. The LEADER builds and moves the dropship objects and the Recycler and Factory it owns; EVERY peer pins its OWN ship aboard. |
| Shot 1 (0-27 s) | The camera pod stands 330 m out in a gap of the ring and films the Texas (`CameraObject(pod, 0, 4000, 0, texas)`). Each ship (staggered 1.2 s) flies in as `avdropc` (9 s), is swapped for `avdropo` (ramps swing open, 2.6 s), takes its cargo up the ramp (6 s, 60% to the lip, then into the hold), is swapped for `avdropx` (ramps fold shut, 2.4 s) and lifts at 1.5 m/s^2. |
| Shot 2 (27-39 s) | The camera follows the lead ship (`CameraObject(ship, 4000, -1000, 7000, ship)`, the offsets are guesses) as it climbs through the storm. The storm is told `ascent`: strikes every 0.2-0.5 s, hard shake, a 1.7x gale, the red swirl overhead. |
| End | The leader removes the pod, releases the camera and succeeds the mission 2 s later (the usual result flush follows). The storm settles into `won`. |

Cameras are the streamed shot kind "O" (labels resolved on guests like the opening); `CameraCancelled` is false in
network games, so nobody can skip it. The ending reuses the technique and measured numbers of `CR04Drop`
(misn04's opening), which is **not** touched: `avdropc` flies in, `avdropo` is swapped in at touchdown, `avdropx`
before lift-off, and craft are pinned with `SetTransform` because floor collision is snapshotted at creation. Humans
are assigned to ships by team order. Each peer pins only what it owns (its own ship; the leader also the Recycler and
Factory) and tops its health up every frame; the tornado's gameplay effect is off during `extract` and `ascent`.

**Save/load mid-ending** cannot resume it (the dropship handles and the cameras are gone): the leader goes straight
to success, once, and the dropships built so far stay in the world until the outro. If `CRDrop18` is absent the win
ends the mission immediately, as before.

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

`Scripts/CRStorm18.lua` (design, tunables and effects: [`MISN18_STORM.md`](MISN18_STORM.md)) is integrated.
`CRMisn18` wires it the way `CRMisn17` wires `CRJungle17`, guarded: `pcall(require, "CRStorm18")`; if
the module is absent, throws on `Create`, or lacks a method, **every call is a no-op** and the mission is
unchanged. Calls are individually `pcall`-wrapped (a failure is printed once per method) because a Lua error can
close the host.

The module returns either `Create(api)` (`api = { exu = <exu>, state = function() return M end,
players = function() ... end }`; `players` lists every live human's position for the tornado's targeting) giving a
director, or the director table itself. Every method is optional:

| Method | Called | Notes |
| --- | --- | --- |
| `Reset(saved)` | every `Start` and `Load`, all peers | `saved` is what `Save()` returned, or nil. |
| `SetPhase(name)` | **leader only** | See below. Must be idempotent: after a load the leader repeats the current phase. |
| `Update(dt, authority, send)` | every frame once the session is ready and no result has been published | `send(...)` queues an event on the ordered stream to all peers (and applies it locally). |
| `Apply(...)` | every peer, in order, with the arguments given to `send` | Keep payload strings short (<= 127 bytes each; CRWire chunks longer ones). |
| `Quake(magnitude, seconds)` | every peer, whenever the mission asks for a quake | See "Quake ownership". Returns true when taken. |
| `Describe()` | every frame after the session is ready | Stored in `M.cr18Storm` for probes and tests. |
| `Stop()` | when the result is applied | |
| `Save()` | when the engine saves | Returned value is stored in `M.cr18.storm`. |
| `Initialized`, `Enabled`, `Disabled`, `GetSeverity()` | `Environment.BindWeatherSensors("Achilles", director)` | Optional sensor coupling. |

Guests never see `SetPhase`; anything a guest must render comes from the director's own `send` events.

### Quake ownership

While the storm runs it owns the native earthquake (`StartEarthquake` / `UpdateEarthQuake` / `StopEarthquake`).
The mission's own requests, the stock `StartEarthquake(2.0)` at discovery and the restored pulse (capped at 12),
still replicate to every peer as presentation ops, but each peer's executor hands the magnitude to
`Storm.Quake(magnitude, 3.5)` instead of calling the native. The storm holds each request for its seconds with
the same rise and fall as its own pulses, and shakes the engine with the **strongest** of its own shake and every
live request, so the restored pulse (6, or up to 12) is preserved and nothing fights. A request is not renewed
once the mission stops sending it and fades out. When the module is absent, stopped (after the result), disabled or
lacks `Quake`, `Quake` is not taken and the mission calls the native itself, exactly as before.

### Tornado ownership

The funnel is replicated state (`tornado` events plus identical dead reckoning), so **every peer** applies the
effect (7 / 9 / 4 m/s^2 pull, spin and lift inside 45 m, 6 hull/s at the core) to the craft **it owns**: in a
network game that is `IsLocal` (its own player and anything it built), and the leader also owns the AI and enemy
craft. Buildings are never touched, a craft owned by another peer is left to that peer, so nothing is applied
twice and guests are pulled exactly as fairly as the host. Offline, everything is local. `Tornado.EFFECT.ENABLED`
(default on) turns it off.

Phases, emitted once each, strictly in this order (a phase whose moment passed is skipped, never replayed late;
`won` / `lost` end the sequence and skip the rest; `extract` and `ascent` are emitted by the extraction ending, not
derived from flags):

| Phase | When |
| --- | --- |
| `opening` | Leader's first update: mission start, before the body's first frame. |
| `search` | The opening cinematic has finished. |
| `found` | The transport has been discovered. |
| `core1`, `core2`, `core3` | One, two, three thrusters destroyed. Simultaneous losses emit every phase between. |
| `collapse` | All four thrusters destroyed: the transport-destroyed cinematic **begins** (the transition into full apocalypse weather). The 180 s countdown starts when it ends, about 8 s later. |
| `final` | Countdown running and at 30 s or less (never before the countdown has started). |
| `extract` | Victory latched: the dropships land and load (shot 1). Harmless to craft. |
| `ascent` | Shot 2: the dropship climbs through the storm. Harmless to craft. |
| `won` | The extraction has finished (held back until then). |
| `lost` | Any failure latched (not found, recycler destroyed, left behind, out of lives). |

`Tools/Test-Misn18Coop.lua` verifies the mission with the module absent, with a recording stand-in in both
module shapes (phase order, leader-only calls, event delivery to guests, save/load, `Stop`), with a module
that cannot be built or throws, and with the **real** `Scripts/CRStorm18.lua` on four peers
(`Tools/Misn18RealStorm.lua`: real director, CRWeather, presets and foliage wind over a stubbed EXU): a full win
and a lost path, phases in order and leader-only, guests rendering the same phase, seed, strikes and funnel from
events, the quake routed into the storm (no peer calls the natives, the pulse is preserved, one native owner),
the tornado pulling only owned craft, no storm errors, calm on `Stop`, and a mid-storm save/load. The extraction
ending is tested with 1 and 4 peers (both shots on every peer, one dropship per human plus the base ship, success only
after shot 2, nothing able to fail the mission even with the Texas dying, each peer moving only what it owns), with a
dead Factory, with a load mid-ending, and without the choreography module.

## Tests

```sh
lua5.1 Tools/Test-Misn18.lua                  # faithful port, 163 checks (CR layer off)
lua5.1 Tools/Test-Misn18Coop.lua              # four-peer co-op layer, 2988 checks
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
`CRStorm18` present, its phases (through `extract` and `ascent`) arrive in order on the leader and its events render on every client; the
stock discovery quake and the restored pulses shake through the storm with no stutter, and a guest's ship is
pulled by the tornado.


## Live results 2026-10-19

First live runs, OpenShim co-op harness (`Tools/Run-Misn18Live.ps1`, scenarios `Tools/Test-Misn18Live.ps1`), GOG
build, DX11, windowed, no audio endpoint, no focus or input. One-peer runs are a one-client network game (the harness
lobby needs a patched copy for one peer; true offline play cannot be started without a menu click, so the offline
code path is **not** covered). Evidence: `C:\BZRCoop\misn18-20261019\` and `C:\BZRCoop\runs\<run>\`.

| Case | Peers | Run | Result |
| --- | --- | --- | --- |
| storm ladder + win + extraction | 1 | `misn18-storm-1p-b20261019-103659` | PASS: opening, search, found, core1-3, collapse, final, extract, ascent, success; no Lua or Ogre errors |
| win (fast) | 1 | `misn18-win-1p-a20261019-103103` | PASS (the countdown check in that run read the engine clock, see below) |
| loss (countdown expiry) | 1 | `misn18-loss-1p-a20261019-104943` | PASS: left-behind shot, `FailMission`, result parity |
| smoke | 1 | `misn18-smoke-1p-c20261019-101828` | PASS to the point the run lost its coordinator (audio watchdog, see below) |
| wakes | 1 | `misn18-wakes-1p-a`/`b` | modules PASS (systems created over water and mud, zero CRWake errors); captures did not frame the craft: visual BLOCKED |
| storm ladder + win + extraction | 2 | `misn18-storm-2p-d20261019-105510` | PASS: every step on both clients, 30/30 matching presentation ops, `SucceedMission` on both |

### Bug found and fixed: the countdown never counted

`MultSTMission` calls `StartCockpitTimerUp` every frame (see `BZR_LUA_AGENT_REFERENCE.md`, "Multiplayer cockpit timer
override"). Live, `GetCockpitTimer()` returned the mission clock (59 at t = 59.9 s, 66 at 66.1 s) whatever
`StartCockpitTimer(180, 120, 30)` asked for. So the countdown loss (`GetCockpitTimer() <= 0`) and the storm's `final`
phase could never fire: a run held 295 s of mission time past the start of a 180 s countdown with no loss. The host
fixture used a counting-down native timer and hid this. Fixed in `CRMisn18`: the leader stores `timerEnd` in saved
state when the countdown starts and `GetCockpitTimer` (and the `final` phase) read that script clock. The fixture's
native timer now mimics the engine (mission clock); `Test-Misn18Coop.lua` failed on it before the fix. **Open:** the
displayed cockpit timer is still the engine's count-up in network games; the on-screen countdown the owner asked for
needs a script-drawn display (design decision). Other missions that read `GetCockpitTimer` in `MultSTMission` (misn12)
should be checked for the same defect.

### What the captures show (DX11, 584x720 window)

* Storm sky: a red swirl deck with dark streaks, drifting leaf and dust sprites, ground fog, cracks and a dark tornado
  funnel. It brightens from orange (found) to saturated red (core3, final). `CR18/StormSwirl` is skipped by the DX11
  legacy-material guard (`[DX11COMPAT] ... unsupported custom programs ... action=skip`) yet draws, so the skip applies to
  a sibling technique; no `CR18_Swirl_v2` compile error (only the expected `Invalid target ... vs_3_0` for the SM3
  delegates).
* A pale grey-green band remains between the red deck and the hills in low-camera shots (extraction landing and ascent,
  wake mud shot) even with `agent/misn18-sky` merged; in the high sky shots the deck reaches the hills. The horizon fix
  is not complete for low views.
* `transdestroyedcam`: the transport tower and the explosion, 8 s, same instants on both clients.
* Extraction: NSDF dropships ("12", star roundels) land and lift in both clients; at landing distance they are dark
  silhouettes. Both clients show the same framing.
* A flat olive polygon at the top edge of one `final-tornado` frame (sky-plane edge or ground tile) is unexplained.

### Guests and co-op (2 peers)

Guest saw the opening, the transdestroyedcam shot (`CameraReady/CameraPath/CameraFinish` within 0.1 s of the leader),
the countdown start, the extraction shots and the result, in the same order. Sampled at t = 17 s and during the ascent
the dropship fleet and the base cargo are within tolerance on both clients; the t = 9 s sample (ships still flying in)
differed by up to 156 m, which is the stream latency on moving craft, not a different place.

### Harness findings

* Without an audio endpoint the opening voice-over reports done at once, so a guest may never get an opening
  `CameraPath`; the scenario treats that as a warning.
* The OpenShim coordinator aborts a run (`Client N lost its audio session`) when an audio endpoint appears mid-run with no
  muted session; the runner no longer passes `-MuteClients` by default.
* One client start-up crash in the menu music (`libvorbisfile`, "Starting Music Playback") in 1 of 11 launches; not
  reproducible, not mission related (the listing has no music key; same as misn17).
* One-time Ogre exceptions at mission start: `Cannot find required template 'CR18/Dust|Streak|Haze|Ash|Cinder|Debris'`
  (templates requested before the payload registers; the director reports `templates = true` and 6 live systems
  afterwards). Worth a look: probably a first-frame retry.
* Not run: DX9 smoke, misn17 jungle and Moon/Mars wake captures, 4-peer, 2-peer loss.
