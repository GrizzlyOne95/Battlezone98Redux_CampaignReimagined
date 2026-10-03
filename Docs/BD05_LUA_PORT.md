# BlackDog05 Lua source port

`Scripts/bd05.lua` ports `BlackDog05Mission.cpp` to stock BZR 2.1+ and Lua 5.1.
It uses no EXU, OpenShim or campaign helper APIs. Native source provenance and
an exact snapshot are in `References/BlackDog05Source/`.

## Preserved behavior

- Initialize team 1 to 8 scrap and 10 pilots on the first Update.
- Opening camera: `camera_start_arc`, height 3000, speed 2000, recycler target;
  `bd05001.wav`, cancellation stops the intro audio.
- Initialize timers during the opening camera, not after it. Radio at 240 s;
  front waves at 300/540/840/1140 s; artillery at 420 s; rear waves at 450/660 s.
  Every check uses the source's strict `< GetTime()` comparison.
- Keep the initial 15 map units and all 31 spawned reinforcements in the
  original zero-based slots. Preserve every ODF, path, cloak call, target and
  priority, including Goto versus Attack. Preserve Execute block ordering.
- After the fourth wave, require all 46 tracked enemies dead before
  `bd05004.wav`, six retreaters, inward portal activation and `bd05005.wav`.
- Remove retreaters on portal contact; clear dead handles. Do not require all
  six gone for victory: the native `allGone` branch is empty.
- Retreat camera: `camera_retreat`, height 3000, speed 0, portal target. Require
  both 15 seconds from camera start and 3 seconds after narration finishes;
  cancellation can finish immediately and leaves the retreat audio playing.
- Play `bd05006.wav` after the movie and await completion before success.
- Keep unused native state (`numBombers`, `whichTimer`, `bomberTime`,
  `portalTime`, `portalStage`, `lost`) for reconstruction and save/load.
- Keep all commented/cut code. No seven-unit build gate or 40-minute timer is
  re-enabled. No scripted loss condition is invented; the source has none.

## Documented fixes and adaptations

1. **Unreachable victory:** the only assignment completing objective 1 was in
   disabled construction/debug code, while active victory still required it.
   Complete objective 1 alongside the existing all-46-enemies-dead event. This
   makes the objective green and repairs the victory blocker without adding a
   construction requirement or changing waves, retreat, camera or audio gates.
2. **Absolute success time:** stock Lua `SucceedMission` takes an absolute time.
   Replace native `0.1` with `GetTime() + 0.1` after final narration. The intended
   short completion delay is preserved at the same point in the sequence.
3. **Null/deleted handles:** guard spawn commands, contact queries, portal and
   camera calls. A missing camera subject takes the existing completion path.
   Correct map objects and successful spawns retain their original behavior.
4. **Missing narration:** nil retreat audio is treated as already complete,
   retaining the 15-second minimum and 3-second post-audio delay. Nil final
   audio schedules success once. Existing narration still uses the source's
   completion checks; missing files no longer leave victory permanently stuck.
5. **Native API names:** `activatePortal(portal, true)` maps to `PortalIn`;
   native `isTouching` maps to stock `IsTouching`. Cloak remains `SetCloaked`.
6. **Serialization:** Save returns the mission-state table; Load restores it.
   LuaMission handles serialization/remapping, replacing native unions and
   `ConvertHandle`. Load does not call Setup or replay events.

Each behavioral fix is explained at its point of use in the Lua script.

## Validation and integration

Run from the repository root:

```sh
lua5.1 Tools/Test-BlackDog05.lua
python Tools/Test-BlackDog05SourceParity.py
```

The stub harness covers startup, cancellation, strict wave boundaries, every
unit's spawn/order/cloak, initial and reinforcement completion blockers,
retreat contacts, timing, victory without the cut build gate, missing audio,
invalid handles, and save/load during both cameras and final audio.

These checks do not simulate engine AI, collision geometry, portal effects,
camera paths or engine handle/message restoration. In-game qualification is
still required on the original `bd05` map with its stock assets. This change
adds the script and review/test artifacts; it does not modify a mission map or
the shipping lock. Bind `bd05.lua` through the original map's Lua mission
configuration when integrating the port.
