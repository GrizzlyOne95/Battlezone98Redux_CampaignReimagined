# Chinese mission 06 source port

`Scripts/ch06.lua` ports `Chinese06Mission.cpp` to stock Battlezone 98 Redux
Lua 5.1. The adjacent C++ file is byte-identical to upstream Git blob
`fb13ebac8532415ad2a8e3ad29677d1514087d6f` from
[Battlezone_Source](https://github.com/GrizzlyOne95/Battlezone_Source/blob/main/BZ1/from_bz2_dll_src/Chinese06Mission.cpp).
It preserves all declarations, comments, disabled code and native serialization.
The disabled debug tank spawn and traitor debug message also remain inline in Lua.

The port retains update order, strict timer comparisons, audio-driven delays,
resource changes, all three randomly selected reinforcement entries, twelve
disguised team-1 units with Soviet pilots, betrayal gates, independent random
base targets, the alternate-entry Soviet wave, PSU-controlled replenishment
raids and the original all-team-2-objects victory condition. Unused objective,
camera and alien flags are retained in saved state. Native pointers and NULL
become handles and nil; LuaMission handles save/load remapping.

Documented changes:

- Reset `moreRanTime` after its first wave. Upstream never resets it and spawns
  eight enemies per frame indefinitely. The original two-minute deadline, wave
  composition and entry selection are retained; the accidental flood is removed.
  This necessarily changes behavior after that first wave, but adds no new story
  stage, victory condition or recurring-wave cadence.
- Treat missing/deleted handles as zero health and avoid invalid mutation/attack
  calls. No target is invented when all bases are gone. Dead producers cannot
  activate raids through undefined distance results.
- Use `SetPilotClass` for native `curPilot`, `SetObjectiveName` for native
  `SetName`, and `AllObjects` for the full native object-list victory scan.
  No broken stock `ObjectiveObjects` iterator is used.

Run `python Tools/test_ch06.py` (requires `lupa.lua51`) for mocked Lua 5.1
regression checks. These do not replace BZR gameplay testing. Original map labels,
paths, ODFs, audio, objectives, debriefs and `chmisn06.aip` must be supplied by
mission integration; this change does not edit TRN/map files or enable the port.
In-game validation remains needed for disguise/pilot behavior, strategic AI,
navigation and engine save/load audio/handle serialization.
