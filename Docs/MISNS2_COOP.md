# Mission S2 co-op: Precious Cargo (misns2)

Shared offline / 2-4 player co-op port of the Soviet mission `misns2` (three Soviet APCs must be escorted from the
start valley to the launch pad past five American ambush waves, two camera networks, a mine pass and a cut-off
squad). One `Missions/misns2cr.bzn` and one `Scripts/misns2cr.lua` serve both modes. Companion to
[`MISNS2_LUA_PORT.md`](MISNS2_LUA_PORT.md) (the faithful DLL port underneath, `Scripts/misns2.lua`) and
[`CCA_COOP_RUNTIME.md`](CCA_COOP_RUNTIME.md) (the shared runtime). Pattern: [`MISNS1_COOP.md`](MISNS1_COOP.md).
Status: **host-tested only**; nothing here has run in the game (see "Live checklist").

## Layout

| File | Role |
| --- | --- |
| `Scripts/misns2cr.lua` | The faithful port plus marked `-- CR ... >>` / `<<` regions. Outside them it is exactly `misns2.lua` (`Tools/Test-Misns2CoopSourceParity.py`). Holds the runtime CONFIG, the native shadows and the restorations. |
| `Scripts/CRVenusSitesS2.lua`, `Scripts/CRVenusWeather.lua` | Venus weather and the generated sites for this map. The generated site tables are **empty** (no sulphur runs, no vents); the weather runs without site effects. |
| `Missions/misns2cr.{bzn,vxt}`, `misns2.{hg2,lgt,mat,trn}` | Map and companions (not part of this change). The map has **no authored enemies**: Lua spawns all of them. |
| `Tools/Misns2Fixture.lua`, `Test-Misns2Coop.lua`, `Test-Misns2Presentation.lua`, `Test-Misns2CoopSourceParity.py`, `Test-Misns2CoopContract.py` | Multi-peer fixture and tests (real map coordinates). `Test-Misns2.lua` / `Test-Misns2Source.py` still cover the faithful port, unchanged. |

## Teams and ownership

| Team | Use |
| --- | --- |
| 1-4 | Humans (host on 1). The authored Soviet side (the three APCs `svapc0..2_apc`, the escort wingmen, towers, the launch pad, camera pods) stays on team 1: shared, host-run. Extra starting recyclers are disabled. |
| 5 | The Americans: every wave unit, the camera-net pods, the mines and the patrol. The body still says team 2; the runtime maps `BuildObject(..., 2, ...)` to team 5 (the three direct stage-prop builds below do the same by hand). |
| 7 | Support (nothing uses it here). |

Only the authority (host, or the offline player) runs the body; guests only present. `SetAIControl(5, true)` runs
once at chunk load. This mission has no `SetAIP`, no `SetScrap` and no AIP: the enemy is entirely scripted, so there
is no shared scrap pool and the guest-scrap bonus (`scrapPerGuest`) has nothing to attach to.

### Humans as the player

The DLL's "player" is `GetHandle("svtank0_wingman")`, the authored player tank (it sits on `coop_spawn1`). In co-op
that tank is just an AI unit, so the CR layer answers that label with the runtime's nearest-human token
(`crcca_players`) and wraps the body's `Distance` with `WrapDistance`. The three player-driven gates therefore fire
for **any** human: the cut-off squad (`bdnet4` within 550 m), the second camera net (`bdnet9`/`bdnet12` within 410 m)
and the launch-pad wave (pad within 550 m). They are approach triggers (nearest human); `farthestTargets` is empty.

The body also asks `GetTeamNum(nearest vehicle) == 1` ("a Soviet vehicle") at the three spawn passes. Humans are
teams 1-4, so the CR layer folds teams 1-4 to 1 for that call only: a human on team 2-4 springs the ambush like the
host does, a team-5 enemy near the pass does not.

## Scaling and concealed arrivals [owner rules, mission decisions]

Scaled spawns: the ODFs `bvtank`, `bvraz`, `bvartl` (the enemy waves). They become *tickets*: the body gets a
negative request id and the unit is built by the runtime on the next frames, with the body's later orders replayed
on it (`Follow(bd11, bd9)` is rewritten to the real unit). Not scaled: camera pods (`bpcamr`), mines (`proxmine`),
the two patrol fighters (`svfigh`) and the eleven stage-prop tanks of the surrender film.

