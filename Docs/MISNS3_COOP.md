# Mission S3 co-op: The Evil Battalion (misns3)

Shared offline / 2-4 player co-op port of the Soviet mission `misns3` (CCA 03). The Soviets send a squadron of four
bombers to destroy the Black Dog recycler before the 6th Battalion is wiped out, then race home before the
Americans cut off the escape route. One `Missions/misns3cr.bzn` and one `Scripts/misns3cr.lua` serve both modes.
Companion to [`MISNS3_SOURCE_PORT.md`](MISNS3_SOURCE_PORT.md) (the faithful DLL port underneath,
`Scripts/misns3.lua`) and [`CCA_COOP_RUNTIME.md`](CCA_COOP_RUNTIME.md) (the shared runtime).
Status: **host-tested only**; nothing here has run in the game (see "Live checklist").

## Layout

| File | Role |
| --- | --- |
| `Scripts/misns3cr.lua` | The faithful port plus marked `-- CR ... >>` / `<<` regions. Outside them it is exactly `misns3.lua` (`Tools/Test-Misns3CoopSourceParity.py`). Holds the runtime CONFIG, the native shadows and the stock fixes. |
| `Scripts/CRCCARuntime.lua` | Shared co-op runtime, including the CCA mission's NSDF-to-Black-Dog ODF remap. |
| `Scripts/CRIoWeather.lua`, `Scripts/CRIoSitesS3.lua` | Io weather and the generated lava-pool / vent sites for this map (341 pools, the two geysers). |
| `Missions/misns3cr.bzn` | Map roster; authored NSDF vehicles are switched to Black Dog ODFs while their labels stay intact. |
| `Missions/misns3cr.vxt`, `misns3.{hg2,lgt,mat,trn}` | Terrain and map companions. |
| `Tools/Misns3Fixture.lua`, `Test-Misns3Coop.lua`, `Test-Misns3CoopSourceParity.py`, `Test-Misns3CoopContract.py` | Multi-peer fixture and tests. `Test-Misns3.lua` / `Test-Misns3SourceParity.py` still cover the faithful port, unchanged. |

No cameras: this mission has no cutscene, so there is no `Test-Misns3Presentation.lua` and `holdCamera` is off.

## Teams and ownership

| Team | Use |
| --- | --- |
| 1-4 | Humans (host on 1). The authored Soviet base, the four wing bombers (`bomb1`..`bomb4`) and the two nav beacons stay on team 1: shared, host-run. Extra starting recyclers are disabled. |
| 5 | The Black Dogs (the authored team 2: recycler, towers, power plants, turrets). The body still says team 2; the runtime maps `BuildObject(..., 2, ...)` to team 5 (defenders, retreat groups, escorts, patrols, mines). |
| 7 | Support (allied to humans; nothing uses it). |

Only the authority (host, or the offline player) runs the body; guests only present. `SetAIControl(5, true)` runs
once at chunk load. The body never calls `SetAIP` or `SetScrap`, so neither is shadowed (the Black Dog AI team is
enabled but has no plan: the stock mission is entirely scripted).

## Humans as one trigger

The body keeps `GetPlayerHandle()` in `M.player` and measures every trigger from it. The layer returns the runtime's
`PLAYERS` token and wraps `GetDistance`:

- **Nearest human** (approach triggers): the 200 m defender trigger (`bdspawntrig`), the 100 m patrol triggers
  (`patroltrig1/2`), the 200 m minefield triggers, the 50 m warning triggers (`don'tgohere`, `iwarnedyou`), the 410 m
  escort trigger. Any human can fire any of them, including the two failure warnings.
- **Farthest human** (reach gate, `farthestTargets`): `homesweethome`. The mission is won only when EVERY human is
  within 200 m of home (a human without a live ship counts as far, so a dead player holds the gate; the respawn
  service gathers players at `basenav`).

`IsValid` is shadowed so the token passes the body's `Valid()` guard. `Attack(unit, M.player)` is rewritten:

