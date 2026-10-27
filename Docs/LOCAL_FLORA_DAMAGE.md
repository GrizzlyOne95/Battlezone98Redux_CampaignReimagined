# Local flora destruction

Owner direction, 2026-10-21: grass, flowers and render-only undergrowth disappear
around locally observed explosions. No additional network messages or gameplay
objects. Bare patches persist for the mission and through that client's save/load.
Different clients may have different patches. Solid trees retain gameplay ownership.

## Implementation

`CRFloraDamage.lua` indexes eligible authored placements in 32 m cells once when
a provider registers. It consumes EXU's opt-in local explosion-event queue, using
the loaded explosion class's actual `damageRadius`, capped at 64 m for this visual
effect. Known stock zero-radius ground bullet/laser impacts clear only 1.25–2 m.
Other zero-radius effects, including ambient smoke, do not destroy plants. The
sphere includes height, so distant airbursts do not clear ground underneath them.
Only the vegetation geometry disappears; this does not repaint the terrain.

No unit, ordnance, health or whole-map scans run during combat. The shared service
is timer-gated at 0.1 s. Each slice handles at most 192 candidate plants, 96 index
cells and 8 new blast queries. Native storage is capped at 512 events; the Lua
pending queue at 128. Overflow is counted rather than allocating without limit.

Repeated hits union the removed membership and coalesce dirty layers. A layer
waits 0.3 s before its first edit; at most one layer is replaced every 0.2 s, with
oldest-ready edits first and a 5 s retry delay after failure. Empty layers are
destroyed. Offscreen/unbuilt layers retain removals without building geometry.
These limits bound work per slice; heavy sustained fire can delay visible edits.

Ogre mesh/material resources may already be warm, but vertex/index buffer rebuilds
still cost time. EXU reports high-resolution `totalMilliseconds` for the native
creation/replacement operation, including Lua argument conversion and logging.
`CRFloraDamage.Describe()` exposes maximum/last native rebuild times, removed
plants, candidates, queue depth, dropped events, dirty layers and failures. Timing
does not include the caller's Lua survivor-table preparation.

## Providers and persistence

- Mission 17: `cr17_mire_*` ground cover and `cr17_fl_*` flowers. Rocks, ice,
  water and tree objects are excluded. The jungle save holds each layer's removed
  membership; initial construction filters it. Leaf-litter and grass-wake density
  are reduced when their source plants disappear.
- Mission 18: `CRStorm18Ground` scrub tiles filter removal state both on rebuild
  and after streaming out/in. Its client-local storm save retains membership.
- `TerrainClutter`: profiles participate by default; `destructible=false` opts
  out. Providers using its generated placement system can call `Save()`/`Load()`;
  Mission 02b wires these into its existing save callbacks. `CRWeather.Update`
  services the optional loaded damage module without adding another weather loop.

A future provider registers a unique name and `{mesh,material,points,options,
onRemove}` with `Register`, saves the returned plain table, filters initial builds
with `Instances`, and calls `Resident` after build/drop and `Unregister` on teardown.
Raw points are `{x,y,z,yaw,scale}`; TerrainClutter-style transform tables also work.
A mesh/count/position fingerprint rejects stale membership after placements change.
Callbacks used for density changes must be cheap and local.

Requires the companion EXU explosion-event API. Older EXU versions leave the
removal feature inactive; no callback is replaced and the base scenery remains.

## Validation (2026-10-21)

- `Test-CRFloraDamage.lua`: 26 checks covering overlap/idempotence, empty layers,
  timer and candidate budgets, airbursts, failed rebuild backoff, placement changes
  and restored/streamed membership.
- `Test-CRFloraAdapters.lua`: real TerrainClutter, Mission 17 jungle and Mission 18
  ground adapters; save/reload, stream/revisit, flora-only filtering and litter.
- `Test-CRFloraDamageStress.lua`: 36,422 current Achilles plants in 422 layers,
  96 blast queries; 828 removals, 213 replacements. Indexed results equal a full
  reference scan; every service slice obeys its candidate/rebuild limits.
  Host-only run: registration 74 ms, total sliced model CPU 25 ms, 10,000 same-time
  timer-gated calls 1 ms. These are one machine's Lua model timings, not game FPS.
- Existing TerrainClutter, foliage-wind, Mission 17 jungle, Mission 18 storm and
  Mission 02b co-op suites passed; repository invariants passed. New suites are in CI.
- EXU Release x86 build, hardening/API parity, address-header checks and bounded
  native event-queue tests passed. The supported GOG image and a live process's
  explosion entry bytes matched the existing catalog preimage.

**Live testing pending by owner instruction.** No flora game run was started:
another session was benchmarking. An isolated `florafx` smoke fixture is prepared
under `C:/BZRCoop/flora-local-20261021/`; it exercises scripted explosion, tank
death, a downward rocket, and membership restoration. Native callback values,
rendered holes, full game save/load, co-op observation, actual rebuild hitching
and DX9/DX11/Enhanced/Proton/Wine behavior remain unverified. No installed game
content or release binaries were updated.
