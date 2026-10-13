# Mission 08 offline and co-op

A Nasty Surprise shares `misn08.bzn` / `misn08.lua` between the campaign
mission (`crcampgn.ini`) and the strategy listing `CR: A Nasty Surprise Coop`.
Use matching CR, EXU and OpenShim builds. Host on team 1, with guests on
distinct teams 2-4; select an NSDF tank or scout and start together.
Late join/rejoin requires a restart. Host departure ends the mission.

## Map

`Tools/Build-CoopMap.py --mission misn08` (see its entry) rebuilt `Missions/misn08.bzn` from the
Battlezone 1.5 original (class `Misn08Mission`) as for misn06/07: class
`MultSTMission`, the 16 authored CCA objects on team 5 (`perceivedTeam 5`),
four zero-motion `pspwn_1` team starts (`coop_spawn1`-`4`) 25 m apart at the
authored start, unsmoothed terrain. The Colorado (`avrecy`, label `colorado`)
sat on team 3, a guest team in co-op; it is now team 7 (the support team,
allied with every human and hostile to the CCA) perceived as NSDF (1). No object
stays on teams 2-4. The unknown ships are `svwalk` walkers: `sovgech1`/`2` on
the map plus the third walker the script spawns at `gech_spawn`.

## Mission ownership

The Utah (`avrecycle`, an `avrec8`), the navs and the objective buildings stay
on team 1 / neutral. CCA units, the walkers, the strike force and the APC use
team 5; `SetAIControl`, `SetAIP("misn08*.aip", 5)`, `SetScrap(5, 40)` and
`SetPilot(5, 40)` target it. The DLL's `SetScrap(1, 30)` becomes each human
team's starting scrap, with native capacity reserved first (as in misn05-07).
The AIPs are the stock files from `bzone.zfs` (authored for team 2).

Only the campaign leader runs AI, spawns, orders, timers and the win/loss
gates; the co-op preamble returns for guests before the mission body.
Objectives, markers, dialogue (the first line of a block plays and the rest
queue), removals and results go to every peer through the ordered, acknowledged
E/A event stream. Map-object markers travel by map label and each guest's wait
for a late replica is bounded on its own clock (the #186 pattern; the adapter
is a self-contained block so a newer version drops in). C carries camera
snapshots; misn08 has no film, so none is sent. Respawns rally at the Utah
(`avrecycle`).

## Co-op rule table

| DLL test | Co-op rule |
|---|---|
| Colorado attack waits while the player is > 400 m from `cam5` | no player within 400 m of `cam5` |
| Impatient-player acceleration (< 700 m of `cam5`) and the patrol ambush `Attack(patrol, user)` | any player; each patrol attacks its nearest player |
| Early walker discovery (< 400 m), stumbling onto the other walker (< 100 m) | any player |
| Relic (`hbcerb`) found (< 70 m) | any player; victory needs the CCA base dead as in the DLL |
| `IsInfo("hbblde"/"hbbldf")` | selection is local UI state: guests relay the two prefixes (`I`) and the leader honours a report for 1 s |
| `CountUnitsNearObject(..., team 1, ...)` for the AIP choice | summed over every human team |
| `AddObject` (no team filter) | marked filter: factory (`avmu8`) and gun towers (`abtowe`) from human teams, the APC (`svapc`) from team 5 |
| Utah (`avrecycle`) lost | the DLL fails everyone, as before; exhausting the five-life respawn service (`COOP_RESPAWN.md`) also fails everyone |
| Back-to-back `AudioMessage` (0802+0804, 0818+0826) | `Play` then `Queue` |

## Restored and changed behavior

All of it sits between `-- CR ... >>` / `<<` marker lines; the source parity test
strips them and proves the DLL body is otherwise unchanged.