- on a live unit it attacks the nearest human to that unit (so the 8 s re-order retargets as people move);
- on a waiting spawn ticket it records the intent in `State().r.attack` and orders the unit the moment it is built
  (the runtime would otherwise drop an order whose target is the token). Extras share the primary's record.

## Scaling and concealed arrivals [owner rules, mission decisions]

The CCA runtime resolves the mission's NSDF `av*` requests to Black Dog units. Scaled requests `avtank` and `avfigh`
become `bvtank` and `bvraz` tickets (defenders, retreat groups, escorts); the patrol already uses `bvraz`. They are
built by the runtime at the authored entry only when no human is within 460 m. Otherwise the runtime first tries the
other authored approach points (`FALLBACK_ENTRIES` / `Entry()` in `CRCCARuntime.lua`) and only waits when none of them
is safe (saved in `M.crcca`, so save/load neither loses nor duplicates it). Mines (`proxmine`) pass straight through: they are static
hazards that appear on approach by design, and tickets would never open a minefield you are standing next to.

Events that get extras (`BeginEvent`, in `-- CR co-op scaling >>` regions): every call of `SpawnDefenders` (the first
wave and each replacement wave), the retreat group's lead tank (`bd50`) and the retreat group's lead fighter (`bd60`).
The first scaled unit of the event is mirrored by `min(floor(humans / 2), 2)` extras, with the same entry and orders:

| Humans | Extras per event | Defender wave | Retreat groups (4 leads) |
| --- | --- | --- | --- |
| 1 (offline) | 0 | 3 tanks + 2 fighters | 4 |
| 2 or 3 | 1 | 6 | 6 |
| 4 | 2 | 7 | 8 |

Extras of a defender wave are extra tanks ordered at the nearest human when they arrive; they are not tracked in
`bd1..bd5`, so they are not re-ordered by the 8 s poll and do not count for the "all defenders dead" test (stock AI
keeps them engaged). Escorts are not scaled (no `BeginEvent`) but still go through a ticket, spawned at their lead as
production, which the runtime exempts from the 460 m rule. Cap: 12 live scaled units; only extras are dropped for it.
Guest scrap: not applicable (the body never sets scrap and the Soviet side has no production in this mission).

The defender camp `bdspawn1` is ~760 m from its trigger `bdspawntrig`, so the first wave normally arrives unseen. A
human parked within 460 m of the camp delays the wave (and the retreat groups) until they leave.

## Timer, win and loss

- Win: recycler destroyed and every human home -> `misns303.wav` -> `SucceedMission(..., "misns3w1.des")` once on
  every peer (the runtime holds the result until every guest acknowledged earlier events). `FailMission` is ignored
  once `missionwon` has latched.
- Loss: the 600 s withdrawal deadline (`misns304.wav`, `misns3l1.des`) while the recycler lives; any human within
  50 m of `iwarnedyou` (`misns306.wav`, `misns3l2.des`).
- Out of lives (every human out): the mission fails for everyone with `misns3l1.des` (the stock set has no better).
- Leader departs: every guest fails the mission.

## Restored content [owner decision 2026-11-01]

None. `References/Misns3Source` has no disabled gameplay blocks (`MISNS3_SOURCE_PORT.md`), and the unused native
state members (`bd6`..`bd12`) carry no behaviour to restore, so there is no `RESTORED_*` flag. The unused shipped
voice line `misns311` ("Comrade, there is an American unit coming your way...") is audited and skipped: nothing in
the body marks a moment for it.

## Stock bugs fixed in the CR layer (the faithful body is untouched)

- **`minetrig1b` / `minetrig2b` / `minetrig3b` do not exist in the map.** The body tests each as a second trigger
  for the three minefields. A distance query on a missing path is undefined in the engine; the layer answers
  infinity for exactly these three names while the path is absent (`OPTIONAL_PATHS`), so the fields open only from
  `minetrig1/2/3`. If a later map carries the paths they work as stock.
- **Audio handle can be absent** (`IsAudioMessageDone(nil)`): the victory and both failures wait on a line's handle.
  An absent handle counts as finished so a result can never hang.
