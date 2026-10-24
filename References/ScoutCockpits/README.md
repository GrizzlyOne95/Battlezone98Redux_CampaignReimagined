# NSDF and Black Dog Razor scout cockpit pair

Owner request: revamp `avfigh` and `bvfigh`, faction-appropriate texturing,
and keep it **BZ grounded, not generic science fiction**. `ODF/bvfigh.odf`
already resolves `baseName = "bvraz"`; therefore the correct Black Dog
resource is `bvraz_cockpit`, not a new unused bvfigh asset/ODF chain.

This work stacks on bomber PR #311 (`agent/cvhraz-cockpit`, 7bc73999) to reuse
the tested shared rig/mesh builder. Earlier cockpit output assets and helper
defaults are unchanged. Canonical CR is untouched. No game launch, deployment,
publication or merge.

## Grounded design and faction identity

The stock cockpit sheet `stock-hardware-reference.png` is the primary hardware
reference: chunky framed rectangular switch banks, square illuminated buttons,
mechanical dial, fuse blocks, slotted grilles and recessed cable/service bays.
The owner's grounding instruction superseded initial modern-avionics drafts;
those unconsumed previews are not shipped. No broad glass MFDs, holographic
HUDs, giant radars or polished airplane screens are used in this pass.

Actual faction exterior references are retained in each faction folder:

- NSDF: muted petrol blue-green paint, charcoal inset machinery, ivory ticks,
  cyan optical pushbuttons and restrained amber status lamps.
- Black Dog: charcoal-black structural metal, red edge trim/guards, ivory
  ticks, red optical pushbuttons and restrained amber status lamps. Red enamel
  and cables do not emit. Structural beam facets are mostly dark with narrow
  red-painted faces, not uniformly scarlet bars.

Both use a compact Razor wedge canopy with substantial mechanical seals,
rearward-swept cheek posts, low squat physical control bank, dropped service
spine and asymmetric side stations. The actual stock-painted nose is visible
beyond the coaming; this is not a whole-body merge. Earlier approved cockpits
are not redrawn by this follow-up.

## Exact rig and source preservation

| Selector | Original eye | Shell | Nose source bone |
| --- | --- | --- | --- |
| avfigh | `ARA11POV`, (-0.0044, 1.467507005, 0.748861998) | `ara21bda`, 13 | `ARA11rof`, 2 |
| bvfigh -> bvraz | `bRA11POV`, (-0.0044, 1.467507005, 0.856662005) | `bra21bda`, 11 | `bRA11rof`, 1 |

Both eye bases are identity. Stock skeletons are copied byte-for-byte to unique
resources, retaining all names, transforms, hierarchy and hardpoints. The two
eyes differ by 0.1078 m along Z; common authored shape is fitted to each exact
eye independently. All output vertices follow that faction's stable shell.
Exterior meshes, native records, materials and all ODFs remain unchanged.

Each cockpit has 680 authored interior/coaming triangles, plus 738 triangles
of the original complete ROF nose component. Selection is exclusively all
vertices weighted to that nose bone, not GC hardpoint cubes or fragmented
side-only crops. Nose UVs, triangle shape and scale are preserved. The rigid
first-person fit pitches -14 degrees about model (0, 0.70, 2.30), then moves
0.10 m up and 0.15 m forward; normals/tangents rotate with it. This is an
art-directed first-person fit, not an exterior/weapon/hardpoint modification.
Noses reuse their existing faction D/N/S/E byte-for-byte, including stock
optics. Interiors alone use the new cyan/red optical maps.

The enclosure has a continuous lower-tub unwrap, closed floor/roof/rear and
one intentional wraparound canopy boundary. A closed low coaming joins the
nose root. Weather glass is refitted: each 605 vertices / 1092 triangles.
Three batches per cockpit, no shader/native changes.

## Art provenance and reproduction

Built-in ImageGen generated two independent atlas masters using the actual
stock cockpit sheet for hardware style and each actual ship for faction
palette. References are not edit targets. Exact prompts, roles and mode are
saved in `nsdf/prompt.json` and `bdog/prompt.json`. Both requested 2048 square,
both returned 1254 square; this does not claim newly authored 2K detail.

The sheets return different chart boundaries. `Tools/Build-ScoutCockpits.py`
repackages explicit source rectangles into padded shared UV allocations,
rather than stamping an entire atlas on every panel. Runtime D/E are 1024
square legacy BC1 with full mip chains. Each saved physical lens ROI is gated
by hue/brightness before repacking; saved source masks are `optical-mask.png`.
Paint, cable insulation, fuse cases, metal dials and mechanical toggles stay
nonemissive. No bitmap is procedurally redrawn. Existing flat N and quiet S are
reused; no duplicate exterior atlas set is created.

All buttons/dials/status lights are static artwork, not live telemetry or
interactive controls.

```text
python Tools/Build-ScoutCockpits.py --game <BZR root>
python Tools/Test-ScoutCockpits.py
python Tools/Test-CVBomberCockpit.py
python Tools/Test-AVRocketCockpit.py
python Tools/Test-CVFighterCockpit.py
python Tools/Test-RedDevilCockpit.py
python Tools/Validate-CampaignRepository.py
```

Only the builder needs the installed stock skeletons; `--game` defaults to the
maintainer's GOG install. Tests use committed inputs/shared codecs without
Blender or game installation. Receipts pin source/master/output hashes, rig,
triangle selection and fitting parameters. Material text pins normalize CRLF
to LF; binary/bitmap pins remain byte-exact. Checks cover actual eye/skin/rig,
shader streams/tangents, no degenerate triangles, central clearance, closure,
window topology, nose visibility, source UVs and triangle lengths, unique
faction paint/emission, physical masks, DDS mips, shipping and bvfigh routing.
The lowered-eye negative fixture must hit the control bank.
Final pair suite: 134 checks passed. Earlier cockpit regressions pass too
(bomber 68, rocket tank 65, fighter 56, Red Devil 55); repository validation
passes. These numbers are offline contracts, not native qualifications.

Shipping `-bless` refused 51 unrelated absent generated payloads without
modifying the lock. Documented membership-only fallback admits exactly ten
new receipt outputs beside existing entries: no removals, every prior member
and order retained. No `Bin/` writes.

## Review boundary

Offline one-sided Blender forward/down/console, side, roof/floor/rear and
low-light views use actual eye, the review's 64-degree vertical FOV and fixed
lighting. Before/after comparisons retain identical camera and lighting per
ship. These are art checks, not native loading, HUD fit, animation, weather,
damage, performance or GOG/Steam/Proton/Wine runtime qualification. No runtime
lane was exercised. Wait for owner art acceptance before rollout.
