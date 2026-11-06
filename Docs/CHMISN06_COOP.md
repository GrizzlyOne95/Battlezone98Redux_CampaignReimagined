# Chinese 06 co-op: Out There Somewhere (chmisn06)

Shared offline / 2-4 player co-op port of the Chinese (CRA) mission `ch06` on Elysium: the Chinese strike force is told
to find and destroy a large Soviet (CCA) base; "allied" reinforcements arrive on the third minute and turn out to be
Soviets in disguise; Soviet raiders harass the Chinese base for as long as the Soviet long-range power towers stand;
the mission ends when every Soviet object is dead. One `Missions/ch06cr.bzn` and one `Scripts/ch06cr.lua`
serve both modes. Companion to the faithful DLL port underneath (`Scripts/ch06.lua`, notes in
`References/Chinese06Source/README.md`, tested by `Tools/test_ch06.py`) and
[`CCA_COOP_RUNTIME.md`](CCA_COOP_RUNTIME.md) (the shared runtime). Pattern: [`BDMISN07_COOP.md`](BDMISN07_COOP.md).
Status: **host-tested only**; nothing here has run in the game (see "Live checklist").

## Layout

| File | Role |
| --- | --- |
| `Scripts/ch06cr.lua` | The faithful port plus marked `-- CR ... >>` / `<<` regions. Outside them it is exactly `ch06.lua` (`Tools/Test-Chmisn06CoopSourceParity.py`). Holds the runtime CONFIG, the native shadows, the weather beats and the restorations. |
| `Scripts/CRElysiumSitesCH06.lua`, `Scripts/CRElysiumWeather.lua` | Elysium weather (the Venus engine in its Earth-like storm dress) and the generated sites for this map (ten geysers, the playable bounds; Elysium switches vents and sulphur off, so only the bounds are used). |
| `Missions/ch06cr.{bzn,vxt}`, `chmisn06.{hg2,lgt,mat,trn}`, `Config/ch06cr.ini`, `Config/crch.ini` (MISSION6) | Map and companions (not part of this change). The Soviets are on team 5, the guests start at `coop_spawn1..4` (teams 1-4). |
| `Tools/Chmisn06Fixture.lua`, `Test-Chmisn06Coop.lua`, `Test-Chmisn06Presentation.lua`, `Test-Chmisn06CoopSourceParity.py`, `Test-Chmisn06CoopContract.py` | Multi-peer fixture and tests (real map coordinates). |

The CR regions, in file order:

| Region | Where | What |
| --- | --- | --- |
| `co-op layer` | file header | The pointer comment. |
| `co-op runtime` | after `local M = NewState()` | The restoration flags, the runtime CONFIG (including the weather beats) and the shadowed natives. |
| `restored content` | before `Start` | `Restored`: the recon patrols, the reveal, the idle-attacker hunt, the scaling bookkeeping. Also called once at the end of `Update`. |
| `co-op callback` | inside `Start`, `Update` (top and end), `Save`, `Load` | The runtime's per-frame calls. `ch06` never returns early from `Update`, so `AfterUpdate` can sit at its end. |
| `co-op victory` | inside the victory scan | One line: a Soviet request still waiting for a safe entry is a living enemy. |
| `co-op callbacks` | end of file | The engine's `AddObject`, `CreatePlayer`, `AddPlayer`, `DeletePlayer`, `Receive`. |

## Teams and ownership

| Team | Use |
| --- | --- |
| 1-4 | Humans (host on 1). The authored Chinese side (the start tank `player0_wingman`, the recycler `avrecy2_recycler`, factory `avmuf2_factory`, armoury `avslf2_armory`, the two silos, towers, scavengers and the six recon fighters) stays on team 1: shared, host-run. The reinforcement convoy is also built on team 1, as in the DLL. Extra starting recyclers are disabled. |
| 5 | The Soviets: the authored base (including the PSU towers `psu_1..4`), the `stolen` factory, and every raider and second-wave unit. The body still says team 2; the runtime maps `BuildObject(..., 2, ...)`, `SetScrap(2, ...)` and `SetAIP` to team 5, and the CR layer maps `SetTeamNum`, `SetPerceivedTeam`, `AddScrap`, `SetPilot` and the victory scan's `GetTeamNum` (see "Stock bugs"). Nothing on the map is left on team 2. |
| 7 | Support (nothing uses it here). |

