# CCA 05 "Controlling the High Ground": co-op and weather (misns5cr)

`Scripts/misns5cr.lua` is `Scripts/misns5.lua` (the faithful DLL port, `Tools/Test-Misns5.lua`) plus marked
`-- CR ... >>` / `<<` regions. Outside the regions the file is the faithful port byte for byte
(`Tools/Test-Misns5CoopSourceParity.py`). The runtime contract is `Docs/CCA_COOP_RUNTIME.md`; the template is
`Docs/MISNS1_COOP.md`. The map is `Missions/misns5cr.bzn` (terrain `misns5`); weather is Titan
(`CRTitanWeather`, sites `Scripts/CRTitanSitesS5.lua`, 25 pool anchors, generated).
The authored NSDF turret in the map now uses the matching Black Dog ODF; its map label is preserved.

## Teams

| Team | Role |
| --- | --- |
| 1-4 | Humans (host/leader = team 1). The Soviet base (recycler, factory, depot, plants, towers) is team 1 and shared. |
| 5 | The Black Dogs (the DLL's team 2). The body still says 2; the CR layer maps it. |

Mapped in the CR layer: `BuildObject(..., 2, ...)` (runtime `Spawn`), `SetAIP` (always team 5), `SetPilot(2, 30)` and
`AddScrap(2, ...)` (local wrappers), and the body's `GetTeamNum(h) ~= 2` filter in `AddObject` (a local wrapper
reports team 5 as 2 to the body only). `SetAIControl(5, true)` runs once by the runtime at chunk load.

## Scaled

`BeginEvent()` precedes the first scaled spawn of each event; the extras are `min(floor(humans/2), 2)` units of the
same kind, same entry and same orders. `liveCap` 12 drops only extras. The runtime resolves NSDF `avfigh` and `avapc`
requests to Black Dog `bvraz` and `bvapc`; `bvltnk` is already Black Dog.
`bvhraz`.

| Event | Spawn | Scaled |
| --- | --- | --- |
| Chaff fighter (every 50-80 s, from 180 s after the opening) | `spawn5` | the fighter |
| APC strike (70 s into the mission) | `spawn6` | the first APC (the second APC is not an event primary) |
| Factory wave 1 (3 razors) | `spawn6` | the first razor |
| Factory waves 2, 3, and the waves that continue past 3 (3 light tanks) | `spawn5` | the first tank |

Not scaled: the two opening artillery pieces (`spawn1`, `spawn2`), the commander walker (`spawn3`), the enemy
recycler `killme` and its two guards (`spawn7`), the two final-phase scavengers, the intelligence pod. Authored entry
`spawn5`/`spawn6` is 600-1000 m from the base; when a human is within 460 m the request takes the next of
`spawn5`, `spawn6`, `spawn7`, `edge_path`, otherwise it waits (saved with the mission). `spawn1`..`spawn4` are inside
the base and are never fallbacks.

Scrap: `AddScrap(1, 10)` becomes `10 + 10 * (humans - 1)` on team 1 (the shared base), bounded by the head count.
The orders of the faithful body (`Goto`, `Attack`, `Defend2`) go through `R.Order`: on a ticket they are recorded
and replayed on the real unit and its extras; `AddObject` orders (route to the player recycler) run on the authority
only.

## Cutscene

