# misns8 DLL source port

`Scripts/misns8.lua` ports the stock Soviet mission directly from
`GrizzlyOne95/Battlezone_Source/BZ1/from_bz2_dll_src/Misns8Mission.cpp`.
The `.cpp` and `.h` here retain the exact upstream bytes, including all commented
code, native declarations, initialization and serialization scaffolding.

- C++ Git blob: `9d5dfd561387e867bcbfc973573087616bca2cbe`
- Header Git blob: `7d8863fc2abc6bc4176fb64d526eeb01dd13baa7`
- Runtime: stock BZR LuaMission, Lua 5.1; no campaign helper or extension required.

The active port retains base construction, center maintenance, factory convoy,
replacement factory, offensive AIP changes, the defense/scrap trigger for Plan C,
recycler evacuation and recovery, all six SAV followers and enemy conversions,
Romeski's player/SAV first-shot reactions, help and death messages, and both
victory delays. The source has no scripted failure branch. Destroying the enemy
recycler remains the victory condition regardless of Romeski's fate.

Disabled C++ is retained in place in Lua long comments. This includes the turret
advance/deployment sequence, alternate tank count gate, early Plan C transition,
escorts and escort prerequisites, evacuation warning/navigation camera, and SAV
orders when Romeski has not spawned. C++ comments do not nest: the second `/*`
inside the initial turret block remains part of that single disabled block.
Cut content is preserved without activating it.

Native API mappings use stock `AddHealth`, `GetHealth`, `IsDeployed`,
`GetWhoShotMe` and `SetObjectiveName`. Native producer `Pickup(..., 0, 1)` uses
Lua `nil` for its empty target. `check2` remains truncated to an integer. Only
`AddObject` registers source production slots; `CreateObject` is not also wired
to that registration. Numeric state exists before map callbacks; `Start` binds
map labels without clearing production slots. Save/Load persists the complete
state table and restored engine handles without replaying mission startup.

Documented fixes in the port:

1. Recycler arrival polling stops after `recy_goto_geyser` becomes true. The
   original polling branch otherwise resets `recy_time` immediately before the
   deployment branch every time it is due, making deployment/recovery unreachable.
   Arrival still sets the original ten-second deadline; deployment then uses the
   original five-second polling and `misns8a`/`misns8f` AIP sequence.
2. Six maintenance completion checks accept `>= 1` rather than `== 1`, preventing
   extra matching buildings from permanently blocking a rig. The ordinary
   one-building case, building priorities and timers are unchanged.
3. Proximity tests reject absent/deleted handles before calling the Lua overload,
   preventing invalid calls or false arrival on a broken map. Valid-map distances
   and all source thresholds are unchanged.

Checks:

```sh
python3 Tools/Test-Misns8SourceParity.py
lua5.1 Tools/Test-Misns8.lua
```

The mock suite exercises startup, base/center construction, convoy warning and
suppression, factory replacement, offensive priorities, Plan C and recycler
recovery, six SAV conversions, attacker decisions, help/death timing, all six
maintenance fixes, missing-handle distances, save/load and both victory endings.
These are script-level checks; actual AI production, navigation, audio and map
integration still require an in-game BZR playthrough with the original mission
assets. This change adds the source port for review; it does not modify mission
map wiring or the shipping lock.
