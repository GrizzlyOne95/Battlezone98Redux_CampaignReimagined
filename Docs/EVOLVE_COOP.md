# Evolve co-op: survival on Sammy (evolvecr)

Shared offline / 1-4 player co-op port of the cut Redux single-player survival mission `EvolveMission`
(`BZ1/from_bz2_dll_src/evolvemission.cpp`, stock debriefs `sammywin.des`/`sammylse.des`). One
`Missions/evolvecr.bzn` and one `Scripts/evolvecr.lua` serve both modes. Companion to
[`EVOLVE_LUA_PORT.md`](EVOLVE_LUA_PORT.md) (the faithful DLL port underneath, `Scripts/evolve.lua`) and
[`CCA_COOP_RUNTIME.md`](CCA_COOP_RUNTIME.md) (the shared runtime).
Status: **host-tested only**; nothing here has run in the game (see "Live checklist").

## Layout

| File | Role |
| --- | --- |
| `Scripts/evolvecr.lua` | The faithful port plus marked `-- CR ... >>` / `<<` regions. Outside them it is exactly `evolve.lua` (`Tools/Test-EvolveCoopSourceParity.py`). Holds the runtime CONFIG, the native shadows, the per-human invehicle/retarget tracking and the scaled-wave extras. |
| `Scripts/CRCCARuntime.lua` | Shared co-op runtime (misns1..8, bdmisn08, now evolvecr); extended for this mission (see "Runtime changes"). |
| `Missions/evolvecr.{bzn,vxt?}`, `Missions/sammy__1.{hg2,trn,mat,lgt}`, `Config/evolvecr.ini`, `evolvecr.mpdes` | Map and multiplayer listing (see "Map packaging"; there is no `.vxt`, no vehicle depot on this map). |
| `Tools/Build-EvolveCoopMap.py` | One-off converter: the stock BZ1 1.5 `sammy__1.bzn` (archived in Redux's `tro_cam.zfs` alongside the Black Dog/Chinese maps) to `Missions/evolvecr.bzn`. |
| `Tools/Test-EvolveCoop.lua`, `Test-EvolveCoopSourceParity.py`, `Test-EvolveCoopContract.py` | Co-op tests (real `CRCoop`/`CRCCARuntime`, single-environment authority harness; see "Tests"). `Tools/Test-Evolve.lua` still covers the faithful port, unchanged. |

## Map packaging [owner finding, 2026-11-02]

The task's premise — "copy the stock sammy bzn" — assumed a shipping Redux map. It does not exist: Redux
ships only the two debrief `.des` files (`StockODFFiles/sammywin.des`/`sammylse.des`); no `sammy.bzn`/`.ini`
is anywhere in the GOG install, its `docs_reference`/`output` research trees, or the `Battlezone_Source`
corpus (which has only a bare `sammy__1.trn`, no companions). The five stock `evolve_1..5.bzn` (`StockODFFiles/`,
also in `bzone.zfs`) are a same-name red herring: a `MultDMMission` deathmatch map pack with `pspwn_N_spawnpnt`
player starts and `apammo_30_N`-style item labels, none of `evolve.lua`'s expected names (`pilot_1`, `cover_1`,
etc.) — unrelated to this mission despite sharing the word "evolve".

The real stock map **does** exist, in the classic BZ1 1.5 `tro_cam.zfs` archive bundled with Redux (the same
archive `Tools/Build-CoopMap.py` already reads for the Black Dog/Chinese maps): `sammy__1.{bzn,lgt,mat,trn}`
(no `.hg2`). Its mission class is `EvolveMission` and **every path and label `evolve.lua` names matches it
exactly**: `pilot_1..3`, `sold_1..3`, `sniper_1..3`, `spawn_1..3`, `repair`, `ammo`, `apmini_1/2`,
`apstab_1/2`, `apsstb_1/2`, `apflsh_1/2`, `aptagg_1/2`, `cover_1..4` (`Test-EvolveCoopContract.py`). The
"`*_array`, rb/wb" names in the task were the archived C++'s serialization arrays (`b_array`/`f_array`
etc.), not map content; there is nothing by those names to check.