Only the authority (host, or the offline player) runs the body; guests only present. `SetAIControl(5, true)` runs once
at chunk load. `SetAIP("chmisn06.aip")` always drives team 5 (the Soviet base's own production and defence).
`SetScrap(1, 50)` becomes `50 + 10 per guest` (`scrapPerGuest`), `SetScrap(2, 0)` and `AddScrap(2, 50)` (the Soviet
gift at 20 minutes) go to team 5, `SetPilot(1, 10)` gives 10 pilots to every human team (each human respawns from its
own pool). Respawns rally on the recycler.

Guest roster (`Docs/COOP_STARTING_UNITS.md`, CH 06): the vehicle list offers a Tank (`cvtnk`) and a Fighter (`cvfigh`);
the map starts the player in a `cvtnk` with `cvfigh` patrols and a `cvmufc` and `cvslf` on the map. Nothing in the
script depends on which craft a human picks.

### Humans as the player

The DLL's `user = GetPlayerHandle()` is assigned every frame and never read. In co-op the CR layer answers
`GetPlayerHandle` with the runtime's token (`crcca_players`); nothing else needs a meaning. The body never measures a
distance to the player and never aims a camera at him.

## Scaling and concealed arrivals [owner rules, mission decisions]

Scaled spawns: the ODFs `svfigh`, `svltnk`, `svtank` and `svhraz`, i.e. exactly the Soviet craft the body builds: the
second wave (four fighters and four tanks at an alternative entry, two minutes after the betrayal) and the harassment
raids (up to ten, at `annoy_1`, from ten minutes on, every ten minutes, refilling only the dead). They become
*tickets*: the body gets a negative request id, the unit is built by the runtime on the next frames, and the body's
`Attack(raider, base, 0)` and `Goto(raider, "annoy_1_path")` are replayed on it and on its extras. The shadows of
`IsValid`, `IsAlive` and `GetHealth` answer "valid, alive, full health" for a waiting ticket so the raid slots are not
refilled while a request waits.

Not scaled: the **reinforcement convoy** (12 craft on team 1, `cvfigh`/`cvtnk`/`cvhraz` at `ran_1..3`). It is the story
of the mission, built where the body says; each member is individually tracked by index and given a pilot class, a
disguise and a route, which a ticket cannot carry. The Soviet base is authored.

Events. The runtime region wraps `BuildObject` once: **a new frame or a new entry path is a new scaling event**, and the
first unit of an event is mirrored by `min(floor(humans / 2), 2)` extras of the same kind, entry and orders. The
second wave is one event (extras are fighters); one raid is one event.

| Humans | Extras per event |
| --- | --- |
| 1 (offline) | 0 |
| 2 or 3 | 1 |
| 4 | 2 |

Cap: at most **24** live scaled units (`liveCap`; the runtime default is 12): ten raiders plus a second wave plus the
extras can be alive together. Extras are the only requests dropped for the cap, primaries always spawn.

No pop-in: a ticket is never built within 460 m of any human. The entries are `ran_1..3` (more than 1.3 km from the
start buoys; `ran_3` is 550 m east of the Soviet base) and `annoy_1` (inside the Soviet base, 2.5 km from the start).
If a human stands near the entry, the next clear approach in `fallbackEntries` (`ran_1`, `ran_2`, `ran_3`) is used, else
the request waits (saved in `M.crcca`, so a save/load neither loses nor duplicates it). A raid that falls back from
`annoy_1` to a far edge would otherwise first drive across the map to the start of `annoy_1_path`, so it is sent to
`activate_2` (the Chinese base) instead. Reinforcements stop for good when the mission is won or lost
(`endedFlags = won, lost`).

## Humans' result, win and loss

- Win: the body's rule. The whole convoy dead (`ch06006`) and **every team-2 object dead** (in co-op: every team-5
  object, buildings and pilots included, via the `GetTeamNum` shadow) -> `SucceedMission(..., "ch06win.des")` once. The
  co-op layer holds the victory while a Soviet request is still waiting for a safe entry, and the restored debrief line
  delays the result (see "Restored content").
