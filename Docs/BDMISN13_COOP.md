# Black Dog 13 co-op: Frustrate Their Knavish Tricks (bdmisn13)

Shared offline / 2-4 player co-op port of the Black Dog mission `bd13` (the Chinese are collecting scrap to build a new
Pegasus portal; the Black Dogs must recycle all six Chinese scrap silos with a construction rig inside 45 minutes without
destroying one or touching the Chinese base, then destroy the Chinese recycler). One `Missions/bd13cr.bzn` and one
`Scripts/bd13cr.lua` serve both modes. Companion to the faithful DLL port underneath (`Scripts/bdmisn13.lua`, tested by
`Tools/CoopCampaignTests/test_bdmisn13.py`) and [`CCA_COOP_RUNTIME.md`](CCA_COOP_RUNTIME.md) (the shared runtime). Pattern:
[`MISNS2_COOP.md`](MISNS2_COOP.md), [`BDMISN05_COOP.md`](BDMISN05_COOP.md) and [`BDMISN08_COOP.md`](BDMISN08_COOP.md).
Status: **host-tested only**; nothing here has run in the game (see "Live checklist").

## Layout

| File | Role |
| --- | --- |
| `Scripts/bd13cr.lua` | The faithful port plus marked `-- CR ... >>` / `<<` regions. Outside them it is exactly `bdmisn13.lua` (`Tools/CoopCampaignTests/Test-Bdmisn13CoopSourceParity.py`). Holds the runtime CONFIG, the native shadows and the restoration. |
| `Scripts/CRGanymedeSitesBD13.lua`, `Scripts/CREuropaWeather.lua` | Ganymede weather (the Europa director with the generated sites for this map: fifteen cryovolcanic vents, the geysers of the Black Dog base, the Chinese base and the scrap fields). |
| `Missions/bd13cr.{bzn,vxt}`, `bdmisn13.{hg2,lgt,mat,trn}`, `Config/bd13cr.ini` | Map, vehicle list and multiplayer listing (not part of this change). The map has the whole Chinese base on team 5 (recycler, six silos, towers, turrets, walkers, scavengers, mines) and the Black Dog base on team 1 (recycler, construction rig, silos, wingmen). |
| `Tools/CoopCampaignTests/Bdmisn13Fixture.lua`, `Test-Bdmisn13Coop.lua`, `Test-Bdmisn13Presentation.lua`, `Test-Bdmisn13CoopSourceParity.py`, `Test-Bdmisn13CoopContract.py` | Multi-peer fixture and tests (real map coordinates). `Tools/CoopCampaignTests/test_bdmisn13.py` still covers the faithful port, unchanged. |

## Teams and ownership

| Team | Use |
| --- | --- |
| 1-4 | Humans (host on 1). The authored Black Dog side (the base, the Recycler, the construction rig, the wingmen, both turret tanks, the scavengers, the nav beacons) stays on team 1: shared, host-run. Extra starting recyclers are disabled. |
| 5 | The Chinese: the base, the silos, the six guard groups and the four attack waves. The body still says team 2; the runtime maps `BuildObject(..., 2, ...)` to team 5. The map's Chinese base is authored on team 5 already. |
| 7 | Support (nothing uses it here). |

Only the authority (host, or the offline player) runs the body; guests only present. `SetAIControl(5, true)` runs once at
chunk load. The mission has no `SetAIP`: the enemy is entirely scripted (its base is static). `SetScrap(1, 30)` becomes the
shared pool plus 10 per guest (`scrapPerGuest`); `SetPilot(1, 10)` is given to every human team. Respawns rally on the
Recycler.

There are no portals and no teleports in this mission, so nothing has to carry every human through anything.

### Humans as the player

The DLL's "player" is `GetPlayerHandle()`, one tank. In co-op the CR layer answers it with the runtime's nearest-human
token (`crcca_players`), so `M.user` is the token. The body uses it in exactly one place: `GetDistance(user, silos[i]) ~= 0`,
the trigger of the six guard groups. `IsValid` accepts the token and `GetDistance` is wrapped (`WrapDistance`): the distance
is the nearest human's (infinite when no human has a ship). The intro shot looks at silo 6, a map object, and needs no
substitute. No order is aimed at the player, so there is nothing to retarget.

