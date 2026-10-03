# misns3 stock Lua source port

`Scripts/misns3.lua` ports `Setup`, the empty `AddObject`, and `Execute` from the
native DLL source in `References/Misns3Source`. It targets stock BZR and Lua 5.1,
without EXU, OpenShim, or campaign helper dependencies. It does not change map
bindings or deploy mission files.

The port includes the opening briefing and objective, 120/280/380-second pleas,
600-second withdrawal deadline, 200m initial defender trigger, repeating three
tanks/two fighters, four retreat routes, eight proximity-spawned escorts,
200m return-home victory, both 50m warning triggers, both bomber/player patrol
routes, and all 34 mines across three fields. Audio completion gates victory
and both failure outcomes. Every unused native state member remains declared.

Preserved details that should not be silently changed:

- The three distance/alive poll deadlines are **integer** members in C++.
  `math.floor` preserves their truncation even when simulation time is fractional.
  Startup polls are five/five/fifteen seconds; subsequent polls are three/three/eight.
- Replacement defenders receive no explicit attack until the next alive poll.
- Patrol detection sets the same `bdspawned` flag used for defender replacement.
  A detected patrol can therefore activate defenders without the 200m trigger.
- Patrol route tests and nearest-enemy tests are independent. Both routes can
  spawn during one poll, and the second detected enemy can override the first.
- Recycler destruction runs after defender polling and before patrol detection.
  Existing defenders keep their orders; no new removal/retreat commands are added.
- Recycler objectives refresh on the next update. Minefields remain active in
  both phases. Retreat groups expand at strictly less than 410m.
- Failure radio flags remain latched if the recycler dies afterward. Terminal
  mission calls retain source order and repetition; no new win/loss arbitration
  or one-shot outcome gate is introduced.

Inline `PORT FIX` comments explain these limited corrections:

| Correction | Why mission flow stays the same |
| --- | --- |
| Represent oversized initial integer timer literals as Lua numbers | Startup overwrites them before any timer test; active deadlines still truncate. |
| Guard missing/deleted handles, failed spawns, and missing nearest enemies | Valid-object distances, orders, thresholds, and spawn timing are unchanged. |
| Skip naming missing navigation markers | Only avoids the source's unconditional object dereference. |
| Retain five discarded `IsAlive(bd1)` calls as comments | Their return values never affect mission state. |
| Refresh the completed home-return objective and update its existing slot | Repairs the source's missing refresh/duplicate green slot; the return and audio success prerequisites are unchanged. |

The complete `.cpp`/`.h` archive preserves all comments and cut-content evidence
byte-for-byte. There are no disabled gameplay blocks in this particular source.

`Save` returns the state table; `Load` restores it. Stock LuaMission serializes
the tables, object handles, and message values. Load does not replay startup,
reset deadlines, or recreate waves, patrols, escorts, or mines.

Validation commands, run from the repository root:

```text
lua5.1 Tools/Test-Misns3.lua
python3 Tools/Test-Misns3SourceParity.py
```

The Lua mock host verifies boundaries, composition, command order, interactions,
invalid handles, and save/load continuation. The source audit checks exact Git
blobs, all state fields, comments, active identifiers (including expanded mine
paths), stock API availability, and integer timer conversion. These checks do
not prove in-engine behavior. BZR playtesting remains necessary for path travel,
audio availability, actual save/load userdata restoration, and objective display.

The new script is source only. Shipping-lock blessing and selecting LuaMission
in the intended mission map are separate integration steps; no shipping lock,
existing map, or native mission binding was changed here.
