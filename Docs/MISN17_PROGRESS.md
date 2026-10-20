# Mission 17 workstream progress

Updated 2026-10-18. Branch `agent/misn17-coop`, worktree
`Campaign-Reimagined-misn17`. Stacked on `agent/fury-fighter` / PR #227,
head at branch creation `476390ed`. Canonical main stays untouched.

## Owner decisions

- Port Tapping the Core to shared offline / 2–4 player co-op using the CR recipe.
- Preserve converter destruction as a way to win.
- Restore the full optional crystal path, including unused VO and custom models
  as needed. This supersedes the earlier stock-route-first staging decision.
- Achilles should be an Earth-like jungle: rainstorms, rivers/waterfalls,
  trees/plants. Reference the owner's ISDFC work.
- Large trees must be solid plant objects with collision; grass/underbrush may
  be Ogre visuals. Commit/push checkpoints and keep this handoff current.

## Implemented prototype

- `CRMisn17.lua` wraps the faithful body with real CRCoop authority, teams 1–4
  humans, 6 Fury, 7 support; shared recycler; explicit enemy AIP; bounded starting
  scrap bonus; ordered acknowledged E/A presentation and shared camera snapshots.
- Seven towers and 54 Fury mines preplaced. Shipped 1.5 uses mine54 and replaces
  DLL paths 50/51 with 55/56; aliases fix the DLL/map mismatch. Sweep clears all
  54. No visible proximity mine creation. Scripted defenders enter at concealed
  sites, retaining pending orders while all entries are watched.
- Shared victory and failure latch once. Recycler loss takes precedence in a
  simultaneous result. Intro skips are local; an authored 35-second bound avoids
  a skipped host path holding everyone indefinitely.
- Shared campaign listing, four starts, original 1.5 unsmoothed heightmap and
  Redux TRN/MAT/LGT companions. New western stream locally cuts 339 samples;
  the original terrain otherwise remains. The new channel is authored CR work.
- ISDFC-derived foliage/cutout/water assets are namespaced, with mesh copies
  repointed to new materials and textures. Source hashes are in
  `References/Misn17Jungle/source-assets.json`.
- 33,416 visual undergrowth plants in 132 bounded Ogre batches. 3,331 planned
  solid tree sites, 125 preplaced near initial sightlines. `CRJungleTrees17`
  streams the rest on the leader beyond every human's 460 m guard, outside
  story cameras, at two plants per 0.08 seconds maximum. No unit AI setter is
  applied to a plant, artifact or other fixture.
- Redux's working plant contract is `i76building2` + EXU `[PlantClass] isPlant=1`.
  Tree SDF/GEO collision geometry is retained and namespaced with the meshes and
  skeletons. New resource names are `c17tree1/2` and `j1711*/j1721*` GEOs.
- `CRJungle17` is a leader-owned weather director over the existing
  CRWeather/Environment architecture. Levels track the mission: 0 clear
  (victory), 1 light rain on approach, 2 downpour deepening with each tower
  loss, 3 storm with lightning once the towers collapse, 4 tempest with rapid
  lightning during converter overload or after a converter falls. Each level
  sets rain, basin mist, fog distance and wind (an override that also slants
  splashes). From level 2 the `CR17/StormCloud` sky plane scrolls with the
  wind, unless the map already has a sky. Bolts are leader-timed number-only
  packets, and thunder is delayed locally. The level resyncs every 15 s and
  survives save/load. Also included: splash and wet glass, the flowing river,
  cascade mist and local rain/water audio.
- Water: `Build-Misn17Jungle.py` priority-floods the heightmap. Streams are
  routed by D8 over a Gaussian-blurred (σ 3 cells) flooded surface, which
  gives branching valley channels rather than grid diagonals. Thresholds are
  900-cell accumulation and a 120 m minimum, producing 100 segments and
  4,297 points. Beds are carved shallowly outside object footprints. Closed
  depressions fill as standing pools: 58 pools, 19,945 cells, capped at
  1,500 cells each. These are emitted as `cr17_streams` and `cr17_pools`
  static meshes. The builder also orders each shader family's delegates before
  its unified program, so a rebuild cannot reintroduce the invisible-material
  bug.
- `CRCrystals17` prototype: five raw artifact cargoes, processed cargo, refinery,
  converter feed and a shared hauler. Twelve-second refining; dropped raw cargo
  at the receiver after towers fall starts a twenty-second overload; processed
  cargo stabilizes it. Overload destroys the existing three converter handles,
  letting the existing finale/result gate run. Lost optional cargo leaves the
  destruction route available. Haul observations are relayed by human peers;
  only the leader accepts deliveries, processes cargo and changes gameplay.
