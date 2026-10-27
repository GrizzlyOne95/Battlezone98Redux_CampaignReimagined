# NSDF rocket tank cockpit revamp prototype

Owner request: pick the next cockpit after the accepted `cvfigh` art pass.
Chosen `avrckt`, which used the APC cockpit texture and a heavy overhead slab.
The owner previously suggested seeing the front fins low in the view.

This work stacks on PR #309 (`agent/cvfigh-cockpit`, 30f8a014) for the shared
cockpit builder. Only the shared rig helper's optional shell-name argument is
generalized; defaults, Red Devil and CRA fighter output bytes remain unchanged.
Canonical CR is untouched. Nothing has been deployed, launched or published.

## Design and geometry

- Separate `avrckt_cockpit.mesh` / `.skeleton` resources use the established
  first-person lookup; existing ODF aliases need no gameplay/selector changes.
- Exact `art11pov` eye: `(0, 2.1953830123, 1.3317009509)`, identity basis.
  Stock skeleton copied byte-for-byte; every output vertex follows stable
  `art21bda`, handle 11. Exterior, native assets and ODFs are unchanged.
- Broad faceted windscreen with slim petrol-blue framing instead of APC
  hazard posts and the low overhead slab. Split flight/launcher console,
  asymmetrical side controls, closed inner tub, roof and rear bulkhead.
  Tub UVs are continuous across the facets, not repeated full panel stamps.
- 734 authored interior/coaming/mount triangles. 393 original lower nose/fin
  apron triangles are selected from `Assets/ModelFixes/avrckt.mesh`: all bone-0
  weights, all Z > 1.8, some Z > 2.9, all Y < 1.8. This excludes upper hull,
  launcher bank, headlight, moving rear nozzles and old cockpit. The small
  adjoining centre apron remains; separated side-only crops left fragments.
- Nose/fin UVs and scale are retained. One rigid fit pitches the piece -12
  degrees around model `(0, 1.1, 3.3)`, then translates +0.28 m up and +0.40 m
  forward. There is no X-sign split or independent side shift. Normals/tangents
  rotate with the geometry; tangent basis is orthogonalized and normalized.
  The silhouette peeks over the sill, connected behind closed cheek boots
  and a closed coaming-to-nose bridge rather than a ribbon of exposed sky.
  This is an art-directed first-person fit, not a literal whole-hull merge.
- Weather glass is refitted to the opening: 550 vertices / 980 triangles.
  Three batches total; no new shader system or native integration.

## Texture and lighting

Built-in ImageGen authored `atlas-master.png`; `source-reference.png` is the
actual ship's third-person POV locator, used only for material/colour identity.
`prompt.json` saves the complete prompt, mode and reference role. Requested
2048 square; actual returned master is 1254 square. Runtime D/E are 1024 square
legacy BC1 with full mip chains. This does not claim newly authored 2K detail.

The atlas allocates separate flight/radar, launcher, switch and engine panels,
plus quiet petrol-blue armor/frame and charcoal trim. Cyan screens and a few
amber lamps have explicit physical lens ROIs and brightness/hue thresholds.
Petrol paint, yellow guards, red toggles and structure do not emit.
`optical-mask.png` retains the source mask. All instruments are static artwork,
not live radar, weapon, fuel or flight telemetry.

Reuse existing flat normal/quiet specular for the new interior, and original
avrckt D/N/S/E for the lower nose. No duplicated exterior texture set is shipped.

## Rebuild and checks

```text
python Tools/Build-AVRocketCockpit.py --game <BZR root>
python Tools/Test-AVRocketCockpit.py
python Tools/Test-CVFighterCockpit.py
python Tools/Test-RedDevilCockpit.py
python Tools/Validate-CampaignRepository.py
```

Only the builder needs an installed stock skeleton, supplied with `--game`
(default is the maintainer's GOG copy). Tests use the committed skeleton and
shared codecs; no game or Blender required. `build.json` pins source/master/
output hashes and selection/fit metadata. Checks include rig and resource
lookup, unit shader streams, skin weights, triangle quality, central aim,
front-facing fin visibility, roof/floor/rear closure, window topology, original
UVs and rigid triangle lengths, physical emission, DDS mips and shipping.
A deliberately moved eye must hit the dashboard as a negative fixture.
Final targeted suites: avrckt 65 checks, cvfigh 56, Red Devil 55; repository
validation passes. These are offline contracts, not native qualifications.
Material text pins normalize CRLF to LF so a fresh Git-for-Windows checkout
does not fail on line endings alone. Mesh, skeleton, textures and source art
remain byte-exact. The same correction covers the inherited cvfigh test.

Shipping `-bless` refused 51 unrelated absent generated payloads in the fresh
worktree, without modifying the lock. Used the knowledge base's membership-only
fallback: admit exactly the five receipt outputs beside their neighbours,
preserve every previous member and order, remove nothing. No `Bin/` writes.

## Review boundary

One-sided offline Blender renders retain actual POV, 64-degree vertical FOV
and the fleet review lighting. Forward/down/console, sides, roof/floor/rear and
low-light emission views are provided, with same-camera before/after images.
These establish art selection/readability, not native loading, HUD fit,
weather/damage behavior, performance or GOG/Steam/Proton/Wine qualification.
No runtime lane was exercised. Wait for owner art review before broader work.
