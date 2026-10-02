# misn08 source port

`Scripts/misn08.lua` ports the original BZ1 DLL mission in
`Battlezone_Source/BZ1/from_bz2_dll_src/Misn08Mission.cpp` to stock
Battlezone 98 Redux Lua 5.1. This is a single-player script checkpoint.
It does not use a community mission, another Lua mission's gameplay,
aiCore, EXU, or OpenShim as behavioral authority.

Source C++ blob: `d1581e4d62251a9a452e26c30fee162a90cf9571`.
The accompanying header contains only its include guard.

## Preserved behavior and cut content

- Opening objectives, scrap, initial walker weapon masks, and navigation names.
- Fighter waves, early-player acceleration, the Colorado walker attack,
  radio sequence, destruction, nav removal, and delayed general's message.
- Both early walker discoveries, their asymmetric followup delays,
  encounters with the other walker, and both trigger/nav warning branches.
- Walker paths, arrival target priorities, popper thresholds and weapon masks.
- Native strategic AI and its 420-second fighter/tank composition AIP changes.
- Factory-deployment objective, APC target priorities, relic reconnaissance,
  both relic/base victory orders, and recycler-loss failure.
- All 44 booleans, 33 timers, 41 handle slots, and two counters, including
  dormant state. Unset handles use Lua `nil`.

The disabled third-walker movement and close-range warning blocks are
translated into Lua long comments at their original positions. The disabled
dropoff lookup, player-pilot grant, and Colorado/dropoff removal calls remain
as Lua line comments. Enabling them is a separate cut-content reconstruction
decision; none runs in this port.

The end of the Lua file contains the **entire original C++ source** in one
long comment, LF-normalized but otherwise verbatim. It preserves every
original comment, disabled statement, state declaration, and native
serialization wrapper for comparison and reconstruction.

## Explicit adaptations

| Source | Lua port |
| --- | --- |
| `Get_Time()` / `GetTime()` | Stock `GetTime()` |
| Object `SetName`, `GetHealth`, `AddHealth`, factory `IsDeployed` | Stock Lua wrappers |
| `WHITE` / `GREEN` | `"white"` / `"green"` |
| Native save arrays and `ConvertHandle` | `Save`/`Load` table of primitive and game values; LuaMission serialization |
| `AiMission` strategic AI | `SetAIControl(2, true)` in `Start`, source AIP calls retained |
| Setup before native map-object loading | Setup in `Start`, then one `AllObjects` scan through `AddObject` to recover startup object notifications |
| APC branch assigns `nsdfmuf = h` | Corrected to `ccaapc = h`, annotated in place |
| Second tower branch assigns `guntower1 = h` | Corrected to `guntower2 = h`, annotated in place |

Only those two unambiguous handle-assignment typos are repaired. The original
spellings remain in the source archive.

## Deliberately retained source quirks

- Two Colorado reinforcements overwrite `svpatrol2_2` consecutively.
  Both spawn; the fighter loses its tracked slot. This is not silently
  changed to `svpatrol2_3`.
- `next_second` and `next_second2` start at 99999. The healing code
  therefore does not protect Colorado/the relic during ordinary mission
  timing. The sentinel has not been changed to zero.
- Discovery sets arrival-check times to absolute 100/105, not offsets.
- The third walker starts on `gech_path2` after the bad-news message,
  but its separate arrival timer stays dormant because its setup block is cut.
- Dead APC/factory/tower handles are not automatically cleared/replaced.
- Success and failure checks retain source order and independent guards;
  simultaneous loss/victory is not redesigned.
- Team/class filtering is not added to `AddObject`.

## Validation

Run from the repository root with a Lua 5.1 interpreter:

```sh
lua5.1 Tools/Test-Misn08.lua
```

52 mock-engine checks pass. They cover strict timer boundaries, Colorado's
distance gate and timeline, startup object recovery, warning/discovery
branches, native AIP selection, popper behavior, corrected APC tracking,
both victory orders, one-shot failure, and save/load continuation.

The script and both translated cut-content blocks parse under actual Lua 5.1.
The repository validator's targeted Lua checks pass without warnings.
The embedded C++ archive was compared to the retrieved source and matches
after newline normalization.

These checks do not exercise actual strategic AI, navigation, audio queues,
handle remapping, or asset availability in the Redux executable.

## Integration and in-game checks still required

Main currently has no `Missions/misn08.bzn` package. This checkpoint adds
the script, test, and notes; it does not create a map, modify mission dispatch,
bless the shipping lock, or deploy.

Use the original mission's map labels and paths, including:

- `avrecycle`, `svrecycle`, `svmuf`, `sovgech1`, `sovgech2`,
  `colorado`, `cam1`, `cam2`, `cam5`.
- `giez_spawn2`, `giez_spawn3`, `stop_geyser1/2/3`,
  `attack_geyser`, `ccarecycle_geyser`, `death_scrap/2/3`.
- `svpatrol1_1/2/3`, `svpatrol2_1/2/3`,
  `hbblde1_i76building`, `hbbldf1_i76building`, `hbcerb1_i76building`.
- Paths `gech_path1`, `gech_path2`, `gech_spawn`,
  `cam2_spawn`, `cam3_spawn`.

Keep the original `avmu8` factory class, `svapc`, `abtowe`,
`svfigh`, `svltnk`, `svwalk`, and `apcamr` definitions available.
The mission also requires `misn08.aip`, `misn08a.aip`, `misn08b.aip`,
its referenced OTF/WAV assets (including source `misn0421.wav`),
and `misn08w1.des` / `misn08f1.des`.

In Redux, verify AI production after Colorado's destruction, actual walker
routes and weapon transitions, each warning order, map factory discovery,
both objective completion orders, and save/load during the Colorado radio
sequence. Confirm native handle remapping without repeating opening events.