The opening is one audio-driven `CameraPath("campath", ..., sbhang0_repairdepot)` shot. In a network game it is
shared and unskippable (`CameraCancelled` is false; a skip releases only the skipper's own camera); offline it is
skippable as in the faithful port. No camera is held (`holdCamera` off): the body re-issues the path every frame.
There are no other cameras, so `Tools/Test-Misns5Presentation.lua` covers the shared opening stream.

## Restored content

| Flag | What | Source block | Status |
| --- | --- | --- | --- |
| `RESTORED_INTEL` | The intelligence camera pod (`spcamr` at `camera1`) is marked on the HUD (named "Intelligence Camera") together with the enemy recycler. | `SetObjectiveOn(killme);  // should be sam` | Restored. The map carries `camera1`; the pod is built for the humans (team 1), so it works offline and in co-op. The recycler marker stays. |

## Skipped (documented, not restored)

| Block | Reason |
| --- | --- |
| `if ((second_message) && IsAudioMessageDone(aud) && !third_message) { aud=AudioMessage("misns503.wav"); third_message=true; }` (opening) | It repeats the same line the live block already plays (`misns503.wav`); restoring it would play that line twice. |
| `(GetTime()>camera_time)` in the opening exit | A 17 s deadline the stock mission leaves audio-driven (two lines last longer); restoring it would cut the briefing. `camera_time` stays unused. |
| `// BuildObject("avtank",2,"spawn3");` | An alternative to the walker; the walker is the commander the wave trigger depends on. |
| `//wave_type=rand()%2` | Unused random wave type; the waves are deterministic in the shipping source. |
| `// killme=BuildObject("avrecy",2,"spawn7");` (wave 3) | Superseded: the recycler is already built with the APC strike. Building it again would duplicate it. |
| Unused map content: `spawn4`, `avturr0_turrettank`, `svtank2_wingman`, `svtank59_wingman`, `svmine59_minelayer`, `svltnk0_wingman`, `svscav1_scavenger`, `svscav2_scavenger`, `sbtowe0_turret`, `sbtowe1_turret`, `sbtowe2_turret`, `eggeizr10_geyser`, `eggeizr15_geyser`, `sfield0_scrapfield`, `sfield2_scrapfield`, `sfield3_scrapfield` | No script uses them; they are the player's starting units and scenery. `avturr0_turrettank` is the single authored enemy craft (team 5, no orders). |

`misns502.wav` has no caller in the source and is not restored (no line or objective is attached to it).

## Stock bugs and gaps fixed (CR layer only; `Scripts/misns5.lua` is untouched)

1. `AddObject` filters on team 2 and `Start` calls `SetAIControl(2, true)`: with the enemy on team 5 the commander
   was never captured and the units were never routed. Fixed by the team wrappers above; `SetAIControl` becomes a
   no-op because the runtime enables team 5 at chunk load (`SetAIControl` is a chunk-root call).
2. `AddObject` runs on every peer: a guest would have ordered replicated enemy units. Guests now stop after the
   runtime's own `AddObject`.
3. `SetPilot(2, 30)` and `AddScrap(2, ...)` named the DLL team (see Teams).
4. Stock `misns5.aip` puts `svturr` (5 Soviet turrets) at priority 15, above the razors and tanks; the Black Dog
   recycler cannot build Soviet units. The CR layer maps it to `ODF/crns5.aip`, the same plan with `bvturr`.

Kept as stock (documented, not changed): the enemy recycler dying before the final phase does not win until wave 3
opens the final phase (then the win lands immediately); the waves continue past wave 3 during the ten-second result
delay.

## Weather (Titan)

`weather = { module = "CRTitanWeather", sites = "CRTitanSitesS5", ops = { "TitanState", "TitanRoll" },
startLevel = 1 (Still), targetLevel = 2 (Hazy) }`. A missing module or sites file disables weather, never the
mission. Beats (authority only, once each, saved in `M.crcca`):

| Beat | Trigger | Target |
| --- | --- | --- |
| Hazy | the opening ends and the commander walker is out (`defender`) | 2 Hazy |
| Drizzle | the APC strike is launched (`h1`) | 3 Drizzle |
| Shroud | the final phase opens (`last_phase`, wave 3, enemy recycler + intelligence) | 4 Shroud |
| Easing | victory | 2 Hazy |

## Live-test checklist (not covered by the mocks)

1. Host + 1-3 guests: the opening shot plays for all, no skip, objectives appear for all together.
2. `crns5.aip` (stock `misns5.aip` with Black Dog build and building-match entries) actually builds and sends Black Dog units for team 5.
3. The commander walker, chaff fighters and waves route to the player recycler; guests never see double orders.
4. APC strike and waves arrive from `spawn5`/`spawn6` (not from inside the base); with 4 players they bring
   2 extra units; the live cap does not stall late waves.
5. The marked intelligence pod and enemy recycler are visible on every HUD; killing the recycler in the final phase
   ends the mission for everyone with `misns5w1.des`; losing the recycler gives `misns5l1.des`.
6. Titan drizzle/shroud reach guests; a mid-mission save/load keeps the beats (no replay) and the pending strike.
7. Offline play: opening skippable, all waves and the win/loss unchanged from the faithful mission.
