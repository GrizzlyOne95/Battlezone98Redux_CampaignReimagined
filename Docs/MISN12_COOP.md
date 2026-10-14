# Mission 12 offline and co-op

Flying Solo shares `misn12.bzn` / `misn12.lua` between the campaign mission (`crcampgn.ini`
MISSION11, Europa, retrospective `misn1227.wav`) and the strategy listing `CR: Flying Solo Coop`. Use
matching CR, EXU and OpenShim builds. Host on team 1, guests on distinct teams 2-4; select an NSDF
tank or scout and start together. Late join/rejoin requires a restart. Host departure ends the mission.

The mission is a stealth infiltration: steal a CCA fighter, fly the patrol route (checkpoint 2, 3, 4,
the comm tower), tap the tower for 45 s from within 60 m, and get back to the Drop Zone, all inside
20 minutes. In co-op **every human infiltrates, and cover blown by anyone fails the mission for
everyone** (single player keeps the DLL's rules exactly).

## Map

`Tools/Build-CoopMap.py --mission misn12` rebuilt `Missions/misn12.bzn` from the Battlezone 1.5
original: class `MultSTMission`, the 49 authored CCA objects (buildings, 10 fighters, 4 tanks, 7
turrets, 4 howitzers, 4 scavengers, the muf, an apc) moved from team 2 to team 5, the six authored
`apcamr5-10_camerapod` nav pods moved from team 3 (a guest slot) to the support team 7 (perceived 7),
and four zero-motion `pspwn_1` team starts (`coop_spawn1`-`4`). Team 1 keeps only the player
placeholder and the Drop Zone nav `apcamr20_camerapod`. Nothing is authored on teams 2-4. The terrain
companions are Redux's own; the heightmap is the 1.5 (unsmoothed) one.

Team 7 is deliberately **not** allied with any human: a camera pod only shows what its team sees, and
the DLL hides the route pods by keeping them on a team that is not yours (stock: team 3). The Lua
flips them to team 1 (allied with every human) when a console reveals them and back to team 7 when
nobody is near. Like the other co-op missions there is no AIP and no `SetAIControl`: the CCA is
script-driven (patrols, guards, the death squad) and the CCA has no base economy.

## Ownership, per human

Only the campaign leader runs spawns, orders, timers and the win/loss gates, but it runs the DLL's
**per-player logic once per human**. The DLL keeps one player's progress in `M`; with several humans
each keeps a private copy of these fields (`HUMAN_KEYS` in the Lua) while the rest stays shared:

| Per human | Shared |
|---|---|
| starting tank and its damage/near-checkpoint gate, key-ship capture, wrong-vehicle flag | patrols and routes, guards, death squad, cameras, nav pods |
| checkpoint 2-5 progress, warnings, "identify yourself" timers, exposure flag | blown-cover state, the 20-minute timer, the uplink completion |
| the warning escort fighter | the capture tour, the win |
| uplink link state (connect / break / noise) | |

The DLL code reads and writes the same field names it always did: `M` holds the human being processed
(`M.hcur`), the others sit in `M.hstore`, and a lone player behaves byte-for-byte as before (the
offline suite, `Test-Misn12.lua`, still passes unchanged apart from the team constants).
Objective-panel calls made while a human is processed travel with a target team and only that human's
peer applies them; everything else (dialogue, cameras, the timer, the result) reaches everyone through
the ordered, acknowledged E/A stream, with the C camera snapshot and an I relay for nav-console
selection (below).

## Stealth rules for several humans

All of these are the DLL's own tests, applied to every human. Any one of them is cover blown for
everyone (`game_blown`: the DLL's 5-second death squad, 10-second failure, `misn1213` or `misn1211`):

| Test | Rule |
|---|---|
| a human's starting tank damaged below 90 percent before they have captured a ship | per human; a teammate's captured ship does not cover for a tank still in the field |
| a key ship damaged below 50 percent before anyone is in it | per ship |
| a starting tank within 75 m of checkpoint 1 before its human has captured a ship | per human |
| out of order / ignored "identify yourself" (the DLL's `real_bad`) | the exposed human's `real_bad` blows cover for all (single player: the DLL's behaviour, hunted but not failed) |
| a human leaves the key ship for another CCA fighter or tank (`out_of_ship`) | blows cover for all |

Everyone is perceived hostile (`SetPerceivedTeam(h, 1)`) when cover is blown. After the uplink is
complete the stealth phase is over: exposure no longer fails the mission (it did not in the DLL
either). A respawned human arrives in a fresh NSDF craft and must infiltrate again: their capture
flag clears and the tank gate applies to the new craft.

Sniping a key-ship pilot kills the pilot instantly (no eject), which is what the DLL's capture rules
are built around: the empty ship still stops at checkpoint 1 and can be taken.
In a network game the hijacked ship is explicitly perceived as CCA (`SetPerceivedTeam(h, 5)`) when
it is captured: the engine's disguise carries the ship's perceived team, but the owning team differs
in co-op. This is the one assumption of the stealth model that needs a live run.

## One key ship per human

The DLL's cycle (the `svfi12` leaves `spawn_geyser`, flies `first_path`, stops within 80 m of
checkpoint 1 for 20 s, returns and is rebuilt) runs per slot, with `HumanCount()` ships (cap 4) leaving
the geyser 25 s apart. A ship leaves its cycle for good once a human's craft **is** that ship, whoever
it was built for. The capture tour and its narration (three shots over checkpoints 2-4, `misn1218` to
`misn1222`) start with the first capture and are shared. The reveal of the route pods, the objective
panel and the audio are per player or shared as above.

## Checkpoints and cameras

Checkpoint progress, warnings, out-of-order recovery and the uplink are the DLL's per-player logic per
human. The acknowledgement shot (the camera framing the human who just passed, with its calm Soviet
line) is shared: one camera for everyone. While another shot or the capture tour owns the screen a
checkpoint is still granted and its line plays, but its shot is skipped, so two humans passing at
once never restart each other's film. Each player can skip their own camera; the shared timing is
unaffected. The 20-minute cockpit timer is started on every peer and stopped on every peer; only the
leader reads it for the deadline failure.

## Nav consoles

The DLL's `IsInfo("sbhqt1")` / `IsInfo("sbhqt2")` reads the local player's selected object. Guests
relay which console they have selected (I packets, honoured for one second) and the leader evaluates
it for that human's position, so any human selecting a console while near it reveals the pods for
everyone: the pods change team on the leader and replicate. The reveal ends only when **every** human
is more than 300 m away.

## Uplink and win

* The uplink is each human's own link (connect within 60 m, warn beyond 75 m, break beyond 85 m,
  45 s). The first human to hold it completes it for everyone: the panels, the timer, the cockpit
  timer and the dialogue are shared.
* Win: **every** human within 75 m of the Drop Zone nav (`apcamr20_camerapod`), latched per human
  and checked on the DLL's 120 s delay then 5 s poll; a player who leaves the session is not waited
  for.

## Scaling (marked `-- CR scaling`)

Each extra human (cap 4 players, so at most +3) adds one patrol `svfigh` on the centre loop when the
patrols start, and one hunter `svfigh` when the uplink completes (the escape begins).

## Artillery (marked `-- CR artillery`)

The four CCA howitzers (`artil1`-`artil4`, 650 m range) that the DLL never orders shell a human
**only while that human is exposed** (still in a tank, or after cover is blown or a wrong vehicle). A
disguised infiltrator is a friendly to them, so the stealth route stays quiet. Scavengers and the
other idle CCA units stay passive.

## Razor One (inferred)

`misn1224.wav` ("This is Razor One. Thanks for rescuing me. I was captured on Venus. I know a fast way
out of here. Follow me.") is never played by the DLL, and nothing in the DLL, the header, the
transcripts or the map mentions him. The map does carry a long, thin, hand-sculpted route that nothing
references. Evidence and the design below are in `Docs/MISN12_ROUTE_PREVIEW.png`
(`python Tools/Preview-Misn12Map.py`).

**Evidence (measured, from the unsmoothed heightmap).** From the checkpoint-2 compound a 20-35 m wide
channel runs east and south for about 1 km; it climbs onto a flat 66.4 m shelf (377 cells at exactly
that height), rises 14.5 m over 30 m to a launch lip at 80.9 m, drops 38 m across a 100 m
edge-to-edge gap over the main channel onto a flat 45.4 m ledge (272 cells at exactly that height),
and descends to the main floor 1.6 km from the Drop Zone. The geometry is one-way, north to south,
and ground AI cannot cross the gap. No path, object or script reaches it; `stop1`/`stop2` sit on
cliff terrain, `2spawn`/`choke_spawn`/`path_1` are single points, and `path_edge` is a map-edge
guide. `edge_path` is the play boundary. Razor One reappears free in misn14.

**What is inferred.** That this route is the arc 1224 belonged to; where he is held, what he flies,
and the trigger. The route is only "fast" from its own head (3680 m from the compound against 4232 m
the normal way); from the comm tower it is longer (6231 m against 4704 m). So it is an escape route,
not a shortcut: ground pursuers cannot follow over the gap.

**Implementation (`-- CR Razor One`, `RAZOR_ONE = true`).**

1. When the uplink completes, Razor One's `avfigh` is built on team 1 at `check2_geyser` (the
   compound), perceived as CCA, held with a nav marker named "Razor One". The stealth phase is over,
   so he cannot blow cover; nothing in the DLL's checks reads him.
2. The first human within 120 m of him hears `misn1224` (shared dialogue) and he leads.
3. He drives the 27 route points (`RAZOR_ROUTE`, measured, chord-checked against the cliff mask) by
   `Goto` with a vector, re-ordered every 8 s, and waits at the foot of the lip until a human is within
   150 m (or 45 s pass): a leader who outruns the group stops being one.
4. The jump is a scripted launch (32 m/s toward the landing with 12 m/s lift: ground AI would refuse the
   gap); the 38 m fall is unproven, so he is held at full health through it, and a teleport onto the
   ledge is the fallback if the gap is not cleared in 9 s. A progress watchdog skips a leg that does not
   shorten for 25 s. He heals 2 percent per second after 4 s unhurt.
5. He ends at the Drop Zone nav. The humans may follow him or take the normal route; the win does not
   depend on him.

`misn1224.wav` exists only in the English and Russian Redux archives, so it ships in `Assets/Audio`
byte-exact from `bzone_en.zfs` (`Tools/Test-ShippedCutVo.py`). Skipped, as decided: 1225 (silos: it
describes an earlier layout), 1226 (a duplicate of 1216), 1231/1232 (ambient). 1227 is the campaign
retrospective voice.

## Weather

`Scripts/CREuropaWeather.lua` (`Docs/EUROPA_WEATHER.md`) is a cosmetic, host-authoritative director
for Europa: cryovolcanic plumes from the geysers with straight-down ice fall, rare ice quakes, brief
Jupiter radiation surges (visual only) and a frost haze. It has no gameplay effect, touches no
perception, sensors or objectives (its own suite audits that). Every peer inits and updates it; the
leader decides. Beats: level 2 when a ship is stolen, level 3 with a plume, a brief quake and a surge
when the uplink completes, level 4 if cover is blown, calm on the win. The generated map data is
`Scripts/CREuropaSites12.lua` (`Tools/Build-EuropaSites.py`).

## Briefing

The stock briefing said the data tap works within 50 m and needs one minute. The script has always used
60 m and 45 s, so the shipped `misn12.des` (lobby and campaign text) now states them.

## Focused checks

```sh
lua5.1 Tools/Test-Misn12.lua
lua5.1 Tools/Test-Misn12Coop.lua
lua5.1 Tools/Test-Misn12Presentation.lua
lua5.1 Tools/Test-CREuropaWeather.lua
python Tools/Test-Misn12SourceParity.py
python Tools/Test-Misn12CoopContract.py
python Tools/Test-CoopAuthoredLabels.py
python Tools/Test-ShippedCutVo.py
python Tools/Test-SetupMissionShell.py
python Tools/Validate-CampaignRepository.py
python Tools/Preview-Misn12Map.py          # regenerates the route preview and prints the numbers
```

## Not yet verified

No live run (two- and four-client co-op, campaign progression). Needs a harness run:

* `SetPerceivedTeam` on a guest's hijacked ship (the explicit CCA disguise at capture) and on the
  everyone-hostile call when cover is blown; that CCA units truly ignore a disguised guest and that a
  guest can hop into an empty key ship at all.
* The cockpit timer and the shared camera shots/tour on guests, and the I relay for `sbhqt1`/`sbhqt2`
  (a guest's console selection revealing the pods for everyone).
* A snipe of the key-ship pilot (instant kill, no eject) and the empty ship's checkpoint cycle; the
  staggered second to fourth ship.
* `AddAmmo` through the owning peer (`TopUpAmmo`) for a guest's captured ship.
* Razor One end to end: his `Goto` with a vector, the scripted jump (32 m/s, 12 m/s lift; the 38 m
  fall damage; the teleport fallback), the watchdog, and whether his route and the nav marker feel
  right; the `misn1224` trigger distance.
* The Europa weather events (plumes, the ice-fall particles, quakes, surges) and the `planet = "europa"`
  campaign key.
* The artillery's `Attack` on exposed humans, the +1 patrol/hunter scaling at four players, and the
  25 s key-ship stagger against the real route length.