- Loss: the recycler **and** the factory both dead -> `FailMission(..., "ch06lsea.des")`. The out-of-lives failure of the
  co-op layer uses the same debrief (`failDes`). The recycler or the factory alone is not a loss.
- `wonFlags = { "won" }`: a loss after the win is ignored. `endedFlags = { "won", "lost" }`: nothing is built after the
  result.
- A departed leader fails every guest.

## Cinematics

None. The mission has no camera: the opening is two radio lines (`ch06001` with the objective, `ch06002` with the
Soviet nav beacon), then the convoy's `ch06003`/`ch06004`; the shared audio stream plays them on every peer in order,
so there is nothing to skip. The Presentation suite covers the runtime's event and camera protocol on a real guest.

An absent audio handle counts as a finished line (it becomes 0, which `IsAudioMessageDone` accepts), so the story
cannot stall. The first objective shown sets `M.crcca.r.objectiveShown` (saved with the state): it arms the restored
patrols, and a Load, which resets the presentation and drops the objective, republishes it.

## Restored content [owner decision 2026-11-01]

Cut-content restorations live only in the CR layer, apply offline and in co-op, and sit behind `RESTORED_*` flags (top of
the runtime region of `ch06cr.lua`). The C++ (`References/Chinese06Source/Chinese06Mission.cpp`) has one disabled
code line: `//BuildObject("cvtnk", 1, user);`, a debug spawn at the player's feet in the first frame. It is not restored
(a free tank for every start would be a balance change, not a recovered feature) and stays a comment in the port. The
rest of the restorations come from authored map content and an unplayed voice line.

### The unused voice line [`RESTORED_DEBRIEF`]