### "Recycled by the player" is any human team

The recycle query is `IsRecycledByTeam(silo, 1)`, the construction rig's team. In co-op a guest's rig is on team 2-4, so
without the fix only the host's rig could ever seize a silo and the guest's recycle would be a "destroyed silo" loss. The CR
shadow asks every human team (offline: team 1 only, exactly the DLL).

## Scaling and concealed arrivals [owner rules, mission decisions]

Scaled spawns: every Chinese craft the body builds, the 24 guards and the 28 wave units (`cvfigh`, `cvltnk`, `cvtnk`,
`cvrckt`, `cvhraz`, `cvhtnk`). They are concealed tickets (`R.Spawn`): built from their authored path when no human is within
460 m of it, otherwise from the next hidden approach, and mirrored for head count.

- One scaling event is one wave (all of a wave's units are built in one frame from `spawn_attack_waves`) and one guard group.
  The guards are built in one frame as six groups of four, so the CR shadow opens an event at every fourth guard build. The
  first unit of an event is mirrored by `min(floor(humans / 2), 2)` extras of the same ODF with the same orders (the wave
  extras attack the Recycler, the guard extras defend the same silo).
- The guards are out on the first frame, as in the DLL (see "Stock behavior kept"); the runtime builds two tickets per frame.
- Fallback entries, tried in order when an authored path has a human within 460 m: `spawn_defend5`, `spawn_defend2`,
  `spawn_defend7`, `spawn_defend8` (authored guard posts, 1100-2000 m from the Black Dog base; the contract test checks they are
  hidden at the start).
- Live cap 60 (the runtime default is 12): 24 guards stay out all mission and the waves are 6-9 units. Only extras are dropped
  for the cap; every primary comes. The worst case with nothing destroyed is 52 primaries + 20 extras.
- Nothing is built after the mission is won or lost (`endedFlags`).

| Humans | Extras per event | Guards | Wave 1 / 2 / 3 / 4 |
| --- | --- | --- | --- |
| 1 (offline) | 0 | 24 | 7 / 6 / 9 / 6 |
| 2 or 3 | 1 | 30 | 8 / 7 / 10 / 7 |
| 4 | 2 | 36 | 9 / 8 / 11 / 8 |

## Humans' result, timer, win and loss

- Win: unchanged. Every silo recycled (`silosRecycled`) and the Chinese recycler destroyed -> `bd13003` -> `SucceedMission(...,
  "bd13win.des")` once. Any human's kill counts.
- Loss, each as in the DLL: the 45 minutes pass with silos left -> `bd13005` -> `bd13lsea.des`; the Black Dog Recycler dies ->
  `bd13004` -> `bd13lseb.des`; a silo dies without being recycled -> `bd13lsec.des` (now with `bd13006`, below); the Chinese
  recycler takes any damage before the silos are held -> `bd13lsed.des` (now with `bd13007`, below).
- Out of lives (every human out): the runtime's generic failure. The game ships no `bd13lose.des`, so no `failDes` is set
  (the same choice as `bd05cr`). Leader departs: every guest fails.
- The 45-minute countdown is shown on every peer (`Present("StartCockpitTimer")`); see the stock bug below for who counts it.

### Stock behavior kept

The guard trigger `GetDistance(user, silo)` has no threshold in the source: it is true for any nonzero distance, so all six
groups spawn on the first frame and walk to their silos. The faithful port keeps this (and `References/BlackDog13Source`
shows no proximity radius), so the CR layer keeps it too; making it a real proximity trigger would change the difficulty of
the whole mission.

## Cinematics are shared and unskippable in a network game [owner]

The one film is the intro: `CameraPath("camera_intro", 500, 1500, silo6)` with the briefing `bd13001`. The shot is driven by
`CameraPath` every frame, so the runtime's camera stream carries it to every guest; `CameraCancelled` is false in a network game
(offline it stays skippable and stops the line). The intro ends when the path has arrived **and** `bd13001` is done. A
save/load cannot resume a film (the camera is gone): on load the intro that was running is ended, as the body would on arrival.

### Stock bug: a host's skip hangs the shared shot

The shot ends on the path's arrival, which `CameraPath` returns. In a network game a host who presses skip releases only their
own camera, and the runtime then never reports an arrival again (`cameraSkipped`), so the whole mission (its waves, guards'
orders, objective and clock all start around the intro) would hang. The CR layer counts a skip that **rises after the shot
began** as the shot's arrival (the line still gates the end, the guests keep their streamed shot until then). A cancel that is
still latched when the shot opens is not a skip of this shot: it is sampled in the `CameraReady` shadow.

## Restored content [owner decision 2026-11-01]

Cut-content restorations live only in the CR layer, apply offline and in co-op, and each has a flag (`RESTORED_*` at the top of
the runtime region of `bd13cr.lua`). The DLL has no commented-out executable code; the cut content is two recorded voice
lines that no line of `BlackDog13Mission.cpp` plays.

| Restoration | Cut block it comes from | Status in this map |
| --- | --- | --- |
| Reprimand for a destroyed silo (`RESTORED_SILO_LOSS_VOICE`) | `bd13006.wav` (12.4 s, `Text/bd13006.txt`: "Lieutenant, what in the name of Sam Hill are you doing? Your orders were to recycle the Chinese silos, not destroy them. That bio-metal was an integral part of our future plans. You are relieved of your command, private.") is named by no line of the source. The silo-loss branch fails silently: `lost = TRUE; FailMission(GetTime() + 1.0, "bd13lsec.des");` (debrief: "You were ordered to take control of the silos, not destroy them!"). | The line is the voice of exactly that branch. It plays first and the debrief follows when it is done, like the DLL's other three losses (`bd13004`, `bd13005`): the CR `FailMission` holds `bd13lsec.des` until the line ends, then fails 1 s later. Repeated calls for the same loss (two silos in one frame) are swallowed. |
| Warning for an early strike (`RESTORED_EARLY_STRIKE_VOICE`) | `bd13007.wav` (10.3 s: "Lieutenant, you attacked the Chinese base before dealing with the silos. Now the enemy has had the chance to build up the scrap they need for a new Pegasus. I hope you can speak Mandarin, son.") is named by no line of the source. The branch fails silently: `if (GetHealth(chinRecycler) < 1.0 && !silosRecycled && !lost && !won) { lost = TRUE; FailMission(GetTime() + 1.0, "bd13lsed.des"); }` (debrief: "Attacking the base is futile until you have control of all the silos."). | Same mechanism for `bd13lsed.des`. |

Both lines fit because the debriefs they precede say the same thing and their transcripts name the very action the branch tests.
Played once, on every peer, through the runtime's `AudioMessage`; the debrief files are unchanged. The pending line is
saved with the mission state (`M.crcca.r.failLine`), so a load while the line plays still ends in the debrief (the host tests use a mock audio handle; whether the engine's handle survives a load is unverified).

Skipped, with the reason:

- Dormant state the DLL declares and never reads: `objective1Complete`..`objective3Complete`, the second camera pair
  (`cameraReady[2]`, `cameraComplete[2]`), `lastUser`, `scrapValue`/`lastScrapValue` (the DLL records the scrap and never
  uses it), the unused local `numSilosGone`. No behaviour to restore.
- The `sound1/3/4/5` members start NULL in the C++; the Lua port starts them absent. Unchanged.

Authored paths the script never uses (documented, not wired): `edge_path` (used by the weather as the playable box),
`spawn_defend4` (two paths carry this label; neither is used), `spawn_defend9` (a post 555 m from the Black Dog base: too
close to be a hidden fallback), and the unlabeled AI scratch routes of the map. `spawn_defend2`, `spawn_defend5`,
`spawn_defend7` and `spawn_defend8` are used as fallback entries (above), not by the body.

### Voice lines [owner decision 2026-11-01]

The shipped lines are `bd13001`..`bd13007` (wavs plus `Text/` transcripts, durations in `Config/durations.csv`). The faithful
body plays five of them; **`bd13006` and `bd13007` are the only unused lines** and are restored above. The contract test
asserts the script (body plus CR layer) names exactly the lines the repo has transcripts for.

## Stock bugs fixed in the CR layer (the faithful body is untouched)

- **Recycling by a human of any team**: `IsRecycledByTeam(silo, 1)` is a team-1-only test. See above.
- **One human as "the player"**: the guard trigger takes a single tank. See "Humans as the player".
- **The 45 minutes never run out on this map (`MultSTMission`)**: the map's mission class restarts the cockpit timer upward every
  frame, so `GetCockpitTimer() <= 0` is never true: the deadline loss (`bd13005`, `bd13lsea.des`) can never fire, in co-op and
  offline on the same map (the faithful test shows the stock behaviour with the engine timer stuck). The CR layer shadows
  `StartCockpitTimer` / `GetCockpitTimer` / `HideCockpitTimer`: the host counts the 2700 s itself (saved with the mission
  state), shows the same timer on every peer, and hides it when the silos are held. If the engine HUD keeps counting upward
  the number on screen is wrong while the logic is right (same caveat as `bd04cr`).
- **The enemy team 2**: `BuildObject(..., 2, ...)` maps to team 5 (nothing is built on team 2, a human slot in co-op).
- **A host skip hangs the shared shot**: see above.
- **Setup publishes before the presentation resets**: the runtime's `Start()` clears the presentation stream, so the CR callback
  runs `campaignRuntime.Start()` right after `M = NewState()`.
- **Loads during the intro**: ended as described above.
- **Objectives, names and the timer after a load**: the runtime's `Load` resets the presentation (objective list, nav names,
  the cockpit timer), and the body publishes them only when a stage begins. After a load (authority, once the intro is over)
  the CR layer republishes the six "Scrap Field" names, rebuilds the list from the mission state with the body's own names and
  colours (`bd13001` white; all silos held: `bd13001` green, `bd13002` white) and shows the running timer again with its
  remaining time. Nothing else is replayed (no briefing line, no guard, no wave).
- **A nil audio handle**: the gates test `sound ~= nil`, so a line that returns no handle would strand the mission or the
  intro. The CR `AudioMessage` wrapper turns nil into 0, `IsAudioMessageDone` counts nil/0 as done and `StopAudioMessage`
  ignores them.
- **Reinforcements after the result**: no unit is built once the mission is won or lost (`endedFlags`).
- Objective rebuilds are coalesced by the runtime (a rebuild identical to the last published list is dropped).
- Audio: every line has a subtitle in `Text/` (`Test-Bdmisn13CoopContract.py`); `audioSubstitute` is empty. The `.des`
  debriefs and `.otf` objectives ship with the game.
- The body already carries its own documented port fixes (the health of a missing object counts as zero, a missing handle skips the guard's distance binding).

## Weather: Ganymede

`Environment.Init` in `orbit` mode (the sun's real path, a short eclipse, Jupiter-shine at night: the same options as
`bd05cr`/`bd08cr`) plus `CREuropaWeather` with `CRGanymedeSitesBD13`, networked through the runtime (seeded timeline
from the host, host-chosen plumes/quakes/surges over the ordered stream as `EuropaState`/`EuropaPlume`/`EuropaQuake`/
`EuropaSurge`, `Save`/`Load` state, `AnnounceState`). No new weather module: Ganymede reuses the Europa director for an icy,
airless Jovian moon. `Environment.BindWeatherSensors("Ganymede", ...)` is registered once per start from the runtime's update
hook on every peer. If the module or the sites module is missing, or any weather call errors, the mission runs without weather
and logs once. The site file has fifteen vents (the geysers under the Black Dog base, around the Chinese base and across the
scrap fields), so plumes stay enabled.

Beats (host/offline only, each once, tied to the mission's own moments; the director never damages):

| Moment | Weather |
| --- | --- |
| Start, the intro | level 1 (Quiescent) |
| The first silo is recycled | a short surge (3 s, 0.4) |
| Wave one (3:00) | level 2 and a plume from `eggeizr10_geyser` under the Black Dog base |
| Wave two (10:00) | level 3 and a quake (0.35, 3 s) |
| The heavy wave three (15:00) | a surge (5 s, 0.7) and a plume from `eggeizr11_geyser` |
| The last wave (30:00) | level 4, a quake (0.5, 3.5 s) and a surge (5 s, 0.9) |
| Every silo is held (`silosRecycled`, `bd13002`) | a surge (6 s, 0.8), a quake (0.35, 3 s) and plumes from the three geysers of the Chinese base |
| The deadline passes ("we'll nuke them from orbit", `bd13005`) | level 4, a quake (0.7, 5 s), a surge (8 s, 1.0) and every vent |
| The Chinese recycler falls (`won`) | forced level released, back to level 1 |

## Tests

```sh
lua5.1 Tools/CoopCampaignTests/Test-Bdmisn13Coop.lua            # offline == faithful, 1-4 peers, scaling, intro, recycling, timer, results, voice lines, loads, weather
lua5.1 Tools/CoopCampaignTests/Test-Bdmisn13Presentation.lua    # E/A/C protocol on a guest
python Tools/CoopCampaignTests/Test-Bdmisn13CoopSourceParity.py # bd13cr.lua minus CR regions == bdmisn13.lua
python Tools/CoopCampaignTests/Test-Bdmisn13CoopContract.py     # labels/paths/teams in bd13cr.bzn (skips with a message if the map is absent)
python Tools/CoopCampaignTests/test_bdmisn13.py                 # the faithful port (needs lupa), unchanged
```

The workflow `.github/workflows/campaign-validation.yml` is not edited by this change; the four co-op commands above are the
steps to add. The contract test checks `Config/bd13cr.ini`, `Config/crbd.ini` and `Missions/bd13cr.vxt` only when they
are in the tree and says which it skipped.

## Inferences and open questions

- `IsRecycledByTeam(silo, 2..4)` on the engine's recycled-by-team record is assumed to work for any team (the DLL only ever
  asked team 1); unverified in game, as is whether a dead silo's handle still answers the query on every frame the body asks.
- Humans on teams 2-4 need a construction rig of their own to recycle a silo; the map authors one (`bvcnst`, team 1, shared).
  Whether a guest can command the shared rig is the base game's rule for shared teams-1-side units.
- The 24 guards plus up to 12 extras are built two tickets per frame (about 18 frames), where the DLL builds 24 at once;
  unverified for frame time on the real map.
- The host-counted timer and the engine HUD can disagree (see the `MultSTMission` bug).
- The live cap of 60 is a CR choice from the worst case; the extras that would exceed it are dropped, never primaries.
- Out-of-lives is not exercised by the host tests (leader departure is).
- The mock `IsRecycledByTeam` is a flag per object (`recycledBy`); the engine's rule (a construction rig finishing a recycle on
  the object) is a base-game fact the tests do not model.

## Live checklist (unrun)

1. Intro: the same shot on every peer, looking at the last silo; cameras balanced; the line `bd13001` ends the shot. A host skip
   does not hang it (it ends with the line); in a 2-4 player game a guest skip never ends it for the others. The objective
   "recycle all the Chinese scrap silos" and six "Scrap Field" beacons appear on every peer, with the 45:00 timer.
2. The six guard groups are out at once and walk to their silos; with 2-4 humans each group has 1-2 extras. None on team 2;
   all are hostile to every human team. No guard pops in beside a human.
3. A guest's rig recycles a silo (not only the host's): it counts as seized, no `bd13lsec`. The first seized silo makes a short
   surge.
4. At 3:00 / 10:00 / 15:00 / 30:00 the four waves come from the north and attack the Recycler (7 / 6 / 9 / 6 units plus
   extras); the sky stirs (levels 2-4), vents erupt under the base.
5. Recycle all six: `bd13002`, objective list green/white, timer hidden, the Chinese base geysers vent. Destroy the Chinese
   recycler: `bd13003`, one shared `bd13win.des`, the weather eases.
6. Shoot a silo instead: `bd13006` plays on every peer and `bd13lsec.des` follows it. Hit the Chinese recycler before the silos
   are held: `bd13007`, then `bd13lsed.des`.
7. Losing the Recycler: `bd13004`, `bd13lseb.des`. Letting the 45 minutes pass: `bd13005`, the sky goes to its worst,
   `bd13lsea.des` (check the host's clock against the HUD).
8. A save/load in the intro, in the field and after the silos are held; the objectives, scrap field names and timer are back; no
   unit is duplicated; the weather sky and radar on guests; no weather error in the log.