- **Objective list**: the stock port's own fix (refreshing the green return objective) is kept; in co-op the runtime
  coalesces `ClearObjectives`/`AddObjective` rebuilds, so the stream stays bounded.
- **Reach gate** (`homesweethome`) and the **players token** are not stock bugs but co-op adaptations (above).
- Audio: no stock-line substitution is needed (`audioSubstitute` is empty). Which wavs ship in every Redux language
  archive was not checked from this tree.

## Weather: Io

`Environment.Init` (orbit lighting, as `misn10cr`/`misn11cr`) plus `CRIoWeather` with the generated `CRIoSitesS3`,
networked as in `misn10cr`: seeded timeline from the host, host-chosen eruptions/quakes over the ordered stream
(`IoState`, `IoErupt`, `IoQuake`), `Save`/`Load` state, `AnnounceState`. The weather-sensor modifier is bound to the
director once after init (and again after a load). If the weather module or sites are missing, or any weather call
errors, the mission runs without weather and logs once. Beats (host/offline only; each only raises the rung):

| Mission event | Beat |
| --- | --- |
| Start | Level 1 (calm) |
| Second plea (280 s) | Level 2 |
| Defenders engage (`bdspawned`) | Level 3 |
| Recycler destroyed | Level 4 and one scripted quake (strength 0.7, 6 s) |
| Withdrawal deadline or warning failure | Level 5 |
| Victory | Release any forced level, back to level 1 |

The director never damages. Both Io vents sit on the geysers `eggeizr10_geyser` (under the Black Dog recycler) and
`eggeizr11_geyser`.

## Map content the script never uses

Paths: `hide1`, `hide2`, `hide3`, `hide4`, `edge_path`. Absent from this map and handled: `minetrig1b`, `minetrig2b`, `minetrig3b`.
Objects: the towers, power plants, barracks, supply depot, cafe and storage of both sides, the four `avturr*_turrettank`
turrets, `svhraz4_wingman` and the geysers are authored scenery or defences the script does not touch.

## Tests

```sh
lua5.1 Tools/Test-Misns3Coop.lua            # offline == faithful, 1-4 peers, scaling, 460 m, nearest/farthest, results, weather
python Tools/Test-Misns3CoopSourceParity.py # misns3cr.lua minus CR regions == misns3.lua
python Tools/Test-Misns3CoopContract.py     # labels/paths/teams in misns3cr.bzn, Io sites present
lua5.1 Tools/Test-Misns3.lua && python Tools/Test-Misns3SourceParity.py   # the faithful port, unchanged
```

The fixture names objects with strings, which the runtime reads as paths; the escort test steps the human away after
the trigger frame for that reason (a real handle is a number and a spawn at an object is exempt).

## Inferences and open questions

- Farthest-human victory is a CR decision; one AFK human holds the win (the respawn service and out-of-lives rule
  still apply). Switching it off is removing `farthestTargets`.
- The `OPTIONAL_PATHS` guard assumes a distance query on an absent path is unsafe; it only affects those three names.
- Escorts spawning at their lead while a human is within 410 m is the stock design, not pop-in the layer adds.
- The bombers `bomb1..4` belong to team 1 (the leader controls them); wing detection counts them for the patrols.
- Whether the geyser under the Black Dog recycler erupting reads well while the bombers attack it is untested.

## Live checklist (unrun)

1. Defenders arrive unseen with 2-4 humans; extras attack the nearest human; no unit pops in within 460 m.
2. Retreat groups leave on `bdpath1..4`; escorts appear when any human closes on a lead.
3. Victory needs every human home; the debrief plays; the return objective turns green on every peer.
4. Withdrawal (600 s) and warning failures end the mission on every peer once.
5. The patrol and the three minefields open from the authored triggers only (no mines at the start).
6. Io sky, lava pools and the recycler-death quake render on guests; no weather error in the log.
7. Out-of-lives shows `misns3l1.des`.
