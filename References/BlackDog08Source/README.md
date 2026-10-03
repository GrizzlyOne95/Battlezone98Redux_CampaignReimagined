# Black Dog 08 source port

`BlackDog08Mission.cpp` is the complete upstream file from
`GrizzlyOne95/Battlezone_Source/BZ1/from_bz2_dll_src`, Git blob
`f0fbb7371b4a584a4852889e1f33f741ad11695a`. It retains the original bytes,
including CRLF line endings, every comment, native serialization, the disabled
`TEST_PORTAL` variant, and the commented factory-loss condition.

The standalone Lua 5.1 port is `Scripts/bdmisn08.lua`, targeting stock BZR 2.1+
portal APIs. It keeps the two cinematics, weighted portal attackers, APC arrival,
nine-minute portal reprogramming, pilot return, 25-second APC departure delay,
capture latch, all three failure descriptors, and original outcome ordering.

The stock `RemovePilot`/`GetIn` APIs replace direct native pilot-field writes and
`AiProcess::Attach`. Boarding is asynchronous: the return timer still starts at
pilot/APC contact, and the pilot is retained until the engine consumes it.
The extra `pilotBoarding` state survives save/load. A capture while boarding is
pending cancels that scripted handoff. The exact boarding behavior, command
restoration after an in-game save, and collision tolerance require BZR testing;
mock-host tests do not reproduce engine physics or AI attachment.

Documented fixes avoid invalid-handle operations after destruction or failed
builds. A failed APC spawn uses the existing APC-loss outcome rather than leaving
an impossible capture objective. A dead pilot cannot satisfy portal contact.
These affect invalid/destroyed-object cases and preserve normal timers and gates.

`TEST_PORTAL` remains false, matching the commented-out source define. The retained
test variant disguises the player, disables attacker waves, and substitutes the
two original fifteen-second timers. It does not change shipped gameplay.

Run from the repository root:

```sh
lua5.1 Tools/Test-BlackDog08.lua
python Tools/Test-BlackDog08SourceParity.py
```

This change supplies a reviewable source port. Mission map bindings, shipping
configuration, asset deployment, and in-game qualification are not included.
