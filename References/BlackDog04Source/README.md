# Black Dog 04 source port

`Scripts/bd04.lua` is the stock BZR 2.1+ / Lua 5.1 port of
[`BlackDog04Mission.cpp`](https://github.com/GrizzlyOne95/Battlezone_Source/blob/main/BZ1/from_bz2_dll_src/BlackDog04Mission.cpp).
The archived file preserves the full source, including all comments, unused
state, native serialization, and disabled lines (only CRLF is normalized to LF).
Source Git blob: `d3d0ee442c4140050186402965d851e19a5ea7a1`.

Use `bd04.lua` with the original mission map and assets. This change adds the
script; it does not rewire another map or ship replacement mission assets.
`Docs/BZR_LUA_AGENT_REFERENCE.md` is the stock API authority. There is no
EXU, OpenShim, or Campaign Reimagined helper dependency.

Mappings: native `isIn(user, "base_limit")` becomes
`IsInsideArea("base_limit", user)`; native `activatePortal(portal, false)`
becomes `PortalOut(portal)`; `deactivatePortal` becomes `DeactivatePortal`;
`SetName` uses its stock `SetObjectiveName` alias. Arrays retain source indices.
The Lua state table replaces native member-array serialization and PostLoad
handle conversion using LuaMission's serializer. Empty AddObject is retained.

The source's three disabled lines are also preserved inline: `doAttack = FALSE`
and both `SetUserTarget(navBeacon)` calls. Unused silo/fightersSpawned/third
camera state remains unused; no cut behavior has been activated.

Documented port fixes:

- Latch the 60-second timeout warning once, so repeated frames cannot replace
  sound5 indefinitely and prevent sound6/attack from following.
- Require the final drop-zone beacon before the 50m victory test. The source
  tests a null beacon before pickup and the temporary rv_scout beacon before
  the 30-second bomber event. The intended extraction event/radius is retained;
  accidental early victories at that temporary beacon are intentionally removed.
- Schedule success at `GetTime() + 0.1` after congratulations; stock mission
  outcomes use absolute time, and the source's `0.1` is already in the past.
- Guard missing/deleted handles and absent messages, including nil cargo/player
  equality and camera subjects. Working-map behavior and spawn counts remain
  unchanged; unusable cameras finish through their normal completion actions.

Preserved quirks: the trigger_1 disguise flag stays latched, base entry is only
checked once, escorts receive no explicit commands, route ambushes are not
gated on fragment pickup, portal-camera cancellation does not cancel scheduled
portal fighters, and portal loss is evaluated after the source victory check.
No new portal-loss precedence or strategic-AI behavior is introduced.

Validation: `lua5.1 Tools/Test-BlackDog04.lua` runs a strict mock host covering
cinematics, cancellation, portal timing, disguise/base-entry branches, timeout
audio progression, inspection, extraction waves, route ambushes, terminal
outcomes, and save/load. `python Tools/Test-BlackDog04SourceParity.py` compares
source assets and disabled code. Engine path geometry, portal physics, map
labels/assets, and live savegame behavior still require in-game testing.
