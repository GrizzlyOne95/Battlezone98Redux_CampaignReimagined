# BlackDog06 Lua source port

`Scripts/bd06.lua` ports `blackdog06mission.cpp` to stock BZR 2.1+ / Lua 5.1.
It uses stock API and Lua's standard `math.random`; it needs no EXU, OpenShim
or Campaign Reimagined helpers. Source provenance and the complete exact
snapshot are in `References/BlackDog06Source/`.

## Preserved mission

- All native state numbers, Execute ordering, zero-based arrays, strict timer
  comparisons, ODFs, paths, objectives, narration and result descriptors.
- Opening camera and both deliberate switch fallthroughs. Initial resources
  remain 75 scrap / 10 pilots. The 11-minute deadline starts after the opening
  camera and is checked only while waiting for the six designated targets.
- Ten decoys move on `fake_attack` and are removed after their camera. Damaging
  them during WAITING1 triggers the early-attack loss; the friendly tank damage
  check remains disabled.
- After all six targets die: replacements after 90 seconds, the two-tank wave
  after another 90 seconds, and the three-tank wave 180 seconds after tank 0
  dies. The two-tank wave deliberately checks ONLY its first tank.
- Portal waves begin after 80 seconds, materialize two random units one second
  into the effect, close after two seconds, then schedule another 80 seconds.
  Five ground hunters recur every 110 seconds. Both continue after portal
  capture, as in the source. Spawn probabilities and commands are preserved.
- After the three-tank wave dies, narration gates a recycler and two escorts.
  Objective 2 follows after 30 seconds. The recycler deploys once its command
  is NONE. The third attack is five tanks on the NEXT Update: the native +60
  assignment is unused and has not been turned into a new delay.
- Any original `bvapc` object within strictly 100 m of `apc_in` captures the
  portal after the recycler exists. No new team restriction is imposed.
  Capture spawns three artillery; entry removes the APC, plays bd06009, and
  starts 60 seconds inside the portal. Seven dummy tanks follow the narration;
  seven fighters attack five seconds after the end camera. The return APC
  goes to `apc_out`; command NONE schedules victory ten seconds later.
- The four source losses, unused `randomAttack` / `recyclerDropped`, and all
  cut code remain available. The alternate victory and cockpit timer are inert.

## Fixes and API adaptations

Inline `PORT FIX` comments explain the changed conditions and their effects.

1. Bound the replacement count to ten tanks. The native OR condition reads
   past the array when exactly five are dead. Retain 0..10 replacements; do
   not infer a five-unit cap. Wave timing, routes and state flow are unchanged.
2. Enter recycler-loss narration once. Restarting it every frame prevented
   the audio completion gate reaching failure. Keep the same loss sequence.
3. Guard destroyed health/camera/command subjects. A destroyed decoy counts as
   damaged; a removed entry APC uses the portal as camera subject; a missing
   fake-camera subject finishes that existing shot. A missing exit APC cannot
   falsely satisfy command NONE. No extra loss condition is introduced.
4. Return immediately after portal loss to prevent a success or portal spawn
   on the same Update. Keep the existing descriptor and two-second delay.
5. Complete the APC entry/removal/narration sequence even if CameraPath arrives
   before entry finishes. This prevents skipping entry and using the obsolete
   11-minute timer for return. The camera still exits at its original gate;
   normal entry, narration, attacks and return retain their original timing.
6. Treat nil narration as completed at its original completion gate. Actual
   audio continues to govern the same transitions and deadlines.
7. Reset the portal-wave timer after processing both unit slots. The native
   loop reset could make its second iteration use a negative elapsed time.
   A late first spawn still gets one Update before close, as in the source.
8. `Deploy(recycler)` replaces the native Recycler method. Stock Lua portal
   control is `PortalOut` plus `ActivatePortal` / `DeactivatePortal`: there is
   no exposed strength parameter. The two-second window and one-second spawn
   gate are kept, but the native per-frame strength ramp cannot be reproduced
   exactly through stock Lua. `BuildObjectAtPortal` retains engine spawning.
9. Save/Load preserve the state table without Setup or event replay. LuaMission
   serialization replaces the native packed unions and handle conversion.
   Random choices use the stock Lua generator, preserving probabilities rather
   than promising the same seeded sequence as the native C++ Random function.

## Validation and integration

```sh
lua5.1 Tools/Test-BlackDog06.lua
python Tools/Test-BlackDog06SourceParity.py
```

The Lua 5.1 stub harness covers the full mission, strict boundaries, waves,
replacements, all losses, APC detection/entry/return, early camera exit, missing
audio, invalid handles and save/load during several phases. The parity check
verifies the source archive, states, cut blocks, assets and spawn counts.

These tests do not simulate engine AI, ODF matching for producer-generated
variants, portal rendering, actual camera paths, deployment geometry or engine
handle/message restoration. Qualify those on the original bd06 map in BZR.
This PR adds the script and review artifacts; the map is not present in this
repository and its Lua binding / shipped-file lock are not modified.
