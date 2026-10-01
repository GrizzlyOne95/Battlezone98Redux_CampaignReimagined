# misn06 DLL-source Lua 5.1 port

`Scripts/misn06.lua` is the first complete logic port of the NSDF mission from
[BZ1/from_bz2_dll_src/Misn06Mission.cpp](https://github.com/GrizzlyOne95/Battlezone_Source/blob/main/BZ1/from_bz2_dll_src/Misn06Mission.cpp).
That DLL source is the sole behavior authority. No community Lua conversion or
Redux C++ mission changes are included.

The exact retrieved source is retained at `Docs/MissionSources/Misn06Mission.cpp`.
GitHub blob: `932031b027a71d74f71a03d9fd290b99f28fa0ba`.
Snapshot SHA-256: `5a66c54a9d6c7f17ebb293434e645d317a50f7bb8e5518ff08fb705bfc27507a`.

## Preserved behavior

- Original Setup values, all 266 declared state fields, and Execute statement order.
- 28-second opening camera, staged 5th Platoon units, cancellation, and cleanup.
- Literal map labels, four random patrol choices, and four extraction paths.
- Hephestus discovery, approach/identification warnings, info scan, and new orders.
- Three required starport info types and the original discovery/recon failure chains.
- CCA escort encounters and cameras, transport-loss orders, and recycler defense.
- Three attack waves at 60/180/300 seconds after escort destruction.
- 540/362/180 cockpit timer, 5th Platoon cinematic, pursuit reminders, and late escape.
- CCA pursuit buildup, source respawn behavior, extraction requiring player AND
  recycler within 100 meters, and all six loss-description files.

The DLL's timing and oddities remain intentional parity constraints. For example,
the opening can end while narration is still playing; the approach deadline starts
at discovery; the identification deadline starts when its camera begins; and
`missionwon` is never set by the active code. This port does not rebalance these.

## Commented-out content

Every one of the source's 96 comments is present verbatim inside Lua long comments.
Comments within Setup/Execute remain beside their related logic; declaration and
native lifecycle comments are retained at the end. The exact C++ snapshot also
preserves their original placement.

This includes unused starport handles, additional patrol units, the third escort,
extra objective rows, alternate transport/Lincoln events, disabled audio lines,
timer cleanup, and the larger CCA platoon. All associated state fields remain.
The 62 complete commented code fragments also have adjacent **disabled Lua
equivalents** with mission variables mapped to `M`. Partial expression fragments
and explanatory notes remain verbatim C++ for context. Restore a complete block
from its Lua equivalent after reviewing its trigger and dependencies; translate
partial fragments before using them. Do not activate an original C++ comment by
removing its delimiter. No disabled content was silently activated or discarded.

## Necessary Lua adaptations and small fixes

| Source construct | Lua treatment |
|---|---|
| Native integer handles and zero/null audio IDs | Engine handle/message values or `nil`; absent messages count as complete and are not passed to StopAudioMessage. |
| C++ `end` state field | `M.endtime`, since `end` is a Lua keyword. |
| `rand() % 4` | `math.random(0, 3)`; the same choices, not the same native RNG sequence. |
| `GetNearestEnemy(patrol) < 450` in three conditions | Obvious handle-versus-distance bug: require a live patrol and compare distance to its nearest valid enemy against 450 meters. |
| Distance/enemy queries with absent handles | Return infinity/nil, preventing false proximity triggers and invalid native overload calls. |
| Three never-assigned fourth-patrol handles | Guard their Patrol calls, preserving the native no-op. |
| DLL save routines containing `_ASSERTE(0)` | BZR Save/Load serialize the mission table, including deadlines, random choices, game handles, and message values. No startup replay after Load. |

The script uses stock BZR APIs and Lua 5.1 only. It has no EXU/OpenShim, aiCore,
weather, difficulty, filesystem, or platform-specific dependencies. Built-in
LuaMission infrastructure must supply native engine/AI behavior; the script does
not replace strategic AI with a community implementation.

## Validation and remaining integration

Run from the repository root:

```sh
luac5.1 -p Scripts/misn06.lua Tools/Test-Misn06.lua
lua5.1 Tools/Test-Misn06.lua
python3 Tools/Test-Misn06SourceParity.py
```

Host tests cover startup, cancellation, all random patrol/extraction choices,
reinforcements, recon timing, wave scheduling, early/late extraction, pursuit,
cinematic cleanup, all loss descriptions, and Lua state restoration. Source checks
pin provenance, verify every comment/state field, and compare the ordered active
asset references and API call counts. They do not validate native rendering,
AI navigation, voice queuing, or the engine's save-file serializer.

There is currently no Campaign Reimagined `Missions/misn06.bzn` or terrain payload.
This checkpoint therefore adds source, Lua, tests, and notes without enabling the
mission in the campaign list or updating the shipping lock. Next, supply the
original mission map/terrain and retain its labels, routes, native AI data, and
assets while switching its mission class to LuaMission. Validate map dependencies
before blessing/deploying new shipping entries.

In-game checks still needed: each camera completion/cancellation route, original
map label/path resolution, AI/AIP behavior, audio sequencing, save/load during
active cameras and queued messages, all six failures, and early/late extraction.
Windows Steam/GOG and Proton/Wine runtime behavior remains unverified.
