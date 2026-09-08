# Mission 04 interactive fog test

`Scripts/misn04.lua` auto-enables a stationary 384 m square fog bank around the local player four simulation seconds after Start or Load. The floor is the terrain height at placement; the layer is 10 m high. This is a deliberately local test bank, not terrain-following fog across the map.

- **F8** toggles fog off/on.
- **F9** enables and moves a fresh bank to the current player location.
- Drive through the bank, look behind, and observe recovery over about 12 seconds with a slight wind drift.
- Existing F6/F7 feature probes retain their controls.

Requires the matching EXU/OpenShim fog bridge and renderer. Older builds log one unavailable message and continue the mission. Configuration feedback does not establish rendering: a separate status message reports whether the renderer is ready. Check the native log if it remains unavailable.

Only the enabled preference is saved. Loading recreates the bank at the current player and clears native wake history. The system observes up to 128 nearby craft at 20 Hz using simulation time. Deleted or departing craft are removed from native tracking; handle reuse receives a fresh numeric token. Pauses do not age fog.

Author check: run `Tools/Test-Misn04FogWakes.lua` from the campaign root with Lua 5.1. It compiles the whole mission and exercises the isolated actual system with mocked natives: startup delay, pause/cadence, reset/clock rewind, key latches, disabled saves, unavailable APIs, failed native calls and handle deletion/reuse. Passing this test does not establish in-game visuals, performance or platform compatibility. Runtime validation is still required on the supported matrix.
