# Mission 15: United We Fight - United We Die

Shared offline / 2–4 player co-op prototype. Source `misn15.lua` retains the
faithful port and all disabled source comments; marked adapter regions delegate
play to `CRMisn15.lua`. The reference-body test injects a no-op runtime factory
and still exercises the original 85 checks. Separate multi-peer tests execute
the campaign runtime and actual CR co-op registry/transport.

## Owner-approved design (2026-10-15)

- Use the shipped `misn15b` layout, not the alternate `misn15` terrain.
- Rendezvous with the allied CCA, recover the Massachusetts/NW group, secure
  75 banked scrap, then bring Texas and all active humans to Supply.
- Restore the optional Alaska/NE group: two scavengers and a howitzer.
- Restore 40/65-scrap reports, 50-scrap withdrawal instructions and the actual
  Mission 15 Texas-loss line. Preserve Tartarus's two warning lines.
- Scale hunters, preserve the two resource-denial tank pairs, and forbid
  enemy pop-in within 400 m of any human.
- Use Titan weather and reflective methane tied to this map's MAT/HG2 data.

## Runtime map and teams

`Missions/misn15.bzn` is generated from **stock `misn15b.bzn`**, rebound to
`TerrainName = misn15` / `MultSTMission`. Its four terrain companions are exact
copies of CR's existing `misn15b` companions under the runtime stem. Neither the
alternate stock map nor the `misn15b` source assets are overwritten.

Humans use teams 1–4; Furies 6; allied arriving/stranded NPCs 7. Team 5 is unused.
The Soviet convoy begins on 7, walks `tank_path`, and joins team 1 when any
surviving convoy unit reaches the original rendezvous radius. All-convoy loss
before rendezvous fails explicitly. Human teams have no AI brain and no extra
starting recycler. Texas is the shared team-1 economy and respawn rally.

Six unique-label rescue units are authored on the original rescue paths and
wait on team 7 at priority 1 until discovery. No units are created when a
player enters the 150 m rescue radius. At least one NW survivor must be
released; all-NW loss before recovery fails. Optional NE loss does not fail the
mission. No factory is added to the stock composition.

Initial native runs exposed a map-builder error: the two renamed editor paths
retained their original six-byte allocation lengths. Correcting `label.size`
removed the startup heap fault in the minimal native control. The contract now
checks every path's encoded label length. A temporary host spawn queue was
removed after its runtime labels failed to resolve on the guest; stable authored
identities keep the approved waiting-rescue design.

`Build-Misn15CoopMap.py` rebinds the map and clears inherited orders/motion.
It assigns unique names to the two unused `path_1` editor labels and reparses
canonical serialization. The stock `misn15b` tower label remains as a source-
layout identity check, not a new gameplay objective. `edge_path` is unchanged.

## Objectives, dialogue and victory

Only the host changes mission state. Any-human discoveries and whole-squad
withdrawal use the CR registry with guarded object distances. The familiar
ordered E/A event stream and C camera snapshots deliver presentation to guests;
short cameras are queued so split-party discoveries cannot overlap shots.

Victory requires a live Texas within **200 m of Supply**, all active humans
within **300 m**, CCA rendezvous, NW recovery, and at least 75 stored team-1
scrap. Either gathering-first or relocating-first works. NE recovery and
Tartarus do not gate victory. Death/loss takes precedence; result is decided
once. An exhausted player fails everyone through normal CR respawn rules.
Late join/rejoin requires restart; host departure ends the session.

Storage shows current capacity rather than cumulative silo construction.
Texas holds 30, each silo 20, factory 10 under current ODFs. Two silos alone
give 70: build another silo or a factory to reach the reserve target. Economic
units initially stay on team 1. Guest economic ownership/dropoff remains a
native acceptance item; no unverified team-balance sum credits the reserve.

Reports fire once at upward thresholds; spending does not replay them. Skipped
lower milestones are not queued after reaching 75. Withdrawal uses `1506/1508`,
NE reminder `1512`; these English originals are bundled byte-exact (PCM mono,
22050 Hz, 8 bit). The older cut-VO validator's fixed 11025 Hz assumption was
extended only for those original formats. Tartarus keeps `1513/1514`; the old
NE code's inappropriate reuse of `1514` stays removed. Failure uses `1509`.

The native co-op HUD defaults and optional traffic API remain owned by the
shared modules. This mission initializes PersistentConfig so X opens the PDA
and its Coop Diagnostics page, rather than merely initializing communications.
CR mission phases advance through rendezvous, rescue and withdrawal for network
diagnostics. Matching phase/heartbeat never claims complete native world parity.

## Fury tuning

First hunter wave at 120 s, then 240 s. One hunter offline, two for 2–3 humans,
three for four. Two Fury Tanks at 300 s and another two at 400 s take `deny1/2`.
At most ten live Furies; reserve capacity for the scheduled tank encounters.
If both authored alien sites are within 400 m of humans, retry after 15 s.
Pending denial encounters are retained. Living team-1 scavengers are reacquired
when a hunter's target is gone, then Texas; no stale latest-scavenger handle.

