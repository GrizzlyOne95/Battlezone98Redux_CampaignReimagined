# misn12 source port

`Scripts/misn12.lua` ports the original DLL mission to stock Battlezone 98 Redux
Lua 5.1. It uses no EXU, OpenShim, strategic-AI replacement, or campaign helper
modules. This change supplies the script; it does not modify a mission map,
select LuaMission in a TRN, deploy files, or bless the shipping lock.

## Source and preservation

The gameplay authority is
[Misn12Mission.cpp](https://github.com/GrizzlyOne95/Battlezone_Source/blob/main/BZ1/from_bz2_dll_src/Misn12Mission.cpp),
Git blob `547a9e0849cd16070060e31f26cf6aa8c4d14b61` (49,467 bytes).
The header blob is `65abfbd4adddbe22af8dbe589f11bd0d3c36d6da`.
Both files are retained byte-for-byte under `References/Misn12Source/`, including
CRLF line endings, native serialization, all comments, and disabled code.
No community mission or existing Lua mission was used as gameplay authority.

All comments from native `Setup` and `Execute` also appear beside the
corresponding Lua logic. Disabled native code stays disabled in Lua comments;
block comments retain C++ syntax so partial fragments remain reconstructable.
The Lua update retains all 180 source conditionals and their sequential order.
State retains all 92 booleans, 27 floats, 57 handle slots, and the audio-message
ID, including unused members. `Save`/`Load` preserve this serializable state
table; handle restoration belongs to LuaMission's engine serializer.

## Behavior

The port preserves the 1,200-second deadline, introductory and capture movies,
key-ship stop/wait/replacement cycle, disguised infiltration, checkpoint
acceptance and out-of-order recovery, patrol legs, warning escalation, tower
repair, guard waves, uplink noise, and nav-camera team switching.

Uplink begins below 60 metres, warns above 75 metres, breaks above 85 metres,
and takes 45 seconds. Reconnecting restarts the full interval. After completion,
the source delays return checks for 120 seconds and then polls every five
seconds; victory requires being within 75 metres of the drop-zone nav. These
values and strict `<`/`>` comparisons are unchanged.

Source quirks are retained where changing them could alter mission flow:

- Patrol routing uses `not real_bad or not game_blown`, as in the source.
- Guard replenishment checks guards 1–3 and can replace guard 4 while its old
  instance survives.
- Recovery from 3 to 2 sets `better_message` without setting `check2`; recovery
  from 2/4 to 3 sets `check4` without setting `check3`.
- Camera cancellation can advance all three capture shots during one update.
- Warning/escalation logic can continue after the uplink completes.
- Movies share `camera_time` with checkpoint responses.

## Corrections and API adaptations

The source's patrol-2_1 centre check commands **patrol-1_1** onto `path3`, then
updates patrol-2_1's routing flag. The Lua commands patrol-2_1 instead. This fixes
the mismatched actor; it preserves the same route, distance gate, ten-second
poll, and flag transition. The affected patrol movement changes as intended,
while checkpoint, warning, uplink, spawn, and outcome sequencing remains the
same. The original command and explanation are preserved inline.

Native object methods map to stock `AddHealth`, `AddAmmo`, `GetHealth`,
`SetTeamNum`, and `SetObjectiveName`. `Get_Time` maps to simulation `GetTime`.
The source `IsVehicleAlive` helper checks object existence, so the Lua uses
`IsValid` rather than substituting an alive/pilot test.

The native name setters only check a nonzero handle before dereferencing the
object pointer. The Lua checks `IsValid`, skipping removed nav/camera objects
without changing timers or flags. The distance wrapper treats missing objects
as infinitely far away, preventing nil from selecting an unintended stock API
overload. Valid-object distances and all thresholds remain unchanged.

## Validation

Run from the repository root:

```sh
lua5.1 Tools/Test-Misn12.lua
python Tools/Test-LuaCommentScan.py
```

105 scenario checks pass under an actual Lua 5.1 runtime. They cover strict
timer/distance boundaries, the empty key ship, capture, cinematics and cancel,
normal and recovery routes, identification/discovery, uplink interruption and
reconnection, failure paths, escape/victory, changed vehicles, corrected patrol
routing, camera ownership, removed camera pods, and save/load into a freshly
loaded script. Objective-panel checks enforce the stock ten-entry limit.

A source audit confirms all 175 original comments are preserved: gameplay
comments inline, and header/serialization comments in the full source copy.
Both archived files match their original Git blob hashes.

CI runs the mission scenarios and six comment-scanner regression tests. The
repository validator now recognizes Lua 5.1 long comments with matching `=`
delimiters, so preserved C++ is excluded from executable-Lua checks. This also
corrects the pre-existing false `goto` report inside misn07's disabled source;
the mission itself is unchanged. Real `goto`/label syntax after a comment still
remains visible to validation.

## In-game work remaining

Test with the original misn12 map and stock assets. Setup expects the original
map labels and paths verbatim; the mission-specific fighter is `svfi12.odf`.
Confirm LuaMission/TRN wiring separately before deployment. The host tests
cannot prove native AI motion, perceived-team behavior, real audio/camera
presentation, cockpit timer behavior, or engine handle conversion during a
saved-game load. Test those in BZR, including saving during the capture movie,
uplink, and escape. No in-game run or deployment was performed here.
