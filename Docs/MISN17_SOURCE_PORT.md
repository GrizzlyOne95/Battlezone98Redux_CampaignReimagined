# misn17 DLL-source Lua port

`Scripts/misn17.lua` ports `BZ1/from_bz2_dll_src/Misn17Mission.cpp` to stock Battlezone 98 Redux Lua 5.1. It needs no EXU, OpenShim, or Campaign Reimagined helper module. This is a script/source checkpoint; it does not change map registration, package locks, or installed missions.

Source repository: [Battlezone_Source](https://github.com/GrizzlyOne95/Battlezone_Source/tree/e7c410573ffedc9e118dd90f402af6d5585955cc/BZ1/from_bz2_dll_src), commit `e7c410573ffedc9e118dd90f402af6d5585955cc`.

| Archived file | Original Git blob |
| --- | --- |
| `References/Misn17Source/Misn17Mission.cpp` | `8a3dd976203e79ebae70d30329d4b737fa074764` |
| `References/Misn17Source/Misn17Mission.h` | `3a567da6ed4802c11dd16caec001362e87956e9e` |

Both files retain their exact original bytes, including CRLF endings, all comments, native persistence, and the scrap-removal implementation. The DLL archive wraps the whole `Execute` body in `#if 0`; the Lua port activates that mission body. Its inner commented alternatives stay disabled in long Lua comments at the corresponding locations. No community/Lua mission was used as the behavioral source.

## Preserved mission behavior

- Startup uses the original recycler/factory/part/nav labels, 40 scrap, `misn17.aip`, seven `hbptow` objectives, and `misn1701.wav`.
- The opening camera uses paths `cineractive1`, `2`, `3`, `5`, `6`, `4`, `7` with the original targets, heights and speeds. Independent sequential `if` statements preserve same-update transitions; camera 1 is still evaluated after cameras 2–7. Voice completion or cancellation ends the opening.
- Each tower checks after 3 seconds and then every 2 seconds. An enemy strictly within 400 m triggers two one-shot `hvsat` escorts. Their defend commands and retaliation checks remain in source order.
- `AddObject` retains the first five `avartl` handles without adding a team filter or recycling slots. A living registered artillery piece gets a replacing `hvsav` counter at `counter` whenever its counter dies. Artillery registered before `Start` survives startup.
- Factory waves begin strictly after 10, 100, 220 and 340 seconds, then repeat every 400 seconds from the current update time. Factory 2 spawns `hvsav`; the others spawn `hvsat`. Valid wreck objects retain source spawn behavior; removed references are safely skipped.
- Factory-approach checks begin after 30 seconds and repeat every 5 seconds. An enemy strictly within 450 m of `savspawn`, point **1**, triggers four defenders with the original factory assignments.
- The proximity mine check begins after 10 seconds and retries every 3 seconds, using the nearest enemy of factory 2 and strict 610 m comparisons to `pt1`, `pt2`, `pt3`. It builds the complete ordered `mine1`–`mine53` field once.
- Each destroyed tower gets a neutral `eggeizr1` replacement. Losing all seven towers creates the minefield if needed, invokes stock `GetRidOfSomeScrap()` only on that fallback branch, and starts `misn1730.wav` plus `minecin`. Factory objectives refresh on the following update, as in the source.
- Mine destruction keeps the original initial no-op update followed by one mine per update through mine 53. Skipping the cinematic ends the camera/audio while mine destruction continues. Completion of the mine voice also ends the cinematic.
- Recycler loss requests failure after 20 seconds with `misn17l1.des` and `misn1704.wav`.
- Destruction of all three factory parts requests success after 4 seconds with `misn17w1.des` and `misn1703.wav`, the original victory camera, and visual-factory explosions strictly after 1.0, 2.5 and 3.2 seconds (factory 2, 4, 3).
- All 64 bools, 34 floats, 141 native handle slots (represented by individual fields plus a mine table), and 3 integers are represented, including unused crystal/camera/dispatch state. `Save`/`Load` restore the full state without replaying startup or retiming events.

## Local corrections and BZR adaptations

| Source issue | Correction and effect on flow |
| --- | --- |
| `Handle MINE[53]` declares indices 0–52, but the mission writes 1–53 and `Setup` writes index 53. The next member is `mineaudio`; starting that audio overwrites the stored last mine. | Use a Lua table with actual mine keys 1–53. No neighboring state is overwritten, and the last mine remains addressable. Preserve the original index-zero no-op and 54-update sweep, while never damaging an unbuilt entry. |
| Both minefield branches reference `" mine10"`. | Remove the accidental leading space in both branches. Mine 10 uses its authored path in the same spawn order. |
| Defender `deftow7a` stores its shooter in `badman13`, then attacks `badman14`. | Attack `badman13`. Only that defender's wrong target changes; mission gates and timers stay intact. |
| All three factory-part replacements spell the geyser `eggiezr1`. | Use `eggeizr1`, matching the tower replacements, final camera object, and repository geyser asset name. Restore the intended visual replacement without changing part-completion tests. |
| Tower `Defend2` calls pass priority `1000`. | Use the documented BZR uncommandable priority `1`, preserving defend targets and player commandability. |
| Missing nearest enemies, removed factories/shooters, or already-detonated mines can supply invalid handles to Lua overloads. | Guard those operations. Missing proximity targets remain outside the triggers; failed/removed references do not pause the original checks, one-shot flags, or destruction cadence. A removed cinematic target skips its shot; normal shots retain their original behavior. |

Every correction is explained inline. Original faulty lines remain in the exact source archive.

## Source quirks deliberately retained

`waveattacks = GetTime() + 1800` and `camdone = GetTime() + 35` are assigned but never tested; they do not create an extra wave or force a camera timeout. Crystal-processing members exist without executable crystal logic in this file. The commented two-shot cinematic and `PanDone` alternatives remain recoverable.

Victory tests factory parts without requiring tower completion. The source has independent failure and success guards, so simultaneous recycler loss and destruction of all parts request both outcomes, in failure-then-success order. Their eventual engine precedence needs an in-game check; introducing a new outcome gate would change gameplay and is outside this faithful port.

The source does not always request an objective repaint at victory and does not stop recurring waves at victory. Those behaviors remain intact. No extra gameplay audio, hints, units or camera paths were invented from the unused members.

## Validation

Run from the repository root:

```sh
lua5.1 Tools/Test-Misn17.lua
python3 Tools/Test-Misn17SourceParity.py
```

Validated with Lua 5.1.5: **141 simulated-host checks** and **241 source-preservation/coverage checks**. The latter verify exact archive Git hashes, every inline source comment in the ported methods, all native state declarations, gameplay call counts and string arguments, both complete ordered minefields, and specific bug corrections. They check structural coverage; the host scenarios check event behavior.

In-game validation remains outstanding: load the original mission data through LuaMission, confirm authored paths/labels and stock dependencies, exercise both minefield triggers and cinematic skips, save/load during the mine sweep and finale, and verify native AI/voice/camera behavior. Actual engine handle/message restoration and scrap selection are engine-owned and are not proven by a simulated host. No map or shipping-lock blessing is included in this checkpoint.