Events. The body has about twenty spawn sites; instead of marking each with `BeginEvent`, the runtime region wraps
`BuildObject` once: **a new frame or a new entry path is a new scaling event**, and the first scaled unit of an event
is mirrored by `min(floor(humans / 2), 2)` extras of the same kind, entry and orders. The events are wave 1, wave 2,
wave 3 (artillery) , wave 4, the cutoff squad (`bdnet4`), the restored `nav5` raiders, wave 5 and the main platoon
(`bdspmain`), however each one is triggered.

| Humans | Extras per event |
| --- | --- |
| 1 (offline) | 0 |
| 2 or 3 | 1 |
| 4 | 2 |

Cap: at most **16** live scaled units (`liveCap`; the runtime default is 12). The nav3 pass springs wave 3, wave 4
and the restored `nav5` raiders in one frame (9 primaries, 15 units with 4 humans) and that has to fit; extras are
the only requests dropped for the cap, primaries always spawn.

No pop-in: a ticket is never built within 460 m of any human. If a human is near the authored entry, the next hidden
enemy staging point in `fallbackEntries` is used (`bdspmain`, `bdsp5`, `bdsp4`, `bdsp3`, `bdsp2`, `bdsp1`, first that
is clear), else the request waits (saved in `M.crcca`, so a save/load neither loses nor duplicates it). Reinforcements
stop for good when the convoy has arrived or an APC is lost (`heldArrivals`).

Known exception, not concealed: static scenery the body reveals at its trigger is built exactly where and when the DLL
builds it, because the body reads it back (the second net's pods) or because moving it would change the puzzle (the
nineteen mines, laid ahead of the convoy). The pods and mines can therefore appear in front of a human. The restored
first net (below) is *not* read by anything and is concealed.

## Humans' result, timer, win and loss

- Win: unchanged. The three APCs within 100 m of the launch pad -> three radio lines -> `SucceedMission(...,
  "misns2w1.des")` once (the runtime holds the result until every guest acknowledged the preceding events).
- Loss: an APC dies -> `misns212` -> `misns2l1.des` once. Out of lives (every human out): the same debrief for
  everyone. Leader departs: every guest fails.
- No `wonFlags` are configured: the faithful port deliberately lets an APC lost during the victory radio queue turn
  the result into a failure (`outcomeSent` is the only latch, it also drops pending requests), and co-op keeps that.