These values are tuning hypotheses, not difficulty qualification. The WASP
experiment, Soviet economy AIP, unexplained launch sites and alternate-map
patrols remain disabled.

## Tartarus guarded-zone encounter

The owner approved a meaningful consequence and explicitly requested a tight
bolt-mine grid if a player persists. Current prototype:

- First approach within 150 m queues the existing warning, once.
- Merely crossing that radius is safe. There is a 15-second warning grace.
- After grace, staying within 80 m for more than six continuous seconds alerts
  Tartarus. Moving away resets the close-range timer. Actual health loss also
  alerts it, even from outside the zone.
- One two-hunter response comes from the existing safe alien sites. It obeys
  the common live cap and denial reservations, retries if blocked, and is saved
  so loading does not duplicate it. A replicated haze/drizzle beat accompanies
  the disturbance. UI announces the response; no unrelated dialogue is invented.
- Tartarus is neither an extraction prerequisite nor a newly invented relic
  research/activation mechanism. Ordinary warnings remain non-punitive.

Continued close intrusion for 12 more seconds starts a four-second deployment
warning, then creates a 7×7 grid at 18 m spacing with its central 3×3 area
clear: 40 stock `boltmine` arc mines on team 6. Deployment is staggered, at most
two per quarter second, and any site within 12 m of a human waits. This
owner-authorized local trap is an explicit exception to the 400 m enemy-wave
rule. Mine deployment progress is saved, destroyed mines do not respawn, and
the grid is independent of the ten-Fury craft cap. The last known structure
position is retained if Tartarus is destroyed. Its 100 m stock mine search
radius makes interference dangerous to nearby optional Alaska survivors too;
it remains clear of the required NW rescue and the Supply withdrawal area.
Physical weapon damage, native mine replication/damage, close-range timing
and difficulty need native acceptance before finalizing tuning.

## Titan MAT and methane surface

Mission 15 binds **`CRTitanSites15`**, **`CR/Titan/Methane15`** and
**`cr_titan15_wet.png`**. It never uses Mission 14's wet mask or pool anchors.
The MAT codec/WorldBuilder validation now lives in the Modding Toolbox
`docs/world/MAT_FORMAT_VALIDATION.md`, `mat_codec.py`, and `hg2_codec.py` wrappers.
That documentation was consulted before generating the map data.

The generic global-height mode is wrong for this map: the large exterior dry
plateau is 102.2 m and yielded zero in-bounds pool anchors. The prototype uses
the lower **38.1 m** basin, identified from the in-bounds terrain distribution.
This classification is an explicit map-specific inference needing visual
acceptance. Only pure MAT 0→0 cells whose HG2 samples stay within ±0.3 m qualify;
mixed shore/rock tiles and high plateaus are excluded. The generator has an
explicit `--sea-level` argument rather than changing Mission 14's default.

Current data: 2,775 wet cells in the padded mask, 57 in-bounds anchors, generated
from the exact shipping MAT/HG2. The same table drives pools, splashes and the
render-only surface; it adds no collision or movement penalty. Existing Titan
weather runs through its guarded API on all peers, with host-issued seeded
events over the ordered stream. No shared shader source was changed.

The subsequently merged owner-wide weather sensor policy also applies here:
Environment captures the native Titan baseline, owns atmosphere writes and
binds the director through `BindWeatherSensors("Titan", director)`. Titan
remains daylight-locked. No additional damage or wind handling is introduced.

Reproduction:

```powershell
python Tools/Build-Misn15CoopMap.py --source <stockfiles>/misn15b.bzn
python Tools/Build-TitanSites.py misn15 --source-dir Missions --sea-level 38.1 --zfs <GOG>/bzone.zfs
python Tools/Build-MethaneSurface.py
```

## Validation

Targeted checks: source port (85), actual campaign co-op fixture (102), source
parity, map/listing/team/MAT-HG2 contract, cut VO, campaign shell, deterministic
methane asset regeneration and repository invariants. The multi-peer fixture
tests guest triggers, shared VO/cameras/results, loss precedence, the all-human
finish, optional-loss handling, postponed spawns, Tartarus grace/damage behavior
and save/load preventing duplicated rewards/responses. Mocks do not establish
native ownership, navigation, rendering or natural mission difficulty.

`Tools/Test-Misn15Live.ps1` is a two-client native harness scenario. It explicitly
assists NPC/player positions and reserve/storage. Its result establishes only
the exercised progression and replication; it does not establish natural
harvesting, physical shooting, balanced combat, four-PC play, Steam or Proton.
Native results are recorded in the local workstream handoff when available.

Still required before release: full unassisted progression/difficulty, actual
guest economic-unit banking and command transfer, dead/respawning extraction,
save/load during both cameras and withdrawal, failure paths, final methane
shoreline/height appearance, four native clients, and platform/release lanes.