- Four custom faceted crystal/station models have matching SDF/GEO collision,
  Ogre meshes and skeletons. The unused raw/processed path positions are shifted
  180 m west to keep the cargo inside the playable boundary. This mechanic and
  these placements are a CR reconstruction, not recovered executable behavior.
- VO `misn1702`, `1705`–`1709` extracted byte-exact from `bzone_en.zfs`.
  Narrative uses crystal discovery/instruction, critical power, stabilization
  and congratulations. The existing body plays `1703` for the explosion.

## Cold temperate forest (branch `agent/achilles-flora`, 2026-10-19)

Owner direction: Achilles must stop reading like BZ2's Mire. It should be an
Earth-like cold temperate forest, close to freezing but still wet.

- `Tools/Build-Misn17Forest.py` replaces the Mire trees and props. It runs after
  `Build-Misn17Jungle.py` and is deterministic (seed 17117).
- **Trees.** Four fir/pine trees from "Low Poly Forest Tree Pack" by 99.Miles
  (CC-BY-4.0, `Docs/FOLIAGE_ART_CREDITS.md`): `c17frst1`-`4`, 58/46/52/40 m.
  They use the same plant contract (`i76building2` + `[PlantClass]`), a trunk
  prism GEO, and wind-sway branch materials.
  - All 3,097 tree sites, including 124 preplaced, were re-picked by a hash of
    the site label. Positions and labels are unchanged, so streaming,
    save/load and co-op labels are unaffected.
- **Rocks.** Nine pack rocks (`cr17_frock1`-`9`) on a 17 m jittered grid on
  TRN types 1 (forest) and 2 (rock): 5,935 instances, 1.2-4.5 m across
  (mostly about 2 m), in 144 static batches.
  - They keep clear of water, the river (12 m), slopes over 0.7, objects
    (30 m) and paths (20 m).
  - They are visual only, with no collision.
- **Ice.** Forty ISDFC `baneice`/`darkice` props as solid plants, only on shore
  cells: dry 5 m cells next to a watermask or river cell.
  - Large ones need at least 70 water cells within about 30 m; 5 sit by
    pools or the river and 35 on stream banks.
  - They keep 75 m apart and clear of objects and paths.
  - Each is a preplaced tree site (`cr17_iceN`), so it streams and saves like a
    tree.
- **Removed from misn17.** Mire trees, `mireshr`, `urchin`, `rendflow` and the
  crystal props. `c17tree1/2` still ship but misn17 no longer references them.
  The `cr17_mire_*` ground-cover meshes are kept (misn18 shares them).
- **Ground cover.** On misn17 only, the ground cover draws through
  `CR17/GroundWindCold`: a cooler, wetter tint with a little specular.
  No new grass assets were added.
- **Live check (2026-10-19).** Single instance, crsetup, weather wired like
  CRMisn17, captured after the blend. Before/after images:
  `C:/BZRCoop/runs/achilles-flora/misn17-flora-before-after.png`.
  - All new meshes, skeletons and textures load.
  - No "Unable to set D3D11 vertex declaration" lines; Ogre shows only the stock
    `TestGround.material` compiler errors, which the before run has too.
  - Each tree/ice ODF logs `Explosion "xplnxpl.odf" not found`. This is
    inherited from `c17tree1.odf`, which logs it too.
  - Not checked live: co-op, save/load, streaming at range, and DX9.
- **TRN hints.**

  | Texture type | Asset | Used for |
  |---|---|---|
  | 0 | grass (`ac00`) | none |
  | 1 | trees (`ac11`/`ac12`) | tree and rock placement |
  | 2 | rocky (`ac22`) | rock placement |
  | 3 | river (`ac00sc`) | none |

## Verified so far

- Lua 5.1: faithful port **141**, source parity **241**, real four-peer co-op
  simulation **112**, jungle weather director/lifecycle **111**, crystals **47**, tree streaming
  **129** checks pass. The co-op fixture
  stubs the separate environmental and crystal modules; these numbers do not
  qualify their native rendering or cargo physics.
- All **22** imported HLSL delegates compile with `/WX` for their SM3/SM4
  targets using Windows SDK fxc. Reflection/default-parameter and GLSL checks
  remain to be recorded.
