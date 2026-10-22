# Local reactive surface controller

`Scripts/CRSurfaceEffects.lua` is integrated with RuntimeEnhancements' existing
object registration and lifecycle. It chains EXU BulletInit/BulletHit callbacks;
callbacks only copy bounded events. Material work happens from Update.

The controller combines local cockpit hull damage and repair, real impact
anchors, smooth muzzle-local heat, wet/dry easing and actual gun-tower power.
CRWeather rain layers explicitly expose `surfaceWetness`; effects neither guess
from preset names nor change gameplay or send network messages.

## Setting and callback ownership

Options > Interface > Surface Effects (default On, `SurfaceEffects=` in the CR
config file) calls `SetEnabled`. Turning it off runs `Shutdown`: owned clones
are released, shared wetness reset, native hooks disabled and Update/Register
become no-ops. Turning it on rebuilds visuals so live objects re-register.

`exu.BulletHit`/`BulletInit` have no shared CR dispatcher, so each Update checks
that the global is still our latest wrapper and, if another script replaced it,
wraps the current function (chaining it) once. A wrapper nested in another of
ours passes through, so a replacement that still chains an older wrapper never
double-counts. Shutdown restores a global only if nothing layered over it;
otherwise the stale wrapper stays in that chain as a pass-through.

## Enhanced only

Reactive surfaces run only while OpenShim's effective render profile is
Enhanced, which is DX11-only. DX9 and DX11 Stock/Retro keep their stock
materials: on leaving Enhanced the controller restores every owned material,
releases its clones and unhooks, but keeps the registered craft, so returning
to Enhanced resumes without a visual rebuild.

The power-off and cockpit warning response lives in `CR_textured-sm4.hlsl`
behind `ENHANCED_MODE`, compiled only by `CR_Textured_fragmentHLSL4Enhanced` and
the `CR_TexturedEnhanced_fragment` unified program. The shared `CR_BZBase` glow
passes keep `CR_Textured_fragment`; only an owned `exu_surface_*` clone swaps its
glow pass to the Enhanced program (`exu.SetSurfaceFragmentProgram`).
`CR_Textured_fragmentHLSL4` and the DX9 shader are unchanged, so Default/Retro
DXBC stays byte-identical (`Compare-DX11ShaderBinaries.ps1`).

## Budgets

| Work | Limit |
| --- | --- |
| Material controller tick | 50 ms; no catch-up loop |
| Event storage | 64 hits and 64 shots |
| Event consumption | 2 hits and 2 shots per tick |
| Tracked objects | 4,096, using existing registration |
| Cold discovery / shared rain | 4 objects / 16 material names per tick (64 names and 32 clone slots while wetness is changing) |
| Active object variants | 64 objects, with 8 heated craft |
| Anchors per craft | 2 impacts, 2 heated mounts |
| Material creation | 1 world subentity and 1 cockpit subentity per tick |
| Per-object material slots | 8 world, 16 cockpit |
| Combat event range | 260 metres from local player |

Hits last 16 seconds and fade over their last four seconds; health recovery also
clears accumulated marks. Wetting takes 2.5 seconds and drying 10 seconds as
exponential time constants. Heat accumulates from accepted shots and cools
smoothly. Missing native mount data suppresses heat rather than guessing.

Rain reaches every material in one synchronised sweep: shared materials and
owned clones (towers, hit units) all receive the same swept value, which moves
at most 0.03 per completed sweep. A few hundred materials therefore wet or dry
together in small steps (about eight seconds from dry to soaked at 300
materials) instead of each one jumping when the round robin reaches it. Clones
no longer wait for their record's slower update. `Tools/Test-SurfaceWetSweep.lua`
covers this.

Heat glows where the muzzle flash is drawn: the native mount plus the same
flash offset the flash uses, read only. That is the craft's `flashOffset<N>`
for the firing slot, else the weapon ODF's `flashOffset`, else none (the
mount). Values are `"right up forward"` metres within -20..20; a malformed one
is skipped like the native parser does. The offset is turned into the weapon
frame with the shot's direction (so turrets and pitched barrels work), stored in
hull axes and re-applied to the live mount every update, so the anchor rides
the hull. A turret that swings after its last shot keeps the last direction
until it fires again. Lookups are cached per ODF key (at most 512).
`Tools/Test-SurfaceHeatAnchor.lua` covers this.
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
