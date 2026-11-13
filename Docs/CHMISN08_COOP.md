# Chinese 08 co-op: Stolen Convoy (chmisn08)

Shared offline / 2-4 player co-op port of Chinese mission 8 (an APC convoy rolls from the landing point to a Soviet
fort; the player captures APC #5, rides the convoy to the fort gate, jumps out disguised as a Soviet before the
convoy detonates a decoy wrecker, then demolishes the fort's power plants, comm towers and ten timed charges). One
`Missions/ch08cr.bzn` and one `Scripts/ch08cr.lua` serve both modes. Companion to the faithful port underneath
(`Scripts/ch08.lua`, [`Docs/CH08_LUA_PORT.md`](CH08_LUA_PORT.md), [`References/Chinese08Source/`](../References/Chinese08Source/))
and to [`CCA_COOP_RUNTIME.md`](CCA_COOP_RUNTIME.md) (the shared runtime). Pattern: [`CHMISN07_COOP.md`](CHMISN07_COOP.md).
Status: **host-tested only**; nothing here has run in the game (see "Live checklist").

## Layout

| File | Role |
| --- | --- |
| `Scripts/ch08cr.lua` | The faithful port plus marked `-- CR ... >>` / `<<` regions. Outside them it is exactly `ch08.lua` (`Tools/CoopCampaignTests/Test-Chmisn08CoopSourceParity.py`): the body is **not edited at all**, the runtime's per-frame calls wrap its callbacks at the end of the file. Holds the runtime CONFIG, the native shadows and the co-op fixes. |
| `Scripts/CREuropaWeather.lua`, `Scripts/CRGanymedeSitesCH08.lua` | The Europa-family weather director (reused for Ganymede, `misn01`'s planet) and the generated sites for this map. The generated vent list is **not empty** (18 geysers), unlike chmisn07's Europa map. |
| `Missions/ch08cr.{bzn,vxt}`, `chmisn08.{hg2,lgt,mat,trn}` | Map and companions (not part of this change). The enemy team 2 was moved to team 5; guests are teams 2-4 at the `coop_spawn1`..`coop_spawn4` buoys; every co-op player starts in the convoy tank `cvtnk`. |
| `Tools/CoopCampaignTests/Chmisn08Fixture.lua`, `Test-Chmisn08Coop.lua`, `Test-Chmisn08Presentation.lua`, `Test-Chmisn08CoopSourceParity.py`, `Test-Chmisn08CoopContract.py` | Multi-peer fixture and tests (real map coordinates). `Test-Chinese08.lua` still covers the faithful port, unchanged. |

## Teams and ownership

| Team | Use |
| --- | --- |
| 1-4 | Humans (host on 1). Nothing authored is left on team 1 besides the convoy escort tanks (`west_1_*`/`east_1_*`, cloaked, removed after the cut-scene) and the starting craft. |
| 5 | The Soviets: the whole authored fort (power plants, comm towers, turrets, barracks, snipers), every reinforcement wave, and the convoy itself (the five `svapc` and their `svfigh` escorts, which the body builds on the literal team 2). The runtime maps `BuildObject(..., 2, ...)` to team 5. |
| 0 | Unused by this mission's live code. |
| 7 | Support (nothing uses it here). |

Only the authority (host, or the offline player) runs the body; guests only present. `SetAIP("chmisn08.aip")` and
`SetPilot(1, 10)` run once at `MS_STARTUP`; `SetPilot(team, count)` fans a team-1 call out to every human team (team 2
remains the literal Soviet remap, handled by the native `NativeSetPilot`, never the reassigned global, so the fan-out
cannot recurse into itself).

### Humans as the player (`M.user`)

The DLL keeps **one** handle for "the player": whoever captures APC #5. Unlike chmisn07 (where any human near a
trigger counts), this mission is **sticky by human identity**: `GetPlayerHandle()` is nil until some connected human
first occupies `apc[4]`; from that frame on, it always resolves to **that same human's current craft**, every frame,
for the rest of the mission — on foot after jumping out, or back to `apc[4]` if they re-board it (which still
correctly re-triggers `MS_WAITFORWRECKER`'s re-entry fail, since their current handle becomes `apc[4]` again).
Offline, the single human is matched by handle (`M.coopDriverFound`); online, the human is matched by their stable
network id (`M.coopDriverId`, captured from `ForEachPlayerHandle`'s second callback argument) so the rule survives a
save/load and a respawn. Before anyone has boarded APC #5, `M.user` is nil; `Distance(_, nil)` already returns
infinity in the faithful body's own `Distance()` helper, so an unboarded convoy fails open (no false triggers).

This sticky-by-identity rule is the fix for a real gap: the body leans on `M.user` for the fort-approach trigger
(`Distance(M.user, "nw_trigger"/"ne_trigger")`), the cloak-zone check, and `IsUser(howitzer_nw/ne)` (clears the
howitzer objective marker) — all *after* the driver has jumped out of APC #5. A rule that went nil the moment the
driver dismounted would silently break every one of those for the rest of the mission.

If the sticky driver disconnects, the role passes to the connected human nearest APC #5 (any human if it is gone),
so those same checks never wait on a nil `M.user` for the rest of the mission.

- **Snipers.** `Strike()` (26 `ssusera` snipers) orders every sniper onto `M.user` whenever the player handle changes
  (`M.olduser ~= M.user`) or at `MS_STARTUP`. Before anyone has captured APC #5, `M.user` is nil: the CR layer's
  `Attack` shadow falls back to the **nearest human** so the snipers still react from the first frame, matching the
  single-player body's guarantee of exactly one player to target.
- **The disguise.** Jumping out of APC #5 sets the driver's `SetPerceivedTeam(user, 2)` (the Soviet side) for 20 s,
  then `SetPerceivedTeam(user, 1)` restores it. In this map the Soviets are team **5**, so the CR layer maps `2 -> 5`
  and applies it only to the **one sticky driver handle** (`CH8Perceived`), on **every peer** (the host's AI must see
  it on its copy of a guest's craft). Unlike chmisn07's squad-wide disguise, this mission's own state (`userCloakState`,
  the jump-out window) only ever changes for one handle at a time, so a single-handle op is correct here, not a
  broadcast.
- **Cloak.** The eight escort tanks are cloaked at `MS_STARTUP` and decloaked/removed after the cut-scene (native
  calls, untouched). The player's own cloak is forcibly cut within 200 m of `east_cloak`/`west_cloak` (`Cloak`/
  `Decloak`/`EnableCloaking`, routed through `CH8Cloak`/`CH8Decloak`/`CH8EnableCloak` so every peer's client reflects
  the sticky driver's cloak state, not just the authority that detected the zone).
- **The convoy explosion.** `MakeExplosion` (the APC #4 and wrecker blasts) is shown on every peer (`CH8Boom`).

## Scaling and concealed arrivals [owner rules, mission decisions]

Scaled spawns: the six reinforcement waves `CheckSpawns()` builds when a human comes within 100 m of a spawn trigger
(`spawn_1`, `spawn_2`/`spawn_2a`, `spawn_3`/`spawn_3a`, `spawn_4`, `spawn_5`, `spawn_6`). The convoy's `svapc` and
their `svfigh` `apc_escort` builds stay **direct, unscaled, real handles** (`SetName`/`Goto`/`Defend2`/`IsUser` need
an immediately-valid handle, never a ticket's negative placeholder id) — `svfigh` is shared between a wave (must
scale) and the two convoy escorts (must stay direct), so the gate is by **spawn path**, not by odf: only the six
`wave_1`..`wave_6` paths route through `campaignRuntime.Spawn`; `apc_spawn`/`apc_escort` call the native builder
directly (with the same team-2 -> 5 remap repeated by hand, since the direct path never reaches
`campaignRuntime.Spawn`'s own remap, and the same `IsAuthority()` gate repeated by hand, since bypassing
`campaignRuntime.Spawn` would otherwise let every peer build its own copy of the convoy).

An event is one frame: the first scaled unit of a frame is mirrored by `min(floor(humans / 2), 2)` extras of the same
kind, entry and orders (the authored count is never reduced, only grown).

| Humans | Extras per event |
| --- | --- |
| 1 (offline) | 0 |
| 2 or 3 | 1 |
| 4 | 2 |

Cap: at most **40** live scaled units (`liveCap`; the largest simultaneous authored count if every wave were up with
none dead is 3+8+8+3+8+8 = 38).

`GetNearestUnitOnTeam(path, 1)` (the native's own team-1 proximity check for each spawn trigger) is shadowed so a
co-op game checks **every human team**, not just team 1 — the last human in a 2-4 player game is on team *n*, not
team 1, and must still be able to trigger a wave near themself.

`config.orders = { "Attack" }` only replays the body's own `Attack` orders on a ticketed unit once its real handle
exists; the body's `Wave()`/`GotoPath()` helpers also issue a `Goto` to the unit's wave path, which `Goto` is never
shadowed and so silently no-ops on a still-pending ticket placeholder (fails `Valid(h)`) and is never replayed. A
built wave unit may therefore sit near its spawn point instead of advancing down the wave path until it has a real
target to attack. Low-impact (the stock BZ AI generally re-engages nearby enemies regardless of order); not fixed
here, since `Goto` would need a new entry in the runtime's replay list to carry a per-unit path argument it does not
currently support.

## Humans' result

- Win: all ten `ch08009.wav`-then-10-second-delay demolition blasts complete -> `SucceedMission(..., "ch08win.des")`
  once. `wonFlags = { "coopWon" }`: a loss after the win is ignored.
- Loss, every path unchanged from the faithful body and shared to every peer: losing any APC (`ch08lsed.des`), the
  convoy straggling past 100 m or breaking off early (`ch08lseb.des`/`ch08lsee.des`/`ch08lsec.des`), staying inside
  APC #5 past the 20-second jump-out window (`ch08lseg.des`), re-boarding APC #5 after jumping out (`ch08lseg.des`
  again), the recycler and factory both dying after the bang (`ch08lsea.des`), or the 4.5-minute cockpit timer
  expiring before all four power plants/comm towers fall (`ch08lsef.des`). Out of lives (every human, the shared
  runtime's own check, not the faithful body): `ch08lsea.des`, the broadest generic debrief (no shipped generic
  "mission failed" `.des` exists for this mission; every stock one is state-specific, so the runtime-level fallback
  picks the broadest, "recycler and factory both destroyed").

## Cinematics are shared, no custom skip/ETA wrapper needed

`cut_1` (22 s, the opening convoy-rollout film) and `cut_bang` (5 s, the decoy-wrecker explosion) both end on the
body's own fixed `stateTimer`, **never** on camera arrival (unlike chmisn07's films, which wait for
`CameraPath`'s own return value). `CameraCancelled` is already unconditionally unskippable in a network game
generically, inside `CRCCARuntime.lua` — confirmed by reading it, not assumed. Because neither film's progression
depends on a skip or an arrival signal, this mission needs no mission-specific ETA/skip handling at all: the camera
calls are passed straight through to the runtime's one-shot-at-a-time safety net (`CameraReady`/`Path`/`Finish`/
`Cancelled`).

## Restored content [owner decision 2026-11-01]

Cut-content restorations live only in the CR layer and sit behind `RESTORED_*` flags. **None of this mission's cut
content is coherent enough to restore** (`Docs/CH08_LUA_PORT.md`'s "Cut and unreachable content" already lists the
full audit: the `#if 0` walker-escort blocks, the commented `SetUserTarget(apc[4])`, the cut `ch08003.otf` objective
and its GREEN variants, a commented earlier military-base spawn, six cut `svscav` Hunts, a commented
`MS_WAITFORSOUND8` hand-off, and a "play avi..." comment). The faithful body's own "Source quirks kept" (the
east-power-plant branch removing `west_bolt` twice, `ch08005.wav` serving both the convoy-break and straggler
warnings) are preserved byte for byte, unmodified here.

Authored content the script never touches (documented, not wired, nothing invented):

- Paths: `edge_path` (the playable box the weather uses), `east_scout`, `west_scout` (unused scout waypoints),
  `east_sniper`, `west_sniper` (unused sniper waypoints), `guard_area` (an unused patrol area for `guard_1`/`guard_2`).
  `walker_path`, `walker_return` and `scavs` are named only inside comments for the `#if 0` walker block and the cut
  `svscav` Hunts — never by live code.
- The `magpull_1`..`magpull_6`, `west_mag_1`..`west_mag_4`, `east_mag_1`..`east_mag_4` and `sniper_1`..`sniper_26`
  families are all reached through loop-concatenated `GetHandle` calls (`"magpull_" .. (i + 1)`, etc.), not a literal
  string per label; `Tools/CoopCampaignTests/Test-Chmisn08CoopContract.py` verifies every generated label exists on the map.

Unused voice lines [owner decision 2026-11-01]: **none.** `ch08001`..`ch08009` is the whole shipped catalogue of the
mission (`Config/durations.csv`, `Text/`), and the body plays all nine (`Docs/CH08_LUA_PORT.md`).

## Stock bugs and co-op fixes in the CR layer (the faithful body is untouched)

- **One sticky, nearest-to-X player:** see "Humans as the player" (a single stock handle would ignore every human
  but the one whose handle it happens to hold, and would go permanently nil the moment the driver dismounted).
- **The Lua 5.1 60-upvalue limit.** `Update()`'s faithful body alone needs ~48 upvalues (the state table `M` plus 37
  `MS_*` state constants plus its own body-local helpers), leaving no room for ~26 shadowed natives too if they were
  `local`s like chmisn07's shadows. The shadows here are **chunk globals** instead (zero upvalue cost), defined
  inside a private sandbox (`local MissionEnv = setmetatable({}, { __index = RealEnv }); setfenv(1, MissionEnv)`) so
  that `CRCoop.lua`/`CRCCARuntime.lua` — which share this engine's default global table and call some of the same
  names internally (`GetPlayerHandle`, `BuildObject`, `SetObjectiveOn/Off`, `RemoveObject`, ...) — keep seeing the
  true natives instead of silently recursing into this mission's wrapper (confirmed with a standalone repro: without
  the sandbox, one such path recurses forever).