- Full prototype repository validation: 3,123 files checked; campaign-shell
  tests pass. Corrected waterfall sound to the engine-safe `c17falls.wav`.
- `misn17-stock-3`: two native Windows/GOG/DX11 clients, **6 steps / 21 checks**,
  guest-triggered mixed fighter defense, 54-mine collapse, all factory shells,
  one result each, 27 matching presentation ops, no Lua errors and normal exits.
  This predates the new jungle and crystal route.
- `misn17-stock-1`: menu music crash before authentication. `stock-2`: all story
  steps completed; one harness assertion wrongly expected two fighters instead
  of the intended mixed roster. Fixed for `stock-3`.
- `misn17-jungle-4`: all 3,331 trees were originally in the BZN. Long native
  loading timed out the network keepalive before registry admission. That design
  was replaced by 125 initial plants plus concealed streaming.
- `misn17-jungle-5`: stopped at lobby because a client had no visible window;
  it did not test the reduced tree map or jungle rendering.
- **Invisible leaves and underbrush (fixed, d4d95157).** Every CR17 unified program was
  declared before its delegates, so `default_params` (`wvpMat`, `worldViewMat`)
  never bound and those materials silently drew nothing. Ogre logged no error for this.
  The fix declares GLSL, HLSL4 and HLSL first and then the unified program, the
  order ISDFC and `cr_methane` use. Evidence from the leaf bisect scenario
  (`Tools/Test-Misn17LeafDiagLive.ps1`): `misn17-leafdiag-4` shot 03 shows
  bare trunks. In `misn17-leaf-reorder-1` shot 03 the canopies and underbrush draw,
  and forcing the leaf submesh to `CR17/Cutout` draws panels.
