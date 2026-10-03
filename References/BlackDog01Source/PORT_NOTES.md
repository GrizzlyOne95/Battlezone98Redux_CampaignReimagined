# Black Dog 01 DLL-source port

`Scripts/bd01.lua` ports only `BZ1/from_bz2_dll_src/BlackDog01Mission.cpp`
from [Battlezone_Source](https://github.com/GrizzlyOne95/Battlezone_Source/blob/main/BZ1/from_bz2_dll_src/BlackDog01Mission.cpp).
Source Git blob: `c55ead909f5e1c4415c7fe43d6d14115ff9e2dc4`.
The adjacent C++ archive preserves the full file, including every comment,
unused member, macro, and native serialization routine; line endings are
normalized to LF. The disabled immediate `SucceedMission` debug call also
remains commented at its corresponding location in Lua. There are no other
disabled gameplay blocks in this source.

The script uses the stock BZR LuaMission API and Lua 5.1. It introduces no
campaign helper dependencies, AIP, multiplayer behavior, asset substitutions,
or map/installation changes. To run it, the mission must load LuaMission with
`bd01.lua` and provide the original labels, paths, ODFs, audio, OTFs and DES files.
Map wiring and deployment are outside this source-port change.

## Preserved behavior

| Source stage | Lua behavior |
| --- | --- |
| Startup | 12 scrap, 10 pilots, recycler/two wingmen movement; opening audio and camera |
| Deployment | First warning 90 seconds after camera completion/cancellation; next warning 30 seconds after first audio finishes; one-second failure after final audio |
| Nav Alpha | Spawn beacon and two cloaked `cvfigh` ambushers 20 seconds after recycler deployment; `BD01002.WAV` blocks later stages until complete |
| Nav reminders | 60 seconds after target selection, then 30 seconds after reminder audio finishes; ally/player distance strictly below 100 or an uncloaked ambusher completes the objective |
| Retreat | Either ambusher's death sends the survivor along the retreat path, cloaked; five-second delay |
| Wave 1 | Two fighters attack immediately; camera starts survivor attack and `bd01003.wav`; camera arrival/cancellation spawns two more fighters; each fighter starts cloaked and decloaks |
| Wave 2 | 60 seconds from first wave spawn, independently of camera completion; four fighters and one light tank across the two source paths |
| Victory | Both ambushers and all nine wave units dead; congratulatory audio finishes; four-second win delay |
| Recycler loss | Failure audio finishes; four-second loss delay |
| Objectives | Three staged OTF entries, original completion colors and visibility gates |
| Save/load | All used and unused mission state, unit handles, camera flags, audio handles and absolute timers restored without spawning or replaying startup |

The source's stale `scavengersCreated` name and empty `AddObject(Handle)` hook
are preserved: this mission waits for recycler deployment, not scavenger builds.
Finite timer sentinels, strict comparisons, camera coordinates/speeds and paths,
spawn order, priorities, debrief files, and the original uppercase macro audio
filename are retained. Native default `Goto` priority is explicitly passed as
0 because stock Lua's default is 1. `IsDeployed`/`IsCloaked` use Lua API casing;
`SetObjectiveName` is the stock alias for native `SetName`.

The direct `curPilot = 0` assignments clear the pilot **class** pointer while
leaving the ambushers' AI active. They map to `SetPilotClass(h, "")`, rather than
`RemovePilot`, `KillPilot`, or nil (nil restores the default class). Supporting
native API evidence is `BZ1/1.5/functions/0045/0045efdb_SetPilotClass.c` in the
source repository, which assigns `GameObjectClass::Find(name)` to `curPilot`;
`0049/004998f6_GameObjectClass_Find.c` returns null for an empty class identifier.
This API evidence informs the translation only; all gameplay comes from the
requested DLL-source mission. Confirm blank-class behavior on the target BZR
build during in-game QA; the mocked tests cannot establish engine internals.

## Documented corrections

1. Setup's `i < 9` writes past the two four-entry audio arrays. Initialize
   exactly `NUM_MESSAGES`, retaining all intended initial flags and timing.
2. Completing deployment or Nav Alpha now cancels both future reminders and
   already-playing reminder handles. The source can re-arm a warning or fail
   after the objective is completed. Completion is checked before stale audio
   can fail that same frame. No deadline, distance threshold, spawn gate or
   delay is relaxed for an incomplete objective.
3. Missing/deleted handles never produce false proximity or invalid camera,
   naming, targeting, or AI calls. A missing camera subject releases the shot;
   attack-camera completion still spawns its original reinforcements.
4. A failure is latched, and recycler failure has precedence while its audio
   is playing. The original can issue success and failure for the same frame,
   or win when the recycler dies during congratulations. Successful defense
   keeps the same eleven enemy checks, audio gate and four-second delay.
5. Victory waits for the attack camera's pending pair to be spawned. If the
   camera lasts beyond wave 2 and existing enemies die, native null handles
   could otherwise count as dead reinforcements. The wave-2 clock is unchanged.

Each correction is also explained at its implementation site in Lua.

## Validation

Run from the repository root:

```sh
lua5.1 Tools/Test-BlackDog01.lua
python Tools/Test-BlackDog01SourceParity.py
```

The Lua host checks the public callbacks and recorded engine operations across
the full mission, both survivor branches, strict timer/range boundaries, all
failure descriptions/delays, both camera cancellations, late objective
completion, destruction races, missing handles, and save/load resumption.
The source audit checks the archived source hash, all referenced mission
identifiers, and retention of the disabled victory call. Both are automated
checks, not proof of actual game playback or asset availability.

In-game QA remains required for LuaMission map wiring, asset availability,
cloaked ambush AI/pilot classes, cinematic motion, simultaneous camera/audio,
and real engine save/load handle remapping. Existing map/assets are not shipped
or changed by this PR.
