# Chinese Mission 02 Lua port

`Scripts/ch02.lua` ports `Chinese02Mission.cpp` to stock BZR 2.1 / Lua 5.1.
Source: <https://github.com/GrizzlyOne95/Battlezone_Source/blob/main/BZ1/from_bz2_dll_src/Chinese02Mission.cpp>
The archived source is byte-identical to Git blob
`a73b6107b9e22c7073d36f9e102322c360c511ca`, including CRLF, declarations,
serialization, every comment and the `#if 0` block.

## Fidelity and cut content

- Original update order, strict `< GetTime()` deadlines, resources, audio,
  objectives, wave composition, path/label spelling and command priorities
  are retained. `hanger`/`hanger_attack_*` are map labels, not typos to fix.
- Arrays retain zero-based C++ indexes. The unused objective flags, second
  camera slot, factory handle and `apcArrived` flags remain in state. The source
  never sets `apcArrived`; the port does not invent unload/arrival processing.
- One living APC within 30 m of the hangar starts victory, provided defeat has
  not already occurred. Two APC deaths before victory trigger defeat. The
  30-second cockpit timer is a display, not an additional victory requirement:
  success follows completion of `ch02005.wav` plus one second, as in source.
- The disabled `walker_attack_1` ambush is translated in a Lua long comment.
  The alternative heavy-razor spawns and early `ch02008.wav` call remain
  commented beside their original locations. Original C++ is preserved here.
- `Save`/`Load` preserve the complete state, including handle/audio values and
  timers. Loading does not replay Setup, spawn waves or restart cinematics.

## Documented fixes and API adaptations

Inline `PORT FIX` comments explain each intentional repair:

1. Guard NULL/deleted health and distance arguments, and pre-audio camera
   cancellation. Valid-object behavior and original timer comparisons remain.
2. Only living APCs satisfy proximity triggers; wrecks cannot trigger an
   ambush or win. The source's trigger radii and one-APC victory rule remain.
3. Suppress victory scheduling after defeat. Native loss checks precede the
   unguarded arrival block, allowing contradictory results in one frame.
4. Retain convoy attack spawns but omit `Goto` when no living APC destination
   exists. Attacks with a live target retain independent random selection and
   priority 1; there is no new fallback attack command.

Native `enableAllCloaking(FALSE)` becomes stock `EnableAllCloaking(false)`.
Native `Recycle(walker)` becomes `SetCommand(walker, AiCommand.RECYCLE, 1)`.
Uniform `math.random` target choice replaces `rand() % count`; exact native
random sequences are not promised.

**Known fidelity limit:** the mission source does not define
`isAtEndOfPath`. The Lua port uses stock `GetPathPointCount` and `GetDistance`
with the final zero-based waypoint and a provisional 25 m radius. This is an
explicit approximation requiring comparison on the original map, not a
recovered native constant. A missing path or dead walker cannot count as
arrival. No EXU/OpenShim/helper dependency is introduced.

## Validation and integration

Run `python Tools/test_ch02.py` with `lupa` installed (uses `lupa.lua51`).
The mocked engine tests cover the cinematic, strict timer boundaries, full
wave timeline, escort orders, disabled ambush, walker escape/recycle and loss,
convoy damage/ambushes, all mission results, wreck/null handling, base/live APC
targeting, source hash, and save/load without duplicate events.

This is a standalone port: no mission map/TRN, ODF, objective or audio asset
is edited or manufactured. In-game integration must verify the `ch02` map
loads this script, all source labels/paths/assets exist, neutral walker
perceived-team/retreat and recycling behavior match, and tune the provisional
path-end radius against native behavior. Mock tests do not validate movement,
AI, cinematic motion, audio playback or engine serialization.
