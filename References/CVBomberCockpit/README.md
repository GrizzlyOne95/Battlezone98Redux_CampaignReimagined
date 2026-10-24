# CRA heavy bomber cockpit revamp prototype

Owner request: next cockpit after the accepted NSDF rocket tank art pass.
Chosen `cvhraz`, explicitly flagged by the owner for covering too much view.
This is a separate offline prototype, stacked on PR #310 (`agent/avrckt-cockpit`,
56a7b73c) to reuse the tested shared rig/mesh builder. No earlier cockpit output
or builder defaults are changed; canonical CR is untouched.

## Design

- Replace the deep V-shaped overhead rails, hazard-covered side bars and tall
  central controls with a broad panorama windscreen, slim brown-red framing,
  low horizontal flight deck and dropped auxiliary/arming keel.
- Retain CRA brown-red and ochre exterior identity, with lime-green optical
  traces and small amber status lamps. Asymmetric side stations, ochre hull
  cheeks, continuous-UV inner tub and closed floor/roof/rear bulkhead.
- The exact `CPX11POV` transform remains `(0, 1.588580966, 1.183248043)`, identity
  basis. All first-person vertices follow `CPX21BDA`, handle 11. The skeleton
  is a byte-identical stock copy. Exterior, native files, hardpoints and ODFs
  remain unchanged. Existing cvhraz aliases use the separate cockpit lookup.
- 666 authored interior/fairing triangles. 586 selected original upper/inner
  pod-cap triangles reuse stock UVs and D/N/S/E. Selection uses pod bones 1/2,
  not tiny weapon hardpoint marker cubes; it excludes the body, rear engine
  assembly, complete launcher bank and old cockpit.
- Pods are fitted in the eye frame: 0.35 m inward, 0.85 m down, 1.30 m forward,
  without rotation or rescaling. Closed fairings meet the sill. This is a
  restrained, art-directed first-person fit, not a whole exterior merge.
- Refitted weather glass and three draw batches; no new renderer/shader system.

## Visibility evidence

The receipt compares identical one-sided perspective samples at the real eye:
97 by 55 screen positions, 64-degree vertical FOV, 16:9 aspect, no weather/HUD.
Original cockpit geometry obstructs about 42.9%; the new cockpit and selected
pod caps obstruct about 28.2%. This is geometric screen occupancy, not measured
gameplay visibility or a claim about every FOV. Tests require at least ten
screen-percentage-points improvement plus a broad clear central corridor.
Native FOV, HUD and camera behavior still need game testing.

## Texture provenance and build

Built-in ImageGen supplies the new atlas. The actual ship's third-person POV
locator in `source-reference.png` is a palette/material reference, not an edit
target or a geometry input. `prompt.json` saves the exact successful prompt,
reference role and generation mode. Authoring master size and output hashes
are recorded in `build.json`. Runtime D/E are 1024-square legacy BC1 with full
mip chains. Existing flat N/quiet S are reused; no duplicate exterior maps.

Green and amber emission is confined to physical lens ROIs and hue/brightness
thresholds; brown paint, ochre guards and red switches stay dark. The source
mask is saved as `optical-mask.png`. Displays are static artwork, not working
radar, sensors, weapon telemetry or interactive controls.
The generated master is 1254 square despite the requested 2048; this is not
a claim of authored 2K detail. The center keel rotates the landscape chart to
its portrait axis so round status lamps do not become stretched ovals.

```text
python Tools/Build-CVBomberCockpit.py --game <BZR root>
python Tools/Test-CVBomberCockpit.py
python Tools/Test-AVRocketCockpit.py
python Tools/Test-CVFighterCockpit.py
python Tools/Test-RedDevilCockpit.py
python Tools/Validate-CampaignRepository.py
```

Only the builder needs the installed stock skeleton (`--game`; maintainer's
GOG copy is the default). Tests use committed inputs and shared model codecs,
not a game installation or Blender. Pins for material text normalize CRLF/LF;
binary meshes, skeletons, textures and art remain byte-exact. Tests cover rig,
shader streams, tangent bases, skin weights, UVs, nondegenerate geometry,
central clearance, pod visibility, closure/window topology, screen obstruction,
texture/mip/emission identity and shipping membership. Negative fixtures use
the old obstructive cage and a deliberately lowered eye.
Final targeted suites: bomber 68 checks, rocket tank 65, fighter 56, Red Devil
55; repository validation passes. These remain offline contracts only.

Shipping `-bless` refused 51 unrelated absent generated payloads in the fresh
worktree without changing the lock. The knowledge base's membership-only
fallback adds exactly five receipt outputs beside existing entries, retaining
every previous member and its order. No removals and no `Bin/` writes.

## Review boundary

One-sided offline Blender views use the original review eye/FOV and lighting;
before/after, forward/down/console, left/right, roof/floor/rear and low-light
views are provided. They verify art only, not native loading, HUD fit, weather,
damage, performance or GOG/Steam/Proton/Wine qualification. No game launch,
deployment, publication or merge. Wait for owner art acceptance before rollout.
