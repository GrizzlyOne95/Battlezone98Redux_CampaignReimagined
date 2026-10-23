# CRA fighter cockpit revamp prototype

## Wing-and-gun connection follow-up (2026-10-23)

Owner asked to move the miniguns farther outboard and show their overlying
wings. Supersedes the original fitted-gun description below. The accepted
interior remains; remove only its 24-triangle invented swept outriggers and
replace the old gun crop with both real capped wing/pod-and-gun sections.
Select body-bone surfaces at `abs(x) >= .90`, `z >= .80`, excluding every
hardpoint marker, using attribute-interpolated cuts and explicit rear caps.
Source positions/scale are **native**, with zero inboard/up/forward offset:
the previous `.55/.45/.65 m` fit is gone. Original UVs interpolate at cuts;
no new atlas or texture edits. Guns stay under their wings, not hovering above
the sill or moved sideways away from the original firing locations.

The wing roofs are especially visible during side looks. A subsequent ray
diagnostic corrected the initial explanation for missing forward barrels:
our outer cockpit sills, NOT the native wings, completely occluded them.
Lower the forward outer lip from eye-relative y=-.34 to -.58 m, blend the
closed liner into that profile and add capped front joining posts. Keep the
rear lip, center console, camera, wing/gun source positions and hardpoints
unchanged. Both barrels now just peek at the lower outer corners: 69 actual
barrel samples per side in a 160x90 forward view (64-degree vertical FOV,
16:9), about .96% of the screen combined. The compiled cockpit now has 720
interior/back triangles and 3,992 source section triangles, plus glass.
The 110 section-cap triangles use the existing quiet interior trim allocation.

`References/CRACockpitConnections/review` retains this follow-up's exported
renders and comparisons; the earlier `review/` images below remain the first
accepted prototype. Fighter tests now run 71 checks. Barrel checks classify
source faces rather than accepting any wing/gun material hit; restoring the
old sill faces is a negative fixture that must hide the barrels again.
Weather glass is fitted
only to the retained cabin, excluding distant exterior sections and their backs.
The common compiler's optional fit subset leaves other builders unchanged.
Exterior/native hardpoints,
ODFs, original/fallback mesh, rig, interior textures and emission masks remain
unchanged. No promise of live shot/flash alignment or native animation follows
from this offline fit. No game launch or deployment.

## Original prototype record

Owner request: pick one reviewed cockpit and fully revamp it. Chosen `cvfigh`:
replace its generic cage with a low, broad CRA fighter interior and show small
portions of the miniguns at the lower sides. Preserve the approved Red Devil.

`agent/cvfigh-cockpit` stacks on Red Devil PR #306 (`fc3190b6`) because that open
workstream supplies the shared mesh/tangent/weather-glass builder. Only its
optional skeleton-resource argument is generalized; its defaults, geometry,
textures and approved renders are unchanged. The canonical checkout is not edited.

## Design

- Separate `cvfigh_cockpit.mesh` / `.skeleton` resources use the established
  engine lookup ahead of the unmodified in-mesh fallback. Existing cvfigh ODF
  aliases select this without gameplay or hardpoint edits.
- Geometry uses the exact `CFL11POV` derived position `(0, 1.301751971, 1.056630969)`
  and identity basis. All vertices follow stable shell `CFL21BDA`, handle 10.
  The skeleton resource is a byte-identical stock copy; original exterior/native
  assets and every ODF are untouched.
- New low, wide instrument panel, raked wraparound canopy, wine-red narrow
  framing, ochre side shoulders, asymmetrical side controls and closed inner
  tub/roof/rear bulkhead. The lower tub uses one continuous unwrap across its
  facets rather than stamping the full trim image on every face.
- The tiny six-triangle GC nodes are only hardpoint markers. Selected visible
  gun surfaces instead come from the source body batch: 2326 triangles, original
  UVs and normals. Positions are translated inward 0.55 m, upward 0.45 m and
  forward 0.65 m in the eye frame; no rotation or rescaling. Closed swept mounts
  connect their backs to the sill, leaving small upper gun sections in view.
  First-person tangents are orthogonalized and normalized; empty source tangent
  directions get a stable orthogonal fallback. This is an art-directed first-
  person fit, not a full exterior merge or a weapon/hardpoint change.
- 578 authored interior/mount triangles, 2326 selected gun triangles, 884 fitted
  weather-glass triangles. Three batches total; no new shader system.

## Texture and emissive art

Built-in ImageGen produced `atlas-master.png` using `source-reference.png` only
as the vehicle/material identity reference. The full prompt is in `prompt.json`.
Although the prompt requested 2048 square, the returned master is 1254 square.
Runtime D/E are 1024-square, full-mip legacy BC1: this is not a claim of newly
authored 2K detail. Master pixels are not procedurally repainted.

`Tools/cvfighcockpit.py` records inset UV allocations for the main console,
switches, engine controls, ochre armor, quiet red frame strip and charcoal trim.
Green CRT traces/bars and saved amber indicator ROIs drive E; structural paint,
red toggles, armor and frames stay dark. `optical-mask.png` preserves the source
mask. Instruments are static artwork, not live ammunition/flight telemetry.
Flat N and an existing quiet specular are reused. Selected guns reuse existing
cvfigh D/N/S/E; no duplicate exterior atlas is shipped.

## Build / validation

```text
python Tools/Build-CVFighterCockpit.py --game <BZR game root>
python Tools/Test-CVFighterCockpit.py
python Tools/Test-RedDevilCockpit.py
python Tools/Validate-CampaignRepository.py
```

The builder alone needs the extracted stock skeleton, found through its explicit
`--game` parameter (default is the maintainer's GOG copy). Tests use the committed
copy and shared codecs, not an installed game. `build.json` pins master/input/
output hashes, geometry selection and fit metadata. Tests cover source/skeleton
preservation, lookup, shader streams, skinning, no degenerate triangles, central
aim clearance, visible gun samples on both sides, connected window topology,
floor/roof/rear rays, UVs, mips, optical masking and shipping membership. A moved-
eye negative fixture must hit the dash.

`-bless` was attempted but refused 51 pre-existing absent generated payloads in
this fresh worktree, without modifying the lock. No removals were authorized.
The knowledge base's membership-only fallback admitted just the five receipt
outputs beside existing entries, preserving every previous member and its order.
`Bin/` and those unrelated generated assets were not touched. Repository validation
passes; this does not qualify deployment.

Offline renders use one-sided surfaces, actual POV, the review's 64-degree
vertical FOV, green/amber E and consistent lighting. Forward, down, console,
left/right, roof, floor, rear and low-light emission views are retained for art
review. Offline visuals/geometry tests do not prove native loading, HUD fit,
weather-layer operation, damage behavior, performance, or any GOG/Steam/Proton/
Wine runtime lane. No game was launched and nothing was deployed or published.
Wait for owner art acceptance before broad rollout or release qualification.
