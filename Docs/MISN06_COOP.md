# Mission 06 offline and co-op

**Sensor policy update (15 October 2026):** The later owner decision enables weather and night sensor effects on mission 06, matching the other Mars missions. Wind push remains disabled. This supersedes the earlier visual-only atmosphere note below. See
`WEATHER_SENSOR_POLICY.md` for the current campaign policy.


Escape from Mars shares `misn06.bzn` / `misn06.lua` between campaign
`MISSION5` and the strategy listing `CR: Escape from Mars Coop`.
Use matching CR, EXU and OpenShim builds. Host on team 1, with guests on
distinct teams 2–4; select an NSDF tank or scout and start together.
Late join/rejoin requires a restart. Host departure ends the mission.

## Map

`Tools/Build-Misn06CoopMap.py` rebuilds `Missions/misn06.bzn` from the
Battlezone 1.5 original (`stockfiles2\misn06.bzn`, binary version 1032,
class `Misn06Mission`). It re-saves the map as Redux ASCII 2016 through the
Battlezone98_Modding_Toolbox converter (`BZ_MODDING_TOOLBOX` overrides the
sibling-repo default), then:

- names the terrain stem (`TerrainName = misn06`; the converter keeps `.bzn`);
- sets the mission class to `MultSTMission`, so one BZN hosts solo and co-op;
- moves the 26 authored CCA objects from team 2 to team 5 (`perceivedTeam 5`);
- adds four `pspwn_1` team starts (`coop_spawn1`–`4`) 25 m apart along the
  player's left from the authored start, with zero motion.

The converter drops only the 1.5 collision-damage fields that Redux 2016 has
no slot for. Every label and path the Lua reads is retained.

Terrain is the unsmoothed 1.5 cook (`misn06.hg2`, generated with the other 35
legacy maps in `ce18e89`). The `.trn`, `.mat` and `.lgt` companions are
Redux's own stock files from `bzone.zfs`; Workshop requires them beside the
listing, and same-named mod files override stock.

## Mission ownership

Wyoming (`avrecy-1_recycler`) and the 5th Platoon remain on team 1. CCA
units use team 5, and the 5th Platoon cinematic units (team 3 in the DLL) use
team 7, allied with every human team. EXU suppresses the extra MultST starting
recyclers. The DLL's `SetScrap(1, 5)` becomes each human team's starting scrap,
with native capacity reserved first, as in misn05.

Only the campaign leader runs AI, spawns, orders, timers and the win/loss
gates. The script keeps the DLL's Execute order; the co-op preamble returns
for guests before the mission body. Objectives, markers, dialogue (the first
line of a block plays and the rest queue, keeping every subtitle), the
540/362/180 cockpit timer, removals and results go to every peer through the
ordered, acknowledged E/A event stream. The C camera snapshot now carries a
kind: `P` replays the opening and Hephaestus path cameras and `O` the object
shots. Each player can skip their own film; the shared timing continues.

Player-handle tests in the DLL become:

| DLL test | Co-op rule |
|---|---|
| Hephaestus discovery/recon, blockade, starport, CCA recycler reminder | any player in range |
| Launch pad abandonment (> 400 m) | no player within 400 m |
| 5th Platoon film gate (no enemy within 400 m) | no player has an enemy within 400 m |
| Escort fighters attack the player | each attacks its nearest player |
| Dust off | Wyoming **and every player** within 100 m |

A player who is dead blocks dust off until they respawn. Rallies use
Wyoming, which escorts the players throughout. Human deaths use the five-life
service (`COOP_RESPAWN.md`); exhausting it fails the mission.

The info scans (`obheph`, `obstp1`, `obstp8`, `obstp3`, `sblpad`) are local
UI state. Guests send their current selection to the leader as `I` messages
(at most every 0.25 s), and the leader honors a report for one second.

Offline play keeps the DLL behavior: every helper iterates only the local
player, and results stay a pass-through.

## Restored cut dialogue

Twenty unused original voice lines return between `-- CR restored VO` markers
(`RESTORED_VO` gates them; the source parity test strips the regions and
checks the DLL body is otherwise unchanged):

- The orbital blockade arc after the escorts fall: transport touchdown and the
  Lincoln/Roosevelt blockade order (0623, 0615, 0652); at transport launch the
  "eight minutes" exchange and the order to take the base (0614, 0616-0620),
  after which the cockpit timer and Launch Pad objective start; at +60 s the
  transport rejoins the destroyers (0624 or 0641) and the Freedom is called
  (0621, 0622); at +90 s the Lincoln's mayday (0625, 0626); then the Lincoln
  is lost (0627) and, if the pad is not yet reconned, the shipped 0628 order.
- 0610 after the Hephaestus scan (new orders wait for it), 0609 once the scrap
  field ambush is clear, 0693 as the first starport reminder.
- Late escape (5th Platoon lost): 0637 replaces 0629/0630 and 0639 is the win line.

Deadlines and failure conditions are unchanged. The campaign briefing voice
is the 0600 retrospective.

## Focused checks

```sh
lua5.1 Tools/Test-Misn06.lua
lua5.1 Tools/Test-Misn06Presentation.lua
python Tools/Test-Misn06SourceParity.py
python Tools/Test-Misn06CoopContract.py
python Tools/Test-SetupMissionShell.py
python Tools/Validate-CampaignRepository.py
```

The host flow suite passes 1012 checks and the four-peer presentation adapter
54 (path/object cameras, cockpit timer, IsInfo relay and expiry, delayed
replicas, local skips, result held for acknowledgements). The source parity
test lists each co-op substitution as an explicit API-count delta. These mocks
do not qualify native wire serialization, AI navigation or voice queuing.

## Not yet verified

No live run yet: Windows GOG two- and four-client co-op, solo campaign
progression from MISSION4, buoy spawn heights on the 1.5 terrain, the film
skips, all six failures, and early/late extraction. Steam and Wine/Proton are
unverified, and stock multiplayer kill-feed messages remain visible.

## Story weather and lighting (2026-10-15)

Environment and CRMarsWeather Plains now run on every peer. The host sets
weather targets from the story: reconnaissance 1, Hephaestus scan 2, starport
recon 3, blockade/timed launch-pad assault 4, extraction 2. Existing mission
logic, objectives and timers are unchanged. Weather target and actual rung use
the ordered presentation stream; guests do not run an independent automatic
ladder. Save/load persists weather scalars and rebuilds particles.

This new weather is visual-only: wind push, weather sensor degradation and
Environment night gameplay are disabled. The visual day/night cycle remains.
The composed fog is capped to the TRN visibility distance. Native clouds and
sky stay as authored; no additional sky/cloud deck is created. Tests cover
story progression, save/load and the real four-peer weather transport adapter;
native rendering/networking remains unverified. See `ATMOSPHERE_AUDIT_20261015.md`.