Unlike `misn06..misn18`/`misns1..misns8` (terrain stem == mission stem == C++ class, all handled by one
`--mission` argument to `Build-CoopMap.py`) this mission's three names disagree: terrain `sammy__1`, class
`EvolveMission`, CR stem `evolve`. Rather than forcing a second naming scheme into the shared, heavily-reused
`Build-CoopMap.py`, `Tools/Build-EvolveCoopMap.py` is a small standalone script that borrows its proven
primitives (the toolbox converter, the buoy template, the stock-field reader) for this one case.

**The heightmap comes from The Red Odyssey.** Redux's `tro_cam.zfs` copy of the map has no height data
(`bzn/lgt/mat/trn` only), but The Red Odyssey 1.3 installs the BZ1 1.5 heightmap loose as
`addon/sammy__1.hgt`: 512x512 legacy samples, matching the `.trn`'s 4x4 zones (`Width=5120`). Its `.mat` is
byte-identical to ours. `Missions/sammy__1.hg2` is that `.hgt` run through the Modding Toolbox's converter
(`bztoolbox/modules/terrain_generator/research/convert_legacy_hgt.py convert sammy__1.hgt --trn-dir Missions`,
default engine rounding, *unsmoothed* — the toolbox's `LEGACY_HGT_TO_HG2.md`: Redux's own load-time cook
adds a 3x3 blur that rounds off authored rims). It is the real map: a closed bowl at 382.5 m walls with a
165 m sperm-shaped arena floor and "evolve" carved beside it; the stock start sits on that floor and every
spawn point the script uses is on it or in a lower pit (down to 96 m). The stock start is at the bottom of the
narrow tail channel, so `Build-EvolveCoopMap.py` lines the co-op starts up 12 m apart along the channel (ahead
of the start) rather than sideways into its walls; `Test-EvolveCoopContract.py` asserts every start is on the
floor with the co-op starts clear of walls one sample (5 m) around, and every used spawn point is at or below
the floor.

## Teams and ownership

| Team | Use |
| --- | --- |
| 1-4 | The humans, one team each (standard CR co-op layout: the engine puts guests on 2-4). The stock player start (`asuser0_person`) is team 1; the map adds one MultST start buoy per team (`coop_spawn1`..`coop_spawn4`). |
| 5 | The attackers (`attackRounds[*].attacker`, the four `cover_1..4` `csuserb` items). The map authors nothing for them; the faithful body builds every one on map team 2 and `campaignRuntime.Spawn` remaps it (`enemyTeam = 5, mapEnemyTeam = 2`, same as bdmisn08/misns1). |

Only the authority (host, or the offline player) runs the body; guests only present. Authority is
`CRCoop.IsCampaignLeader()` (team 1 and `IsHosting()`).

### Humans as one trigger

`GetPlayerHandle()` returns the runtime's `PLAYERS` token; `AttackPlayer(h)` (`Attack(h, M.user)`) is
rewritten, same shadow pattern as every other CR co-op wrapper, to attack the human nearest the attacker.
Wave scaling counts humans with `campaignRuntime.HumanCount()` (distinct human teams, one per human here).

## Scaling [owner decision]

Per-spawn-point attackers: `min(20, ceil(native * (1 + 0.5*(humans-1))))`, `humans` counted at
the start of the wave; `native` is `M.maxroundattackers`, the body's own per-spawn-point count (1, rising to
20 over repeated clears — unchanged, the faithful port's own escalation). Cover attackers (`cover_1..4`) and
the twelve friendly pickups use a different odf and are never scaled.

