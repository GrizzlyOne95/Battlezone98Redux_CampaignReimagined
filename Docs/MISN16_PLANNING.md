# Mission 16: Strike at the Heart — source audit and CR plan

Audit date: 16 October 2026. Planning baseline: `a8a0701f`.
This is a proposal, not an implemented mission or a live-test result.

## Recommended direction

Build the offline / 2–4 player mission on the stock **misn16b** layout, retaining
the two alien-facility destruction objective and the CCA reinforcement assault.
Restore the existing warning and progress dialogue at observable mission events.
Keep a transport-escape finale as a separate, reviewable addition: the audio
supports that story, but the inspected map and mission logic do not supply the
scene. Preserve the faithful source port as the reference under a marked CR
adapter, following Mission 15's separation of reference behavior and runtime.

First deliverable after design agreement: the smallest playable offline/co-op
prototype with the correct map, teams, native AI, presentation and endings. A
larger qualification matrix follows that prototype's acceptance.

## Evidence and present state

Evidence labels distinguish **PROVEN** source/data findings, **STRONG INFERENCE**
interpretation, and **UNKNOWN** behavior not established by this audit.

| Finding | Evidence / confidence |
| --- | --- |
| A faithful Lua port already exists | **PROVEN:** `Scripts/misn16.lua`, `References/Misn16Source/`, `Docs/MISN16_LUA_PORT.md`. Current targeted tests pass: 411 Lua host checks / 99 source checks. |
| The stock campaign selects `misn16b.bzn` | **PROVEN:** installed stock `packaged_mods/819834262/bzcmpgns.ini`, entry named Strike at the Heart, followed by Tapping the Core. Both BZNs select `Misn16Mission`; the suffix does not prove a separate story phase. |
| The alternate map is incomplete for the current port | **PROVEN:** `misn16` lacks `sat1`, `sat2`, `starta2`, `starta3`, `startb2`, `startb3`. Those six paths are present in `misn16b` and referenced by active mission logic. |
| CR is not ready to launch Mission 16 yet | **PROVEN:** no tracked `Missions/misn16.bzn`, multiplayer listing or campaign entry; `crcampgn.ini` ends at Mission 15. No CR co-op adapter exists in the port. |
| Some integration assets already exist | **PROVEN:** tracked `misn16b.hg2/.trn/.mat/.lgt`, all 17 transcript text files and duration metadata. The older port note saying there is no terrain is stale for this baseline. No tracked Mission 16 AIP was found. |
| Stock assets are available locally | **PROVEN:** GOG 2.2.301 `bzone.zfs` contains both BZNs and terrain sets plus `misn16.aip`; `bzone_en.zfs` contains `misn1600`–`misn1616.wav`, objective and ending texts. Presence alone is not proof of an active branch. |
| The faithful source's disabled extras are also absent from the inspected classic executable mission body | **PROVEN** for the inspected classic 1.5 corpus. Private executable evidence stays local; no decompiler output is included here. This does not establish every Redux runtime difference. |
| Actual Redux mission playback and AI | **UNKNOWN:** no game was launched for this planning audit. |

The classic stock BZNs and the corresponding members of the inspected GOG
archive are byte-identical. The stock AIP is also byte-identical between those
sources. This does not mean their terrain companions or engine behavior are
interchangeable.

Public source pointers:

- `References/Misn16Source/Misn16Mission.cpp`: original behavior and disabled code.
- `Docs/MISN16_LUA_PORT.md`: port decisions and source identities.
- `Tools/TranscriptSources/GoombaBZ/campaigns.csv`: dialogue inventory; its
  "unused" annotations are leads, not behavior evidence.
- `Docs/PILOT_MODE_CAMPAIGN.md`: separate N64 Pilot Mode design reference.

## Map audit

| Property | misn16 | misn16b — selected baseline |
| --- | --- | --- |
| Objects | 51 | 133 |
| Authored teams | 1: 9, 2: 21, neutral: 21 | 1: 9, 2: 22, neutral: 102 |
| Named mission paths | 7 | 13, plus 2 unnamed paths |
| Additional spawn paths required by the port | missing | all six present |
| Duplicate nonempty object labels | two scrap-field labels repeated | none found |
| Authored Fury SAV | none | one |
| Resource representation | nine scrap-field objects | 90 individual scrap objects |

Both maps reference `misn16b.bzn` as their terrain name. For CR, generate a
`misn16.bzn` runtime map from the original **misn16b** BZN and consistently bind
its terrain companions. Use CR's retained unsmoothed height source after checking
its provenance; do not replace it with Redux-smoothed heights.

