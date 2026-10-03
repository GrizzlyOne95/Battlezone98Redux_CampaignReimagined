# misn16 DLL-source Lua 5.1 port

`Scripts/misn16.lua` ports the complete active mission logic from
[BZ1/from_bz2_dll_src/Misn16Mission.cpp](https://github.com/GrizzlyOne95/Battlezone_Source/blob/main/BZ1/from_bz2_dll_src/Misn16Mission.cpp).
That DLL source is the sole behavior authority; no community Lua or Redux mission
implementation was used. The script uses stock BZR APIs and Lua 5.1, with no
EXU/OpenShim, filesystem, weather, or difficulty dependencies.

The exact native source and empty header are in `References/Misn16Source/`:

| File | Upstream Git blob | SHA-256 |
|---|---|---|
| `Misn16Mission.cpp` | `0b6305ff8ec4f218556c4fe1504e7329177e3e48` | `8f16127507361360ed1b135dcc3764e44d4e3e1bae575bd3601386942629cde5` |
| `Misn16Mission.h` | `54fe03a6d9e7e8fb5178801a486512b52350d5e4` | `14dd760f792b2157f3d12af8828f63923317b178ad48c3597583b3398ec0662f` |

## Preserved mission behavior

- All 38 native state fields, including unused reinforcement/camera handles and
  `finish_cam`; nil object/message fields are initialized explicitly in Lua.
- Both opening radio calls, 50 team-1 scrap, `misn16.aip`, the original objective,
  four beacon names, and three defending alien SATs.
- Opening camera path, height/speed, hangar target, 20-second timeout, cancellation,
  and completion of the second briefing as alternative exits.
- Team-1 Soviet combat units attack one randomly chosen alien base; scavengers and
  haulers travel there. All remain player-commandable with priority 0. Other teams
  and ODFs are ignored; the most recently added qualifying unit becomes `newbie`.
- First reinforcement deadline at 120 seconds, first type chosen from 1/2, seven
  subsequent type choices, 180-second recurrence, and nine actual reinforcement
  waves. The tenth deadline produces no units or active radio call.
- Two-second delay before the optional reinforcement shot, strict greater-than
  150-meter enemy-distance check, original centimeter offsets, four-second shot,
  and player cancellation.
- First SAV at 60 seconds. Each deadline uses the current gap before reducing it
  by five seconds, from 150 down to a minimum of 60 seconds.
- First SAT pair at 90 seconds, `sat1`/`sat2` spawns and `strike1`/`strike2` routes.
  Subsequent SAT deadlines use **the next SAV deadline + 90**, as in the source.
- Either fully cleared tower pair, or loss of either alien building, starts a
  two-SAV factory attack once. A second two-SAV recycler attack follows 120 seconds
  later. Both attacks retain priority 1.
- Destruction of both bases schedules `misn1613.wav` and `misn16w1.des`; loss of the
  recycler schedules `misn1612.wav` and `misn16l1.des`. Both use a 15-second delay.
- Native Execute order and strict timer comparisons. Waves and an already
  scheduled second counterattack continue during the end delay. Victory and loss
  checks remain independent, including their ordering on simultaneous destruction.

The native switch has **no break after type 5**. Its light unit therefore also
spawns type 6's three tanks and repeats `misn1607.wav`. This is preserved explicitly;
changing it would change the authored combat pressure. Unusually coupled SAT
timing and independent ending checks are also retained rather than redesigned.

## Comments and cut content

Every one of the 49 original C++ comments is present verbatim in the Lua comment
archive, including comments from declarations and native save/load scaffolding.
The seven disabled code statements also remain beside their related logic, with
disabled Lua equivalents for reconstruction:

- Extra fighter at `reinforce24` and extra tank at `reinforce14`.
- Exhausted-reinforcement radio `misn1614.wav`.
- Third factory-counterattack SAV and its factory attack order.
- Third recycler-counterattack SAV and the original repeated `Attack(sav1,recy,1)`.

That last disabled line names `sav1`, not `sav3`; the original spelling is preserved
and noted. No cut content has been activated. The byte-identical source snapshots
preserve the complete C++ declaration/lifecycle code and original placement.

## Lua adaptations and bounded fixes

Each fix is explained beside the relevant Lua code.

| Source issue or construct | Port treatment and effect on mission flow |
|---|---|
| `rand()%N` | `math.random` with the same ranges and call ordering; no reseeding. The native RNG sequence is not reproduced. |
| `WHITE` | Stock Lua objective color `"white"`; source default duration retained. |
| Native null handles/messages | Lua nil values plus validity guards. An absent message is complete; invalid object handles never reach stock location/command overloads. A randomly selected destroyed base is not replaced with the other base. |
| Uninitialized local `enemy` when the player is dead | Skip the optional reinforcement shot for a dead player or missing subject. No enemy allows the safe shot; a valid enemy retains the strict >150 test. Spawn timing and combat orders are unchanged. |
| Camera subject removed during the shot | Finish the active reinforcement camera instead of querying the deleted object. Valid-subject shots retain the four-second deadline and offsets. |
| Hangar destroyed while spawns remain scheduled | Save its startup position. Use the native handle overload while valid, then the cached vector for the same intended spawn site and unchanged units/deadlines. A missing initial hangar has no recoverable site, so no alternative location is invented. Native placement details require in-game checking. |
| Reinforcement counter increments every frame after its tenth deadline | Saturate `rcount` at 10. The source's nine spawn events, radio calls, and camera opportunities are unchanged; only the unused post-exhaustion count stops growing. |
| C++ union serialization / `ConvertHandle` | Stock LuaMission Save/Load serialize the state table, including deadlines, random choice, object/message values, camera flags, and the cached position. Load does not replay startup. |

Stock LuaMission must provide the native strategic-AI behavior formerly supplied
through AiMission. The script retains `SetAIP("misn16.aip")` and does not introduce
a late `SetAIControl` call or a replacement Lua AI.

## Validation and integration

Run from the repository root:

```sh
lua5.1 -e 'assert(loadfile("Scripts/misn16.lua"))'
lua5.1 Tools/Test-Misn16.lua
python3 Tools/Test-Misn16SourceParity.py
```

Validation completed: **411 Lua 5.1 host checks** and **99 source checks**. Host
tests exercise all reinforcement manifests and both initial random choices;
callback routing; opening/reinforcement camera exits and exact timer boundaries;
wave acceleration/coupling; all four counterattack triggers; deleted-hangar
fallback; nine-wave exhaustion; victory/loss combinations; and active-camera state
restoration. Native stubs reject invalid handles. Source checks pin both upstream
blobs and verify all 38 fields, 49 comments, seven disabled statements, and counts
of all 92 active literal references.

The host uses Lua 5.1. Tests do not run the game, strategic AI, navigation,
rendering, audio queue, or the engine save-file serializer. The state restoration
test verifies the Lua callbacks and data, not native userdata serialization or
restoration of camera/audio engine state.

Current main has no misn16 map/terrain or `misn16.aip`. This checkpoint adds the
logic port, source snapshots, tests, and notes without registering the mission or
changing the shipping lock. Integration needs the original map with its exact
labels/paths, native AIP data and referenced assets, and LuaMission configuration.
Then check both cameras, radio sequencing, strategic AI and Soviet callbacks,
destroyed-hangar wave placement, all endings, and saves during each camera and
counterattack phase in-game before deployment.
