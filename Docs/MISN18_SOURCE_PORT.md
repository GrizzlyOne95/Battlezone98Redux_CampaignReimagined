# misn18 DLL source port

`Scripts/misn18.lua` ports the original `Misn18Mission` to stock Battlezone 98
Redux Lua 5.1. It uses no Campaign Reimagined helper, EXU, or OpenShim APIs.

Source: [Battlezone_Source at e7c410573ffedc9e118dd90f402af6d5585955cc](https://github.com/GrizzlyOne95/Battlezone_Source/tree/e7c410573ffedc9e118dd90f402af6d5585955cc/BZ1/from_bz2_dll_src).
The original C++ and header are preserved byte-for-byte in
`References/Misn18Source/`, including native serialization and every comment.
The Lua file also retains all ten original Setup/Execute comments verbatim at
their corresponding locations. These include the disabled earthquake pulse,
three `PanDone()` alternatives, and two additional return-wave units.
All 124 native state fields remain available, including unused wave handles.

The port retains the opening camera sequence, approach and shortcut triggers,
150/230/310-second reinforcements, four transport thrusters, discovery-triggered
recycler attack waves, wrong-route ambushes, return wave, three-minute escape
countdown, progress/hurry voices, objectives, victory, and all three failures.
Lua `Save`/`Load` persist the mission state table without replaying initialization.

## API adaptations and fix

- Native `GetObj(...)->SetName` becomes `SetObjectiveName`; native `AddHealth`
  becomes the stock Lua `AddHealth` wrapper. Objective colors become strings.
- Null object handles initialize to `nil`; voice playback uses the stock
  `AudioMessage` token rather than storing it as a C++ integer handle.
- The documented `Distance` guard returns infinity for missing/removed object
  handles. The source queries its initially-null enemy and can retain a removed
  enemy between polls. The guard keeps proximity triggers false in those cases
  and leaves valid distances, thresholds, spawn routes, and deadlines unchanged.

## Source behavior deliberately retained

- The transport heals by 100 per update after discovery; thrusters stop healing.
  Before discovery they share the source healing timer. Changing this cadence
  would alter combat difficulty.
- Camera height counters change per update. Path completion and narration
  completion remain separate, including the source cancellation cleanup.
- Once recycler attack waves activate, all-four-dead replacements continue
  after transport destruction. Destroying the transport before activation
  prevents the initial wave.
- Timer failure requires distance greater than 400 m; victory requires less
  than 200 m. The intervening band and independent outcome latches remain.
- Simultaneous thruster losses can skip intermediate progress messages. The
  recycler-loss voice really is `misn1704.wav` in the DLL source.
- Objective refresh and hull destruction retain their source update order,
  including the extra approach objective if demolition happens before discovery.

## Validation and integration

Run from the repository root:

```sh
lua5.1 Tools/Test-Misn18.lua
python Tools/Test-Misn18SourceParity.py
```

The Lua 5.1 host suite passes 163 checks covering trigger routes, strict timer
boundaries, waves, healing, cameras, destruction, voices, objectives, outcomes,
invalid handles, and saved-state restoration. The parity audit checks exact
snapshot hashes, all original mission comments, all 124 fields, 137 ordered
string references, Setup assignments, and all 2,068 adapted active logic tokens.
The new Lua files also pass the campaign validator's Lua/API/filename rules.

This change supplies the script and audit files. It does not change a mission
map, the shipping lock, or installed content. In-game validation still needs
the original misn18 map labels/paths and stock assets, the map configured to
load this Lua mission, and checks of native AI, camera rendering, earthquake,
timer UI, audio, and engine save/load handle restoration.