Preserve the named mission routes: `camera_path1`, `starta/b`, their four
additional ingress points, `sat1/2`, `strike1/2`, `edge_path`, and `path_4`.
The five-point `path_4` broadly traces the outside of the play area; its purpose
is **UNKNOWN**. It is not evidence of a transport route. Neither disabled
`reinforce14` nor `reinforce24` exists in the selected map.

The selected map carries two unnamed paths, moving SAT state and issued orders,
plus a moving camera pod. Audit and normalize those saved motion/order fields
during conversion, and deliberately reissue necessary standing orders. Do not
apply a blanket Stop/AI command to static fixtures or camera objects. Keep the
authored defenders and scrap distribution unless a separately explained change
is required. Test navigation through both fifteen-point SAT routes.

## Preserved gameplay contract

**PROVEN from the faithful source and port:**

- Start with Texas, the NSDF factory, 50 shared scrap, two opening radio calls,
  four named beacons and an introductory factory camera.
- Nine CCA reinforcement waves: first at 120 seconds, then 180-second intervals.
  Seven possible manifests; the first selection is restricted to the two weak
  manifests. Soviet combat units attack one of the two alien facilities;
  scavengers/haulers move toward one. Orders are overridable in the source.
- Type 5 falls through into type 6: two fighters and four tanks, with the same
  reinforcement radio twice. This is shipped behavior, not hidden content.
- Fury SAV pressure begins at 60 seconds; the gap decreases from 150 toward
  60 seconds. SAT pairs begin at 90 seconds and their later timing is coupled
  to the next SAV deadline. Preserve that coupling in the first prototype.
- Clearing either entrance's two towers, or destroying either facility, starts
  a two-SAV factory counterattack. A two-SAV Texas attack follows 120 seconds later.
- Destroy **both** alien HQ and hangar to win; losing Texas fails. The stock
  checks are independent and can schedule both results on simultaneous loss.

The CR adapter needs a deliberate single terminal result. Recommended policy:
Texas destruction wins the same-update tie; otherwise both alien facilities
destroyed wins. Record and test this as an intentional CR change.

The selected stock AIP requests Soviet units and structures even though the
scripted opposition contains Furies. Preserve and measure this baseline before
deciding whether a different enemy construction roster is desirable. Do not
silently replace its construction program with an inferred Fury-only plan.

## Cut/unused content ledger

`misn1600.wav` is the campaign narration, selected outside the mission script;
it is not a cut in-mission radio. The active source calls 01–08, 12 and 13.
The remaining six audio files exist in the stock English archive.

| Candidate | Evidence | Proposed CR use |
| --- | --- | --- |
| `misn1609.wav`, counterattack warning | **PROVEN available; no active call** in audited mission logic | Play once when the first counterattack is launched. |
| `misn1610.wav`, defend Texas reminder | **PROVEN available; no active call** | Queue behind the warning when the Texas strike begins. Keep both lines audible without overlapping an existing message. |
| `misn1611.wav`, attack from multiple directions | **PROVEN available; no active call** | Optional one-time hint after sustained lack of assault progress while both facilities remain. It should not require four humans or prescribe a new win condition. |
| `misn1614.wav`, finish the facilities reminder | **PROVEN explicitly disabled** at the reinforcement-exhaustion branch | Restore once at the tenth deadline only if a facility remains and the mission is active. The spoken line is a finish-the-job prompt, not an announcement that reinforcements ended. |
| `misn1616.wav`, factory destroyed confirmation | **PROVEN available; no active call** | One-time hangar/factory-destruction beat; suppress a stale prompt after the final result and queue correctly if both facilities fall together. |
| `misn1615.wav`, Furies boarding a transport and fleeing Titan | **PROVEN available; no active call**. The success debrief also establishes escape to Achilles. No authored transport object or dedicated escape path was found. | Strong candidate for a short optional finale, but its staging is **new CR design**. Do not claim a recovered executable transport sequence. |
| Additional fighter at `reinforce24`; tank at `reinforce14` | **PROVEN disabled statements**; both markers absent from the selected map | Leave disabled initially. Restoring them requires authored positions and an explicit balance decision. |
| Third SAV in each counterattack | **PROVEN disabled spawns/orders**; one disabled recycler order repeats the first SAV rather than ordering the third | Optional difficulty/scaling material. Do not enable the commented text literally or quietly add both units to the baseline. |
| N64 Pilot Mode rebuilding/wingmen | **PROVEN documented alternate-platform behavior**, not a disabled PC branch | Separate offline option using the existing Pilot Mode architecture; never enable its AI on human teams in co-op. |

### Escape-scene decision

