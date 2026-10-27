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

Cockpit glass and power follow the ISDF Chronicles cockpit damage preset. In F1,
below 50% hull the glass shows a faint impact star and below 25% a strong one,
drawn and faded by `CRWetGlass` (on fitted cockpit glass, else the screen
overlay). Hysteresis (clear above 55%, back to faint above 30%) stops
damage/repair chatter, and each craft keeps one spot, clear of the reticle.
`SetCrack` is called only when the stage changes, so a mission that scripts its
own crack (CRStorm18) is not overridden every frame. Leaving F1, leaving
Enhanced, turning the setting off or a scene reset clears the crack, and the
controller keeps calling `CRWetGlass.Update(0)` until it has faded. A real hull
loss of 5% or more in one tick also dims the cockpit emission briefly through
`surfaceState.w` (eased down in about 0.1 s, back over about a second, at most
60%, 0.4 s cooldown). Repair, boarding and the first sample never trigger it.
Impact dirt on the glass and saving the crack spot are not ported.
`Tools/Test-CockpitGlassDamage.lua` covers this.

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

## Snow

Snow worlds (`SnowWorlds`, keyed by the CRWorldArt name read from the TRN
`[Atlases] MaterialName`; Europa only for now) write the `surfaceSnow` uniform
once per scene: x cover, y linear albedo, z blue tint. Every shared material,
owned clone and the world's terrain atlas material (`EU_DETAIL_ATLAS`) take it.
Cockpit materials and clones never do. The OpenShim Enhanced base and terrain
shaders whiten upward faces from the world-space normal plus noise (object-local
on craft and buildings, world XZ on terrain), flatten the normal map under the
snow and raise roughness. Zero is the default and changes nothing. DX11
Enhanced only, any tier. Reset and Suspend write zeros back.

## Dust and ACT weather masks

Dust worlds (`DustWorlds`, same world detection; Mars only for now) write the
`surfaceDust` uniform once per scene: linear rgb dust colour and w amount.
Shared materials and owned clones take it; cockpit materials never do, and
terrain only on maps with a shape mask (below). The Enhanced base shader settles dust on up-facing faces with noise, lowers
F0 and raises roughness under it, and rain (`surfaceState.x`) washes it off.

Materials with a baked ACT map (`ACTMap` alias) place all three weather terms
from it: dust also collects in occluded corners and concave creases, snow thins
under overhangs and on sharp convex edges, and rain beads, trails and wet gloss
follow AO exposure while creases pool water (glossier, darker). Without an ACT
map exposure is 1 and dust uses up-facing faces only.

## Terrain shape masks

`Tools/Build-TerrainShape.py` bakes each weather map's HG2 into hollows (R)
and ridges (G) at 10 m per texel: height minus 30 m and 90 m Gaussian blurs,
mixed and smoothstepped. The maps of one terrain atlas sit side by side in
`<atlas>_shape.dds` (row 0 = min Z), which the atlas material binds through the
`TerrainShape` alias; the CR terrain base passes default to the black
`cr_terrain_shape_none.dds`. `Scripts/CRTerrainShape.lua` (generated) maps
each TRN to its atlas and the `surfaceTerrain` uv transform
(`u = x*su + ou, v = z*sv + ov`; x = 0 is off). An entry is used only when its
atlas matches the map's TRN atlas.

The terrain shader's view-space position is camera-relative (maps sit near
z = 97 km), so the shaped terrain material also takes the camera's world
position in `surfaceCamera` on every update. With both set, snow piles into
hollows and is scoured off ridges, and dust worlds settle dust in hollows
(never under snow). Terrain snow and dust noise also run on absolute world XZ
then. Re-run the tool after editing a weather map's HG2; the build writes the
shipping lock entries too. Reset and Suspend write the transform back to zero.

### Thruster wash

On shaped terrain, hovering craft blow snow and dust off the ground beneath
them. Each update scans 32 records for craft (not people or walkers) within
250 m of the camera; strength is 1 at 4 m altitude or lower and 0 at 12 m. The
nearest fill `surfaceWash0..5` (x, z, 8 m radius, strength); the player also
drops a trail mark every 5 m, which fades over 4 seconds and takes any free
slot. The shader clears 90% of the snow and all the dust inside half the
radius, fading to a noisy rim, so the ice shows through on Europa. Slots are
written only when they change; Reset and Suspend zero them.

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