- `misn17-forest-reorder-1` (story scenario, first run with jungle and crystal
  content): steps 1–4 pass. During step 5 (seven tower losses collapse 54 mines)
  client 1 crashed with an access violation in the engine, a read at exe+0x430A0E
  on the main thread, while explosion and particle textures were loading. There were
  no CR17 shader, StaticGeometry or out-of-memory errors in the Ogre log. Cause
  not yet known. `misn17-story-jungle-2` reproduced it at the same step (client 1,
  58.6 s, frame 2718; last log again the `SetObjectiveName` "Converter crystal
  feed" op). `misn17-stock-3`, before the jungle and crystal content, passed this
  step, so that content was the trigger.
- **Root cause of that client crash (fixed, 661497b3).** The engine's Lua packet
  string decoder reads each string's length as a *signed* byte. Any `Send`
  string longer than 127 bytes therefore crashes every receiving peer
  (exe+0x430A0E). The 141-byte crystal objective text, sent once the hint
  marks the converter feed, was the trigger. Fixes:
  the text is now 106 bytes; every mission-owned send in `CRMisn17.lua` now goes
  through the shared `CRWire.Pack`/`Unpack` (127-byte chunks, `\2` marker; the
  local copy was retired after the main merge `54dc7045`); the fixture's
  `e.Send` asserts every string argument is 127 bytes or less. The crystal
  reports also moved from channel `J` (owned by `CRCoopComms`, which was
  swallowing comms packets) to the new channel `Y`. Channels in use: H Q K P L
  (CRCoop), J (comms), C E A (presentation), I (another mission), Y (crystal).
  An OpenShim-side unsigned-length fix would protect every mod; that is a
  separate workstream.
- `misn17-story-wire-1` (story scenario, jungle and crystal content, wire fix):
  **PASS, 6 steps / 21 checks**, both clients. The tower-loss step that crashed
  client 1 in `forest-reorder-1` and `story-jungle-2` now passes (54-mine
  collapse at 58.0 s), followed by all factory shells, `SucceedMission` on both
  peers, 47 matching presentation ops and no Lua errors.
- `misn17-jungle-hd-1` (jungle scenario, `Tools/Test-Misn17JungleLive.ps1`):
  **PASS, 7 steps / 23 checks**, both clients. Bounded foliage batches,
  river/mist, a solid native plant seen by each peer, heavy rain then a shared
  storm, waterfall, plant destruction replicated without touching mission
  gates, stock converter route to `SucceedMission` on both peers, 23 matching
  presentation ops, no Lua errors. Shots 03–05 show canopies, underbrush,
  rain rings and the river.
- **Weather director and water network, live (`jungle-water-1`…`7`).**
  - `water-1` fast-failed (0xC0000409 at exe+0x43ECA1, with no OpenShim log). A
    `require` of `CRWire` was missing from the frozen test content, and the long
    error overflowed the engine's fatal printer. Stage `CRWire.lua` with the
    mission.
  - `water-4`: 1,050 D3D11 "Unable to set vertex declaration" exceptions per
    client. Ogre's sky plane has no COLOR0, and the ACLOUD2.MAP clone's Effect
    programs read it. The cloud deck now uses its own `CR17/StormCloud`
    material and `cr17_cloud` shaders (position and UV only); `water-5` onward
    show 0 exceptions.
  - `water-5`/`6`: the pools/storm steps hung on a modal "Fsm error: Camera
    Stack 0verfow". The mission's mine cinematic pops the camera stack itself,
    so a test camera pushed or popped across it overflows or underflows. The
    scenario now releases its camera before the first tower falls and shows
    the water from the cockpit.
  - `jungle-water-7`: **PASS, 10 steps / 33 checks**, both clients:
    - light rain with streams, pools and wind;
    - downpour on the first tower loss;
    - lightning storm under the cloud deck once every tower falls;
    - pools (shot 07) and streams (shot 08) on the terrain under rain rings;
    - plant destruction replicated;
    - `SucceedMission` on both peers, 49 matching presentation ops;
    - no Lua errors and no Ogre exceptions.

    Shot 08 shows the stream as a channel in the middle distance; the nearest
    stream segment is not in frame.
- Test instances now run 1920×1080 windowed (`Full Screen=No`) with radar 0.5×,
  PDA font 0.8/opacity 0.4 and the weapon stats HUD off, so captures show the
  world. Previous settings are in `*.pre-hd` beside each instance file.

## Immediate next work

1. Finish crystal-specific simulated tests: raw/processed delivery, genuine
   towing/drop requirement, refinement, guest reports, wrong delivery recovery,
   lost cargo, save/load deadlines, simultaneous converter/recycler outcomes.
2. Run the reduced-tree native jungle scenario. Inspect actual images for leaf
   cutouts, bark, river placement/flow, mist and rain; inspect Ogre logs. Check
   `exu.IsPlant`, solid tree collision and replicated destruction. Shader loads
   or particle readbacks alone are not visual proof.
3. Run native crystal haul/drop/refine/stabilize/sabotage routes with both
   peers, custom cargo collision/pickup and VO/subtitle sequence. Check original
   converter victory and recycler loss again with the full prototype active.
4. Add/update map/asset contract and shipped-cut-VO checks; CI integration;
   README/campaign description/changelog; source-port and co-op docs. Confirm
   Environment sensor binding follows the shared weather policy.
5. Review geometry winding, mesh/material/skeleton references, all shipping
   membership, native errors and resource cleanup. Replace placeholder tree
   death effect if `xplnxpl` is not a stock resource. Add visible refinery
   processing/receiver feedback and verify it rather than claiming a model
   substitution alone looks complete.
6. Final two-/four-client harness qualification, natural balance/navigation,
   save/load and human play remain unverified. Steam/Proton/Wine are unverified.

## Resume commands and local evidence

Use this worktree; do not edit canonical main or ISDFC. ISDFC source is
`<GOG game>/addon/ISDF Chronicles`, origin
`GrizzlyOne95/ISDF_Chronicles`, main `63a3645c` when inspected. It has unrelated
owner edits; leave them alone.

Build pipeline: `Tools/Build-Misn17CoopMap.py` (original stock 1.5 map), then
`Tools/Build-Misn17Crystals.py --game <GOG game>`, then
`Tools/Build-Misn17Jungle.py --isdfc <ISDFC root>`. All asset builders write only CR.

Native runner: ignored `Local/misn17/run.ps1`, Windows PowerShell 5.1, wraps
OpenShim `reverse_engineering/Run-BZRCoopMission.ps1` with isolated prepared
instances. Frozen content `C:/BZRCoop/misn17-20261018/content`; listing override
`listing/misn17.ini` sorts first (row 99). Staging is a previous manager-produced
native payload plus reviewed mission assets. Preserve its known EXU binary;
do not overwrite it blindly with an unrelated cache build.

Logs: `C:/BZRCoop/misn17-20261018/*.out/.err`; native run evidence under
`C:/BZRCoop/qualification-20261016/runs/<run>/`. Use the harness launch mutex
and `Stop-BZRGame -NoForce`, never force-kill the game. Do not dot-source the
launch mutex in the parent runner. No native test is currently certified for
the final combined jungle/crystal prototype.

No merge, release, Workshop publication or normal-install deployment authorized.