Recommended first prototype: finish the two-facility objective without a mandatory
chase or escort. The debrief already bridges to Mission 17. Add the transport
finale only after choosing a location, appropriate craft appearance, visible
approach/boarding/departure behavior and audio order. The stock archive contains
landing/drop-related assets, but their suitability as a Fury evacuation transport
is **UNKNOWN**. Asset names alone do not establish the intended model.

A scene must not spawn combat enemies beside an unsuspecting human, steal
controls from a player under fire, leave guests waiting for a missing camera
target, or turn an optional spectacle into an undocumented extra win gate.
Preserve the ability to skip a local camera without skipping shared mission state.

## Co-op design proposal

- Humans: teams 1–4. Texas and the established base/economy remain host-owned.
  Disable extra starting recyclers; use the existing shared rescue/respawn/PDA
  services. Proposed initial VXT choices are existing NSDF choices, not a new
  faction-selection system.
- Furies and captured hostile facilities: team 6. Team 5 remains unused unless
  a verified independent enemy faction needs it. Do not use a generic builder
  rule that leaves the Furies on a guest team.
- Preserve the CCA reinforcement groups as host-owned shared team-1 assault
  units for the baseline. Any support-team arrival or allocation to individual
  humans is an explicit later design choice; the stock mission has no rendezvous
  handover gate. Exclude every human craft from the Soviet AddObject auto-order
  callback, including humans who later board Soviet vehicles.
- Host alone owns timers, RNG, builds, strategic AI and results. Guests perform
  only owner-local actions. No strategic AI may attach to a human team.
- Verify the native AIP actually constructs and orders units under MultSTMission
  before adding a substitute AI layer. Preserve the original source for comparison.
- Use the established acknowledged presentation stream for radio, objectives,
  marker labels, camera state and one shared result. Reuse the native-handle label
  binding fixes and compile the full instrumented mission under Lua 5.1.
- Keep opening cameras shared, with individual local skips. Reinforcement
  flybys should respect combat near any human; skipping one cannot change
  reinforcement timing. Define the shot subject explicitly rather than relying
  on whichever matching Soviet unit last happened to trigger AddObject.
- First prototype keeps nine CCA waves and stock enemy timings. Tune assistance
  and enemy pressure from one-to-four-player measurements rather than multiplying
  every timer and unit count at once. Disabled extra units are options, not proof
  of a desired four-player difficulty.
- Reuse the current Titan weather/native-baseline policy. Generate sites from
  this selected map and validate methane classification for this terrain; do not
  inherit Mission 14/15's basin thresholds without measuring Mission 16.
- Offline Pilot Mode remains optional and separate. Its constructor/base-repair
  behavior and additional factory-loss condition are not the co-op win/loss rules.

## Implementation and validation order

1. **Playable baseline:** generate the selected map and four stationary starts;
   free guest teams, preserve labels/routes, stage the native AIP and existing
   assets, wire one offline/co-op runtime without changing the faithful reference.
2. **Readable assault:** restore the warning/progress lines with once-only
   triggers and queueing, shared markers and result latch. Keep the transport
   scene and optional extra units outside this first increment.
3. **Small live prototype:** offline and a short four-client run checking map
   load, both assault ingress directions, team ownership, AI construction,
   first reinforcement camera and both enemy routes. Inspect actual rendering,
   radio order, unit commandability and guest labels. No live checks were run
   by this planning audit.
4. **Design review:** choose the escape scene, optional extra units, balancing
   and offline Pilot Mode scope against the playable prototype.
5. **Qualification after acceptance:** exercise every reinforcement manifest
   (including type-5 fallthrough), all four counterattack triggers, nine-wave
   exhaustion, partial/final facility destruction, Texas loss and simultaneous
   destruction. Check save/load during both cameras and both counterattack
   phases offline; shared presentation, local film skips and one result on all
   four clients online. Include human boarding of Soviet units to prove the
   auto-order filter cannot take control of a player.

Packaging after the prototype needs the Mission 16 campaign entry, multiplayer
listing, preview, VXT, menu/contract updates and a reviewed shipping-lock diff.
Cross-platform behavior remains a test requirement: GOG/Steam on Windows and
their supported Wine/Proton environments. A loopback pass is not human multi-PC
or platform qualification.

## Decisions to carry into the prototype

Recommended starting scope is the selected map, faithful assault pacing, restored
warning/progress radio, shared presentation and reliable endings. The following
remain design decisions, not activated code:

1. Whether to build the visible transport-escape finale now or retain the debrief
   bridge for the first playable version.
2. Whether disabled extra Soviet units / third counterattack SAVs belong in a
   later difficulty tier or player-count scaling.
3. Whether to include the N64-style offline Pilot Mode in this mission's first
   CR increment.
