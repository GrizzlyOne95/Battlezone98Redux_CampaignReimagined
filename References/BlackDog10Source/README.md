# Black Dog 10 source and port

`Scripts/bdmisn10.lua` ports `BlackDog10Mission.cpp` to stock Battlezone 98 Redux Lua 5.1. The basename stays within the legacy eight-character convention. No campaign helper, EXU or OpenShim is needed.

Source: https://github.com/GrizzlyOne95/Battlezone_Source/blob/main/BZ1/from_bz2_dll_src/BlackDog10Mission.cpp

Upstream blob: `a1b4f90298b15f8c622f920e90ab5603c672b72e`. The archived file retains every source line and comment, with CRLF normalized to LF. The single disabled executable line, `//CameraFinish();`, is also retained in place in Lua. It leaves the final shot active during the one-second success transition; this is preserved rather than assumed to be a bug.

The port preserves all eight 400-meter ambush triggers and their 46 units, six target checks, 10-second nav delay, nav-audio completion gate, 5-second APC delay, 7-second APC camera, six captured tanks following the recycler at independence zero, and 10-second/audio-gated finale. Timers retain strict `< GetTime()` comparisons. Independent `if` blocks retain same-update transitions, including cancellation of the final camera immediately after cancelling the APC camera. No new failure condition is introduced for the APC, recycler or player.

The nil/deleted-handle health guard is explained beside the target check. It preserves native zero-health behavior without passing a missing Lua handle to the API. `NewState`, `Start`, `Save` and `Load` replace native member initialization, Setup and handle conversion; loaded flags, timers, object handles and audio messages are restored without replaying setup.

The path overload is `GetNearestUnitOnTeam(path, point, team)`, verified against the engine author's API reference: https://battlezone.videoventure.org/lua_script_utilities.html. The project's condensed nearest-query summary does not expand this overload. The mission uses point 0 and team 1 exactly as the C++ source does.

Validation: `python Tools/test_bdmisn10.py` (requires `lupa`, using its `lua51` runtime). Six mocked-engine regressions exercise ambush counts and boundaries, intro arrival/audio gating, cancellation, complete mission timing, reloads at each stage, single-shot victory, and missing/deleted targets. Tests compile and run the mission under actual Lua 5.1. They do not validate engine camera motion, AI pathing, audio serialization or map/asset availability.

In-game validation still requires the original map labels (`destroy_1` through `destroy_6`), ambush paths, camera and arrival paths, and original ODF/audio/objective/debrief assets. This change adds the script only; it does not rebind an existing map or substitute stock asset names with Campaign Reimagined variants.