- On victory every live raider the runtime built (the co-op extras are not in the body's retreat list) is ordered
  to retreat to `bdspmain` like the body's own.

## Cinematics are shared and unskippable in a network game [owner]

Both films (the opening, and the surrender film that shows the platoon) are driven by `CameraPath` every frame, so
the runtime's camera stream carries them to every guest; `CameraCancelled` is false in a network game, offline both
stay skippable. The film's end is the body's own audio-gated test (`IsAudioMessageDone`), host-side.

The eleven platoon tanks at paths `100`..`110` are stage props the camera must see (`CameraPath("platooncam", ...,
bd100)`): the CR layer builds them directly on team 5 instead of as tickets, so there are no extras and no waiting
for concealment. Nine are removed at the film's end, two (`bd103`, `bd104`) attack. A save/load cannot resume a film
(the cameras are gone): on load the unfinished film is ended as the body would end it (opening: `openingcindone`
and the `misns202` line; surrender film: the same removals, orders and `misns206`).

## Restored content [owner decision 2026-11-01]

Cut-content restorations live only in the CR layer, apply offline and in co-op, and each has a flag (`RESTORED_*` at
the top of the runtime region of `misns2cr.lua`). Each is gated on what `misns2cr.bzn` carries.

| Restoration | Cut block it comes from | Status in this map |
| --- | --- | --- |
| Opening film (`RESTORED_OPENING_FILM`) | the commented timed block: `cam1t` (+9 s) `CameraPath("cinpath1", 500, 800, t1)`, `cam2t` (+9.01 s) `CameraPath("cinpath2", 600, 7000, nav1route)`, `cam3t` (+24 s) `CameraPath("cinpath4", 400, 4000, launchpad)`, `cam4t` (+34 s) `CameraFinish()` | The map has `cinpath2`, `cinpath4`, the pod `apcamr5_camerapod` (= `nav1route`) and the pad. The film rides the body's audio-gated opening: the body's own `cinpath1` shot until +9 s, `cinpath2` on the pod until +24 s, `cinpath4` on the pad until +34 s, then `cinpath1` again until `misns200` ends. The cut block's own end (`CameraFinish` at +34 s) is not restored: the audio still decides. The cut `cinpath1` values (500, 800) are not used (the active shot is 500, 200). |
| Wave-1 raiders (`RESTORED_WAVE1_RAZ`) | `//bd3 = BuildObject ("bvraz", 2, "bdsp1"); //bd4 ...; //Attack (bd3, t3, 1); //Attack (bd4, t3, 1); //SetIndependence (bd3, 1); //SetIndependence (bd4, 1);` | Two more `bvraz` at `bdsp1` attacking APC 3, built in the frame of wave 1. Wave 1's end test still looks only at `bd1`/`bd2`. They retreat through the body's own `bd3`/`bd4` entries. |
| Cutoff raiders (`RESTORED_CUTOFF`) | `//bdcutoff1..3 = BuildObject("bvraz", 2, "nav5"); //Attack(bdcutoff1, t1); //Attack(bdcutoff2, t2); //Attack(bdcut0ff2, t3);` inside the nav3 (artillery + mines) branch | Three `bvraz` at path `nav5`, built in the frame that branch arms `alerttime` (the only branch that does). The cut third order named the variable `bdcut0ff2` (a typo that never existed); the third raider attacks APC 3. |
| Wave-5 tanks (`RESTORED_WAVE5_TANKS`) | `//bd25 = BuildObject ("bvtank", 2, "bdsp5"); //bd26 = ...` | Two `bvtank` at `bdsp5`, no orders (as cut), built beside the three raiders. They retreat through the body's `bd25`/`bd26` entries. |
| Wave-5 warning (`RESTORED_WAVE5_VOICE`) | none: unused shipped line `misns211` ("Commandant, we're picking up some American units on the hill.") [owner decision 2026-11-11] | Plays once (`AudioMessage`, replicated to co-op guests) when wave 5 spawns at `bdsp5`; latched in the runtime state, so Save/Load does not replay it. Redux ships the wav only in `bzone_en/ru.zfs`, so the stock English take ships byte-exact as `Assets/Audio/misns211.wav` (guarded by `Tools/Test-ShippedCutVo.py`). |
| First camera net (`RESTORED_NET1`) | the commented `nav1 = BuildObject ("apcamr", 2, "bdnet1"); ... nav6 ... "bdnet6"` in the `bdnet4` ambush block | Six enemy `apcamr` pods at `bdnet1`..`bdnet6` in the frame of the ambush, stored in the body's `nav1..nav6` fields. Nothing reads them, so each is built only when no human is within 460 m of its post. |

Skipped, with the reason:

- The commented timed platoon film (`platooncam` timer, `CameraPath("platooncam", 1000, 600, bd100)` until
  `platooncam < GetTime()`): superseded by the audio-gated film the body runs; the two cannot both run.
- `//navmine = GetHandle("navmine");` and anything built on it: `navmine` is **not** in this map (`navmine` label absent).
- The second `//AudioMessage ("misns202.wav");` in the startup block: the body plays `misns202` when the opening
  ends; a second copy would repeat it.
- Orders for the units the body leaves without attack orders (the early nearest-vehicle wave 3/4 branches, the
  proximity platoon): the faithful port documents them as authored; they keep SetIndependence behaviour.

Authored paths the script never uses (documented, not wired): the route markers `nav2`, `nav4`, `nav6`, `nav7`,
`nav8` (the body measures against `nav1` and `nav3`, and the restoration uses `nav5`), `tursp1`, `tursp2` (turret spawn points; the body
spawns no turrets), `cinpath3` (no block, active or cut, uses it), `edge_path` (used by the weather as the playable
box), and three paths with no code behind them anywhere: `alt_trigger_wave1`, `alt_spawn_wave1`,
`alt_trigger_artillery&mines` (they look like an alternate wave-1 trigger/spawn and an alternate artillery/mine
trigger for the northern route; the intent is undocumented, so nothing is guessed from them).

Unused shipped voice line `misns211` ("Commandant, we're picking up some American units on the hill.") was first
skipped; it is restored as `RESTORED_WAVE5_VOICE` (see "Restored content") [owner decision 2026-11-11]. It plays as
wave 5 (the last ambush, sprung within 550 m of the launch pad) spawns; the line is a generic sighting warning.

## Stock bugs and co-op fixes in the CR layer (the faithful body is untouched)

- Humans on teams 2-4 and the player tank label: see "Humans as the player" (a stock `GetTeamNum(...) == 1` and a
  fixed `svtank0_wingman` would ignore every human but one).
- The cut `bdcut0ff2` typo: fixed inside the restoration.
- Markers: `MarkObjective(bd9/bd10)` fires 15 s after the artillery spawn; in co-op the guns may still be tickets
  (waiting for concealment) and the native marker call would receive a negative id. The CR layer defers the marker
  until the real unit is built.
- Extras and retreat: see above.
- Objective rebuilds are coalesced by the runtime (a rebuild identical to the last published list is dropped).
- Audio: every line the body names has a subtitle in `Text/` (`Test-Misns2CoopContract.py`); `audioSubstitute` is
  empty. The `.des` debriefs ship with the game.
- The body already carries its own documented port fixes (`MISNS2_LUA_PORT.md`: the `bdnet4` ambush now latches wave 4,
  the scout pairing, APC-alive arrivals, single outcome).

## Weather: Venus

`Environment.Init` subtle lighting plus `CRVenusWeather` with `CRVenusSitesS2`, networked exactly as in
`misns1cr`/`misn07cr` (seeded timeline from the host, host-chosen strikes over the ordered stream, `Save`/`Load` state,
`AnnounceState`). The generated site tables are empty, so there are no sulphur pools or vents: only the sky, wind and
lightning director. If the weather module or the sites module is missing, or any weather call errors, the mission runs
without weather and logs once. Beats (host/offline only): level 3 when wave 2 springs (the first ambush), level 4
when wave 3 springs (the artillery pass), back to level 2 on victory. The director never damages.

## Tests

```sh
lua5.1 Tools/Test-Misns2Coop.lua            # offline == faithful, 1-4 peers, scaling, 460 m, fallback, cameras, results, weather
lua5.1 Tools/Test-Misns2Presentation.lua    # E/A/C protocol on a guest
python Tools/Test-Misns2CoopSourceParity.py # misns2cr.lua minus CR regions == misns2.lua
python Tools/Test-Misns2CoopContract.py     # labels/paths/teams in misns2cr.bzn (skips with a message if the map is absent)
lua5.1 Tools/Test-Misns2.lua && python Tools/Test-Misns2Source.py          # the faithful port, unchanged
```

The workflow `.github/workflows/campaign-validation.yml` runs all four tests.

## Inferences and open questions

- Scaling is per (frame, entry path), a CR inference; a wave whose units a branch spawns on different frames gets
  one more event. `liveCap = 16` instead of the default 12.
- The restored opening film is untested against the real length of `misns200.wav`: if it is shorter than 24 s the
  pad shot is never reached; if longer than 34 s the film falls back to `cinpath1`.
- `fallbackEntries` assumes the six `bd*` points are all usable enemy approaches; a wave can arrive from a staging
  point behind the convoy when the intended one is watched.
- Static pods and mines can appear within 460 m of a human (stock reveal), see above.
- The out-of-lives path is not exercised by the host tests (leader departure is).

## Live checklist (unrun)

1. Opening film: same shots on every peer (cinpath1, pod flyover, pad), cameras balanced, wave 1 appears at the end.
2. Wave 1 at `bdsp1` with 2-4 humans: 4 + extras, none visible at spawn; the surrender film shows the platoon to all.
3. Walk a second human (team 2-4) to a pass: the ambush fires; wave arrives from a hidden point when watched.
4. `nav3` pass: artillery + cutoff raiders + mines; guns marked 15 s later on every peer.
5. `bdnet4` cutoff: squad, wave 4 group and the six first-net pods (none in view).
6. Second camera net -> patrol -> main platoon.
7. Launch pad: wave 5 plus its two tanks, then victory radio, raiders retreat, one shared result.
8. APC loss (including during the victory radio): one shared failure.
9. Venus sky renders on guests; no weather error in the log.