- **The sandbox must not swallow the engine's own entry points.** `lua_getglobal` (what the host engine uses to find
  `Start`/`Update`/etc after loading a mission script) reads the Lua state's real global table directly, bypassing
  any `setfenv` a chunk does to itself. `setfenv(1, RealEnv)` restores the chunk's environment to the real global
  table, **after** the faithful body's original functions are captured by value (`local BodyStart, ... = Start, ...`)
  but **before** the new wrapper `Start`/`Update`/`Save`/`Load`/`AddObject`/`CreatePlayer`/`AddPlayer`/`DeletePlayer`/
  `Receive` are defined. This works because a Lua 5.1 function's environment is fixed at creation time: the faithful
  body's functions (created while `MissionEnv` was active) keep resolving shadows through `MissionEnv` forever via
  the `Body*` references, regardless of what the chunk's "current" environment becomes afterward, while the new
  wrapper functions (created after the restore) land in the real global table exactly like every other mission's.
  Verified with a standalone Lua 5.1 script that loads the actual file (stubbed natives) and asserts from *outside*
  the chunk that `_G.Start`, `_G.Update`, `_G.Save`, `_G.Load`, `_G.AddObject`, `_G.CreatePlayer`, `_G.AddPlayer`,
  `_G.DeletePlayer` and `_G.Receive` are all real functions in the real global table; `Tools/CoopCampaignTests/Chmisn08Fixture.lua`'s
  `makePeer` re-exercises the same load order against the **real** `CRCCARuntime.lua`/`CRCoop.lua` (not stubs) for
  every test in `Tools/CoopCampaignTests/Test-Chmisn08Coop.lua`, which calls every one of those entry points through `p.env.*` and
  would error immediately on a nil call if any were trapped in the sandbox instead.