**Why this needs its own mechanism, not `BeginEvent()`/ticket extras (bdmisn08/misns1's scaling)**: those
missions mirror a *single build call* with 0-2 extras of the same kind. Evolve's own `CreateAttackerRound`
already loops `roundmax` (= `M.maxroundattackers`) times per spawn point *in the faithful body*, and that
loop bound cannot be reached from the CR layer: `CreateAttackerRound` is a `local function`, called directly
by the body at three protected sites, so a CR-region local declared earlier is shadowed by the body's own
(later) `local function CreateAttackerRound()` for the rest of the chunk; and `M.maxroundattackers` is a
plain table field, not a name a lexical shadow can intercept at all. So `BuildObject` (which *is* a bare
global the body never locally redeclares) is shadowed instead: on the first call for a given spawn-point path
each frame (`CreateAttackerRound` visits its `i=1..numunits` points in one unbroken burst of native calls, so
"first call for this path this frame" reliably means "this burst's native count is about to run"), the CR
layer reads `M.maxroundattackers` directly (a CR region can always read/write `M`'s fields, just not
intercept the body's *access* to them), computes the scaled target, and builds `target - native` extra units
immediately — spliced into the same `M.currentAttackers`/`M.diedAttackers` bookkeeping the body's own builds
use, so they count toward wave-clear and scoring exactly like a native attacker.

| Humans | Per-spawn-point attackers (native round 0, `maxroundattackers = 1`) |
| --- | --- |
| 1 (offline) | 1 |
| 2 | 2 |
| 3 | 2 |
| 4 | 3 |

## Any-human vehicle latch [owner decision]

The native `invehicle` flag latches on *any* change of `M.user`'s handle (not a query of the current craft):
preserved by the faithful port (`EVOLVE_LUA_PORT.md`). In co-op `M.user` is always the `PLAYERS` token and so
never itself "changes": the CR layer tracks each connected human's own current handle
(`CRCoop.ForEachPlayerHandle`) every frame on the authority, and when *any one* of them changes, it latches
`M.invehicle = true` and re-runs the same retargeting the native handle-change branch does (every current
attacker and unlocked cover item, `AttackPlayer` again — which, like the opening wave, resolves to whichever
human is nearest *now*). The per-human tracking table is reset in `hooks.start` (a fresh baseline each
mission start/restart, same as the faithful body's own `M.olduser = M.user` at startup) and is not itself
persisted: a save/load cannot spuriously relatch it, because nothing changed across the load from its point
of view.

## Shared score and co-op lives [owner decision]

`SetScrap(1, M.score)`/`SetMaxScrap(1, M.bestscore)` are the score HUD, not production scrap. The CR layer
mirrors every team-1 call onto teams 1-4 with the native `SetScrap`/`SetMaxScrap`, so each guest's own HUD (its
own team's scrap) shows the shared score, with no per-guest bonus (`scrapPerGuest = 0`).

Lives are CRCoop's own (`COOP_LIVES = 5` per connected human, `Docs/COOP_RESPAWN.md`): a craft death respawns
through the native MultST + `CRCoopRespawn` system, costing one life, not ending the run. The run ends only
when CRCoop reports the humans out of lives (`onOutOfLives`, fired once *some* connected human has none
left — the project's existing "every human out" semantics, unchanged from every other CR co-op mission).
Evolve's own ending is never a plain failure, though: the faithful body's `FinishRun()` always
`SucceedMission`s, choosing `sammywin.des` or `sammylse.des` by comparing the run's score against the
(stock-API-unavailable, so always-zero) baseline (`EVOLVE_LUA_PORT.md`). `hooks.outOfLives` (new, see below)
therefore calls the body's own `FinishRun` directly instead of the runtime's default `Failure()`/
`FailMission(failDes)`. The body's own death-grace path (`not Alive(M.user)` for 2 s) cannot itself end a
co-op run: `IsValid(PLAYERS)`/`IsAlive(PLAYERS)` are shadowed to always return true, so that branch never
fires in co-op; only the shared-lives ending can.

## Runtime changes [owner, in `Scripts/CRCCARuntime.lua`]

Two small, backward-compatible additions (every other CCA mission's behavior is unchanged; every existing
coop test in the repo still passes):

- `native.StartCockpitTimerUp` joins `StartCockpitTimer`/`StopCockpitTimer`/`HideCockpitTimer` in the plain
  dispatch table, so `Present("StartCockpitTimerUp", ...)` can relay the cockpit count-up timer (local-client
  HUD widget state, like the other three) to every peer. No other mission starts a cockpit timer.
- `hooks.outOfLives()`, when provided, replaces the default `Failure()` (`FailMission(failDes)`) call made
  when CRCoop reports every human out of lives — for a mission whose own ending is not a plain failure.

## Tests

```sh
lua5.1 Tools/Test-EvolveCoop.lua            # 1-4 humans scaling, nearest-human targeting, invehicle latch,
                                             # co-op lives, single ending, save/load, host-only body
python Tools/Test-EvolveCoopSourceParity.py  # evolvecr.lua minus CR regions == evolve.lua
python Tools/Test-EvolveCoopContract.py      # labels/paths/teams in evolvecr.bzn (skips if the map is absent)
lua5.1 Tools/Test-Evolve.lua                 # the faithful port, unchanged
```

`Tools/Test-EvolveCoop.lua` drives a single Lua 5.1 process as the authority (or, for the "host-only body"
check, a guest) over the *real* `Scripts/CRCCARuntime.lua` and `Scripts/CRCoop.lua` — only the native engine
and the `exu`/`RequireFix`/`ScriptSubtitles`/`Environment`/`PersistentConfig` modules are mocked (the last
four as inert stubs, same as every other CRCCARuntime mission's own peer fixture). Remote humans are
registered through CRCoop's wire API directly (`CreatePlayer` + `Receive("H"/"Q", ...)`) rather than a second
sandboxed peer environment: the E/A/C presentation wire protocol itself is already covered by
`Test-CRCoop.lua` and every other CRCCARuntime mission's own fixture; this only has to prove evolve's own
decisions are wired correctly. The workflow `.github/workflows/campaign-validation.yml` runs all four
evolve commands above plus the faithful-port source-parity check in one new step.

## Inferences and open questions

- `minPlayers = "1"` in `Config/evolvecr.ini` (not `"2"` like every other CR co-op listing): there is no
  existing single-player campaign `.ini` entry for this cut mission to share (unlike bdmisn/chmisn/misnNN),
  so this multiplayer listing is the *only* way to play it at all, including solo.
- Scaling is a CR inference: the exact formula is the owner's decision, but whether 2-3 extra pilots per
  point (at 4 humans) feels right in the actual arena is untested.
- The per-human handle-change latch assumes `CRCoop.ForEachPlayerHandle`'s per-id handle is a reliable
  "this human's current craft" signal across an eject/respawn; this is the same assumption every other CR
  co-op mission's nearest-human wrapper already makes, just applied here to a *second* purpose (the latch)
  as well as targeting.
- The out-of-lives path in `Tools/Test-EvolveCoop.lua` uses one connected human (`CRCoop.ReportOutOfLives()`
  dispatches without needing a second peer's event acknowledgements, which `CRCCARuntime`'s 3.5 s
  result-publish delay otherwise waits on); a true multi-peer "all four run out together" sequence is
  untested, matching every other CR co-op mission's own host-only test coverage of this path.

## Live checklist (unrun)

1. Load: the map renders (bowl, tail channel, carved "evolve"), every co-op start drops onto the floor.
2. Solo: the opening pilot wave (round 0) matches `Tools/Test-Evolve.lua`'s own native-baseline checks
   (3 pilots total, one per spawn point); scrap/pilot/cockpit-timer HUD all start normally.
3. 2-4 players (guests on teams 2-4, every HUD showing the same score): wave sizes scale per the table above; every attacker and cover item
   retargets correctly as players eject, respawn or swap craft.
4. One player dies (not out of lives): they respawn through `CRCoopRespawn`; the run keeps going, the wave
   clear/scoring is unaffected by their temporary absence.
5. Every player simultaneously exhausts their 5 lives: one shared ending, `SucceedMission` with
   `sammywin.des` or `sammylse.des` chosen by the final score (never `sammylse.des`'s stock-API-unavailable
   baseline producing a "win" by accident).
6. Save/load mid-wave, with 2+ players: the round, timers, unlocked cover and score all survive; no
   attacker is lost or duplicated; the per-human handle tracking does not spuriously relatch `invehicle`.
7. A late joiner is refused (same as every other CR co-op mission; `CRCoop.HasLateJoiners()`); the leader
   departing ends the run for every guest.
8. No Lua error in `BZLogger.txt` across an entire 20-round escalation to the 20-per-spawn-point cap (4
   humans): the scaled extras cannot themselves exceed `min(20, ceil(native*2.5))`, so a human count at the
   boundary should still cap correctly.