* **The Colorado massacre** (`CR Colorado massacre`). The DLL cuts the radio
  scene with `Damage(colorado, 20000)`. Now walker 3 (spawned 106 m from the
  Colorado and ordered onto it) and the CCA strike units (the fighter and light
  tank the DLL spawns; the fighter's handle was lost to a retained source quirk
  and is kept) attack it. The DLL's heal (+500 hp/s) protects the Colorado until
  the scripted `kill_colorado` moment, then stops, and the attackers finish it
  on screen. The orders are refreshed every 10 s. The old `Damage` call remains
  as a fallback, run only if the Colorado is still alive 120 s after the heal
  stopped. Once it falls the strike units resume the DLL's order to the Drop
  Zone and the rest of the timeline (nav removal, 0805, the CCA recycler/AIP)
  continues from its death. 0824 (Collins: stay clear of the Colorado) plays
  once for the first player who either trips the impatient-player test (< 700 m
  before the attack) or comes within 400 m of the Colorado during it.
* **Walker 3 to the base** (`CR restored walker content`). The DLL's disabled
  block: after the CCA recycler spawns, when walker 3 passes within 30 m of
  `stop_geyser2` it is sent along `gech_path2` again and `gech3_there_time` is
  armed 97 s out, so the base-arrival block sends it at the Utah like walkers 1
  and 2. Fallback: 150 s after the recycler spawn it advances anyway.
* **0816 "pull out"**: the second disabled block. Once a walker has been found
  or has reached its trigger, any player within 75 m of walker 1, 2 or 3 plays
  it once (shared with the popper warning).
* **Relic and Colorado heal** (`CR relic heal fix`). The DLL initializes
  `next_second` / `next_second2` to the 99999 "never" sentinel, so neither
  500 hp/s heal ever ran. Both are armed at `Start` (due immediately, then each
  second): the Colorado heal runs until the scripted fall, and the Cerberus
  relic heals for the whole mission so stray fire cannot destroy the objective.
  Healing a building at full health does nothing.
* **Utah lost**: the DLL plays 0421 ("We've lost the Recycler!"); the adapter
  substitutes 0823 (Collins's abort order) for every peer. 0825 is not used.

## Focused checks

```sh
lua5.1 Tools/Test-Misn08.lua
lua5.1 Tools/Test-Misn08Coop.lua
lua5.1 Tools/Test-Misn08Presentation.lua
python Tools/Test-Misn08SourceParity.py
python Tools/Test-Misn08CoopContract.py
python Tools/Test-SetupMissionShell.py
python Tools/Validate-CampaignRepository.py
```

`Test-Misn08.lua` (79) is the offline host flow over the real CRCoop with one
player. `Test-Misn08Coop.lua` (132) runs the whole script in four peers plus an
offline peer over the E/A/C transport with a small damage model: startup and
teams, nav names reaching guests whose map handles arrive invalid, the massacre
(the Colorado dies after its heal stops, killed by an attacker, no scripted
damage), the fallback, the hold-off and 0824, walker 3 to the base, 0816 at
75 m, the heal fix, the 0823 failure, the any-player win gate in both orders,
the `IsInfo` relay, the team-filtered `AddObject` and the human-summed AIP
choice. `Test-Misn08Presentation.lua` (65) covers the adapter: cameras, label
markers with skewed guest clocks, late replicas, a vanished target, the
`IsInfo` relay and the 0421 substitution. The parity test pins
`References/Misn08Source/Misn08Mission.cpp` (the DLL source extracted from the
old Lua archive comment) and lists each co-op substitution as an API-count delta.
These mocks do not qualify native wire serialization, AI navigation, weapon
damage or voice queuing.

## Not yet verified

No live run: Windows GOG two- and four-client co-op and the campaign
progression from MISSION7. Specifically unproven: how long the real walker and strike fighter need to
kill the Colorado once its heal stops (the mock uses invented damage rates;
the 120 s fallback is the net),
that `SetAIControl(5, true)` at startup enables the CCA strategic AI the way
the DLL's `AiMission` did for team 2, the AIPs' behavior on team 5, the
walker routes against real terrain (the 30 m `stop_geyser2` pass), the heal's
real effect on the relic, and the `IsInfo` relay and label markers in a live
four-client session. `misn08.trn` still carries a `[LightningBolt]` section;
the Venus weather work owns it. Steam and Wine/Proton are unverified.