- Orders aimed at a dead or replaced single player handle: `Attack` falls back to the nearest human when no sticky
  driver has been found yet (see "Humans as the player").
- A save in the middle of a film: a load never replays a build, a camera or an audio line (`Docs/CH08_LUA_PORT.md`'s
  own "Save/Load" note); `ResetObjectives()` is called once after a co-op load to rebuild the objective panel from
  `missionState` alone, since the body only issues objectives at its own events.
- Objective rebuilds are coalesced by the runtime (a rebuild identical to the last published list is dropped).
- Audio: every line the body names has a subtitle in `Text/` (`Tools/CoopCampaignTests/Test-Chmisn08CoopContract.py`).
- The ticket-replay gap for `Goto` on a still-pending wave unit: see "Scaling and concealed arrivals".

## Weather: Ganymede

`Environment.Init` in orbit mode plus the shared Europa-family director (`CREuropaWeather`, reused for every ice moon
including Ganymede) with `CRGanymedeSitesCH08`, networked through the runtime (seeded timeline from the host,
host-chosen quakes and surges over the ordered stream, `Save`/`Load` state, `AnnounceState`) and bound to the sensor
service. If the weather module or the sites module is missing, or any weather call errors, the mission runs without
weather and logs once. **The generated site table has vents** (18 geysers), unlike chmisn07's empty Europa map, so
the plume beat fires once a plant or tower falls (guarded by the vent count, as every CR mission's plume beat is).
Beats (host/offline only, each once, tied to the story): the convoy rolls out -> level 2; the decoy wrecker's bang ->
level 3 plus a quake; a power plant or comm tower falls -> level 4, a radiation surge, and (since this map has vents)
a plume; victory -> `ReleaseForcedLevel` and calm; a loss without a win -> level 4 (restless ice). The director never
damages.

## Tests

```sh
lua5.1 Tools/CoopCampaignTests/Test-Chmisn08Coop.lua            # offline == faithful, 1-4 peers, sticky driver, scaling, convoy fails, cockpit timer, out-of-lives, saves, weather
lua5.1 Tools/CoopCampaignTests/Test-Chmisn08Presentation.lua    # E/A/C protocol and this mission's five per-handle ops on a guest
python Tools/CoopCampaignTests/Test-Chmisn08CoopSourceParity.py # ch08cr.lua minus CR regions == ch08.lua
python Tools/CoopCampaignTests/Test-Chmisn08CoopContract.py     # labels/paths/teams/start file in ch08cr.bzn (skips with a message if the map is absent)
lua5.1 Tools/CoopCampaignTests/Test-Chinese08.lua               # the faithful port, unchanged
```

The contract test checks `Missions/ch08cr.vxt` and `Config/ch08cr.ini` only when they are present.

## Inferences and open questions

- **Sticky-by-identity, not nearest-to-X.** Unlike chmisn07 (where any human near a trigger counts), this mission has
  exactly one meaningful "player" concept (whoever is driving APC #5), so sticky identity was chosen over a
  proximity rule — a CR design decision, not implied by the source. See "Humans as the player".
- The real-engine entry-point visibility (the `setfenv`/`RealEnv` sandbox restore) is reasoned through and verified
  with a standalone script and the real runtime modules under the test fixture, but **has not been confirmed in an
  actual live game** — flagged explicitly in "Live checklist" below.
- The `Goto`-on-a-pending-ticket gap (see "Scaling and concealed arrivals") is left as a documented, low-impact
  limitation rather than fixed, since fixing it would require extending the runtime's replay-order mechanism to
  carry a per-unit path argument it does not currently support.
- Scaling is per frame, a CR inference, following the same convention as every other CR co-op mission.
- The out-of-lives path and the cockpit-timer expiry path are exercised by the host tests; neither is exercised live.

## Live checklist (unrun)

1. Two clients, DX11: the convoy rollout cut-scene (`cut_1`) is the same on both, the opening line plays once on both.
2. Five `svapc` and two `svfigh` escorts spawn 30 s later with real, driveable handles; the nav "APC Convoy" appears
   after `ch08003.wav` finishes.
3. One client captures APC #5, drives to "Base", VO4, scrap 100, the APC #4 marker clears at 100 m.
4. Each failure path: lose an APC, straggle past 100 m, break off early at `apc_fail`/`trigger_1`, stay inside APC #5
   past the 20-second jump-out window, re-board APC #5 after jumping out.
5. Jump out at `trigger_1` with time to spare: every peer sees the driver disguised as Soviet (team 5) for 20 s, the
   bang camera, the APC and wrecker explosions, the mag mines removed, the recycler/factory/armory arriving.
6. `nw_trigger`/`ne_trigger`: VO, howitzer/power/comm markers on every peer, the howitzer user-targeted for the
   sticky driver only; kill one power plant, see the 4:30 cockpit timer, kill the rest; timer expiry fails.
7. 10 demolition blasts over ~106 s, `ch08009.wav`, victory 10 s later, shared to every peer.
8. Reinforcement waves scale with player count without anything popping into view near a human; a wave unit that
   spawns far from any human still advances toward its wave path (watch for the documented `Goto`-ticket gap).
9. Save and load at: mid-convoy-spawn, inside the jump-out window, mid-demolition. Nothing respawns or replays.
10. The Ganymede sky renders on guests (orbit lighting, a quake at the bang, a plume once a plant/tower falls), no
    weather error in the log.
