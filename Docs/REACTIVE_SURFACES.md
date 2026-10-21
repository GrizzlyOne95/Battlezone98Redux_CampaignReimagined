# Local reactive surface controller

`Scripts/CRSurfaceEffects.lua` is integrated with RuntimeEnhancements' existing
object registration and lifecycle. It chains EXU BulletInit/BulletHit callbacks;
callbacks only copy bounded events. Material work happens from Update.

The controller combines local cockpit hull damage and repair, real impact
anchors, smooth muzzle-local heat, wet/dry easing and actual gun-tower power.
CRWeather rain layers explicitly expose `surfaceWetness`; effects neither guess
from preset names nor change gameplay or send network messages.

## Budgets

| Work | Limit |
| --- | --- |
| Material controller tick | 50 ms; no catch-up loop |
| Event storage | 64 hits and 64 shots |
| Event consumption | 2 hits and 2 shots per tick |
| Tracked objects | 4,096, using existing registration |
| Cold discovery / shared rain | 4 objects / 16 material names per tick |
| Active object variants | 64 objects, with 8 heated craft |
| Anchors per craft | 2 impacts, 2 heated mounts |
| Material creation | 1 world subentity and 1 cockpit subentity per tick |
| Per-object material slots | 8 world, 16 cockpit |
| Combat event range | 260 metres from local player |

Hits last 16 seconds and fade over their last four seconds; health recovery also
clears accumulated marks. Wetting takes 2.5 seconds and drying 10 seconds as
exponential time constants. Heat accumulates from accepted shots and cools
smoothly. Missing native mount data suppresses heat rather than guessing.
Shared material lookup uses Autodetect; unsupported uniforms retry with a
two-second backoff and are never recorded as successfully updated.

Cleanup restores only assignments still owned by this controller. Other material
owners win. Scene reset releases owned variants and clears shared wetness before
the existing bootstrap re-registers objects. EXU caps all owned surface materials
at 1,024; destruction finishes share at most 128 source variants within that cap.

## Water and compatibility

OpenShim Enhanced High DX11 shaders provide small beads, flowing trails and
normal-based glints and a distinct reflective water coat on nearby wet hulls. Distance/subpixel filtering limits
shimmer. The renderer clock supplies animation without Lua work for each unit.
Nearby wet High/IBL pixels reuse the bound environment map for one extra
clear-coat lookup. Dry/distant pixels skip it. Lower tiers retain the basic wet finish. Rain details currently assume upright
local-Y surfaces and a rigid parent transform. Cockpit wetness remains zero.

Requires the matching EXU surface API and OpenShim renderer payload version 4.
Old runtimes fail closed. Muzzle readback currently requires the qualified GOG
single-player native presentation adapter. No Steam/co-op support is inferred
from local GOG evidence. See EXU `Docs/SURFACE_MATERIAL_API.md` and OpenShim
`Docs/REACTIVE_SURFACES.md` for native contracts and pending qualification.

The local review and screenshots are at
`C:/BZRCoop/reactive-surfaces-live/REVIEW.md`. Live acceptance and combat FPS
measurement remain pending; a bounded design is not an FPS measurement.