The ch06 catalogue is `ch06001`..`ch06007` (`Text/ch06001.txt`..`ch06007.txt`, `Tools/TranscriptSources/GoombaBZ/campaigns.csv`);
the DLL plays `ch06001`..`ch06006`. **`ch06007`** ("Good work, Major. We believe that there is no longer a Russian
presence on Elysium. Return to Ganymede as quickly as possible. You are required for a delicate mission on Europa.")
is never played. It is plainly the debrief, so it is spoken when the victory is declared and the result is delayed
by 13 s (the line runs 11.7 s) so the debrief screen does not cut it. Inference: the line is placed by its text alone;
nothing in the source orders it. No other `ch*` voice line of the stock audio (`ch01001`..`ch08009`) belongs to this
mission, and no stock `ch06` line is left over.

### The recon fighters fly their routes [`RESTORED_RECON_PATROLS`]

The map carries six Chinese fighters labelled `sw_patrol` (three) and `nw_patrol` (three) and two routes `sw_path`
(10 points) and `nw_path` (12 points) that the body never uses. `ch06001` says "We have sent reconnaissance patrols to
find it" and `ch06002` "we have found the Russian base" (the patrols are the ones that found it). Each route starts
where its trio stands and ends at the Chinese base, so once the opening objective is shown each trio is sent along
its route (`Goto(h, path, 1)`, once, by label through `AllCraft`, because the three fighters of a trio share one
label). Gated on the path existing in the map; the fighters are team-1 map units, so only the authority orders them.
`sw_trigger` and `nw_trigger` (single points at the Chinese base next to the routes' ends) have no clear use and stay
unwired.

### The disguised buildings are revealed [`RESTORED_REVEAL`]

`ch06006` ("It seems that the Russians made use of the Factory that we left on Ganymede. We suggest that you are more
careful when you attack the Russian base. They may have more of our units.") is played when the convoy is dead. The
map has exactly that: a Chinese `cvmuf` labelled `stolen` and two `abspowa` plants labelled `ld_power` standing in the
Soviet base on team 5 with *perceived team 1*: Chinese units never choose them as targets, yet the victory needs every
team-5 object dead. When the line plays, the factory and both plants are revealed (`SetPerceivedTeam(h, 5)`), and
the factory is named "Stolen Factory" and marked for every human. Inference: the line is the cue, the disguise is
authored data; nothing in the source touches them.

Authored map content the script never uses (documented, not wired): the paths `edge_path` (the playable bounds, also in
`CRElysiumSitesCH06`), `alien_1` (one point at the north-east corner; with the DLL's dead `alien1` flag it is the trace
of a removed alien arrival, and there is no unit or line to restore), `sw_trigger` and `nw_trigger` (above), the
unnamed patrol/howitzer waypoint paths of the Soviet units, the geysers, the Soviet base's own turrets, walkers,
howitzers and barracks, and the DLL's unused `objective1..3Complete` and `cameraReady/cameraComplete` flags (no cutscene
exists in this mission). **Map note:** `sw_patrol`, `nw_patrol` and `ld_power` are each labelled several times (3, 3
and 2 objects; the geysers, turrets and a turret tank repeat labels too, but nothing looks those up); `GetHandle`
would resolve to one of each, which is why the restorations walk the object lists by label.

## Stock bugs and co-op fixes in the CR layer (the faithful body is untouched)

- **Team 2 is a guest in co-op.** The body turns the traitors with `SetTeamNum(h, 2)` / `SetPerceivedTeam(h, 2)`, gives
  the Soviets `AddScrap(2, 50)`, and counts "everything on team 2" for the victory. The CR layer maps every one of them
  to team 5, and the victory scan reads `GetTeamNum` through a shadow (Soviets answer 2, every human team answers 1), so
  a guest's team-2 craft never blocks the victory and the traitors never join a guest.
- **Pilots.** `SetPilot(1, 10)` gives 10 pilots to every human team, not only team 1.
- **Idle attackers.** The traitors, the second wave and the raiders are ordered once (`Attack(h, getBase(), 0)`); a unit
  whose target died, or whose order was dropped because its target was already dead, stands where it is for ever. Every
  20 s an attacker with no command attacks the nearest living building of the base (`Restored.Hunt`); a unit that has a
  command is left alone, and nothing is ordered once the mission is decided.
- **Victory in the gap.** A Soviet request waiting for a safe entry is not an object, so the victory scan would pass
  with enemies still to arrive. The `co-op victory` region holds the victory while a ticket waits.
- **Orders on tickets.** `Goto` and `Attack` are recorded on a waiting ticket and replayed on the real unit (and its
  extras); the body's checks on tickets (`IsValid`, `IsAlive`, `GetHealth`) answer "valid, alive, full health".
- **The second wave's flood** (a source bug the faithful port already fixes: `moreRanTime` was never reset, so eight
  enemies spawned every frame) cannot recur: the wave is one scaling event.
- Objective rebuilds are coalesced by the runtime (a rebuild identical to the last published one is dropped).
- The body already carries its own documented port fixes (`References/Chinese06Source/README.md`: the `moreRanTime`
  reset, null-handle guards, `SetPilotClass` for `curPilot`, `AllObjects` for the victory scan).

## Weather: Elysium

Elysium, the Earth-like world under a blue-grey overcast: the existing `CRElysiumWeather` director (the Venus engine
re-dressed) with the generated `CRElysiumSitesCH06` sites, networked exactly as Venus in `misns2cr` and `bd07cr`
(seeded timeline from the host, host-chosen strikes over the ordered stream with the ops `VenusState`, `VenusStrike`,
`VenusErupt`, `VenusFog`, `Save`/`Load` state, `AnnounceState`). Lighting is the runtime default (subtle). If the weather
module or the sites module is missing, or any weather call errors, the mission runs without weather and logs once. The
ladder starts at level 1 (calm) and drifts to 2 (haze). Beats (host/offline only, each once, tied to the story; the
director never damages, a strike only knocks craft near it about):

| Moment | Beat |
| --- | --- |
| The convoy sets out (`ranDone`, 3 minutes after the second briefing line) | level 3 (rising) |
| The betrayal (`turnTraitor`, `ch06005`) | level 4 (storm) and a strike over a traitor |
| Every second wave and every raid | a strike over its first unit, once it is built |
| The convoy is destroyed (`reinfDestroyed`, `ch06006`) | level 3 |
| Victory | level 2 |

The severe rung (5) is not used: its visibility and radar penalty would last the whole assault.

## Tests

```sh
lua5.1 Tools/Test-Chmisn06Coop.lua            # offline == faithful, 1-4 peers, convoy and betrayal, wave and raid scaling, 460 m, fallback, idle attackers, restorations, results, weather
lua5.1 Tools/Test-Chmisn06Presentation.lua    # E/A/C protocol on a guest
python Tools/Test-Chmisn06CoopSourceParity.py # ch06cr.lua minus CR regions == ch06.lua
python Tools/Test-Chmisn06CoopContract.py     # labels/paths/teams/entries in ch06cr.bzn (map checks skip with a message if the map is absent)
python Tools/test_ch06.py                     # the faithful port, unchanged
```

## Inferences and open questions

- The recon routes are flown once from the opening objective; whether the original patrols patrolled (looped) or stayed
  parked is not in the source. Their routes end at the Chinese base, so a one-shot sweep to the base was chosen.
- `ch06007` as the debrief and the 13 s delay are inferences from the text and the line length.
- Revealing the stolen factory and the plants with `ch06006` is an inference from the line and the authored disguise.
- Scaling is per (frame, entry path), a CR inference (the same rule as `bd07cr`); `liveCap = 24` is a guess.
- The convoy is not concealed: a human within 460 m of the chosen `ran_N` (mainly `ran_3`, 550 m east of the Soviet
  base) would see 12 craft arrive. Choosing the entry is the body's random draw, which the CR layer does not override.
- A fallen-back raid drives to `activate_2` (the Chinese base) instead of the route start; the base is the raids'
  authored target (`annoy_1_path` ends there).
- The idle-attacker re-issue (20 s) costs one `GetCurrentCommand` per live attacker.
- The out-of-lives path (`failDes`) is not exercised by the host tests.

## Live checklist (unrun)

1. Opening: `ch06001` with the objective, `ch06002` a minute in, the Soviet nav beacon named "CCA Base" for everyone.
2. The six recon fighters set out along their routes on the objective (watch them reach the base; nothing odd with the
   shared label).
3. Three minutes after `ch06004` twelve craft arrive at a random far entry and drive to the base; `ch06003`/`ch06004`
   play before them. A guest scouting near `ran_3` sees them arrive (known limit).
4. The betrayal: reach the trigger or shoot one: all twelve turn, `ch06005` plays on every peer, the storm breaks over
   them, they attack the base. No guest is affected by the team change (team 2 guest!).
5. Two minutes later the second wave (4 fighters + 4 tanks + extras) arrives at a different entry, none in view.
6. Raids from ten minutes (only while a PSU tower stands); with a human at the Soviet base the raid comes from a far edge
   and drives to the Chinese base; kill the four PSU towers: the raids stop.
7. Kill the convoy: `ch06006`, the stolen factory is named, marked and targetable; kill every Soviet object: `ch06007`
   plays in full, then one shared victory (`ch06win.des`), the sky eases.
8. Lose the recycler and the factory: one shared defeat (`ch06lsea.des`), no further raids.
9. Save/load during the countdown and mid-raid: the wave goes once, the raid is not duplicated, the objective reappears.
