# Four-player qualification, 16 October 2026

**Result:** all nine selected core progression scenarios pass on the final
candidate: 02b, 03, 04, 07, 08 and 12–15. Mission 13 and 14 recycler-loss
scenarios also pass. The eleven selected reports total 125 steps / 496 checks.
Each passing mission's script and BZN hashes match the frozen human candidate;
native DLL identities remained unchanged. Earlier failed reports are retained.

This workstream tests four real GOG Redux clients on the private loopback
server. Mission assists accelerate travel/combat and act on each object's
owner. Guest mission state is never assigned by the scenarios. A pass is scoped
to the checks actually exercised; it does not establish natural difficulty,
physical boarding, a separate-PC network, Steam, Proton or Wine.

## Queue and required coverage

| Map | Scenario | Required result |
| --- | --- | --- |
| misn15 | `Tools/Test-Misn15Live.ps1` | both rescues; methane binding; replicated Tartarus response/mines; fourth-human extraction gate; shared win |
| misn13 | `Tools/Test-Misn13Live.ps1` | CCA AIP; four-human reinforcement sizes; factory/hangar/all-silo win gate; shared win |
| misn14 | `Tools/Test-Misn14Live.ps1` | eight Furies, commandability on each human, rogue team replication, three rescues, surrender and scientists' return |
| misn12 | `Tools/Test-Misn12Live.ps1` | per-human checkpoint state; guest uplink/range break; all-human extraction; shared win |
| misn02b | `Tools/Test-Misn02bLive.ps1` | on-foot start; fourth-human film skip; scavenger chain; shared win and clean labels |
| misn03 | `Tools/Test-Misn03Live.ps1` | defense/evacuation chain; fourth-human film skip; every human reaches extraction; shared win |
| misn04 | `Tools/Test-Misn04Live.ps1` | relic/base objectives and films; fourth-human film skip; shared win |
| misn07 | `Tools/Test-Misn07Live.ps1` | guest rendezvous, array destruction, Utah arrival and shared core-objective victory |
| misn08 | `Tools/Test-Misn08Live.ps1` | base destruction alone cannot win; fourth human discovers relic; shared win |

Mission 12's scenario explicitly supplies replicated, owner-local key ships
and assumes them through EXU. This tests the mission capture adapter and later
progression, **not physical sniping and boarding of the authored key ships**.
Mission 7's alarm/parachute and restored test-range branches, Mission 8's
Colorado/walker sequence, and unassisted combat require further coverage.

All runs require four distinct teams, complete registries and directional
alliances. The harness compares presentation with all three guests, checks Lua,
rendering and unresolved-label errors, verifies audio and native network
diagnostics, and closes clients gracefully. Native DLL identities are checked
before and after every progression run. A missing final report is incomplete.

## Run

Use Windows PowerShell 5.1, the current selected OpenShim harness checkout and
a frozen private campaign stage. Prepare four clients with that same native
build first. The runtime root is disposable and must not be a player install.
Each mission has a private listing override at `listings/<map>/<map>.ini` whose
title sorts first; the production listing is unchanged.

Run OpenShim's `reverse_engineering/coopflow/Test-CRFlowMissionParsing.ps1
-CampaignScripts <CR-checkout>\Scripts` first. It compiles the full mission plus
probe under Lua 5.1; checking the probe alone misses the main chunk's local limit.

```powershell
.\Tools\Run-CoopFourQualification.ps1 `
  -HarnessRepo <selected-OpenShim-checkout> `
  -CampaignContent <frozen-content-directory> `
  -BZRCoopRoot <prepared-private-runtime-root>
```

`qualification-status.json` identifies the current mission and completed rows.
Each run retains its full report/captures and the suite writes `suite.json`.
`-Missions misn13,misn14` selects a subset when invoked from PowerShell.
`-StopOnFailure` stops on a failed verdict; surviving clients always stop the
queue. Never force-kill the game or start over an existing game.

Mission 13 and 14 also accept `Mode=recycler-loss` through the harness's
`-ScenarioArgs` parameter. These must produce the mission-specific shared
failure result instead of a victory.

## Initial regression

The first four-client Mission 12 rendering control reached gameplay with four
players, correct authority/alliances and passing native network diagnostics.
Its final verdict was FAIL: client 4 parsed CR shader wrappers before the
OpenShim worker installed its resource-group bootstrap, producing missing
Enhanced source errors and caught DX11 rendering exceptions. The related
OpenShim workstream arms that import hook before the expensive patch sweep;
the original failed run remains evidence and is not relabelled.

The fixed cold-start control `misn12-four-smoke-v2-20261016` passes four steps /
38 checks with four native clients, including rendering, roster, directional
alliances, audio and native network health. This establishes the rendering
prerequisite, not the Mission 12 story path.

The old Mission 14 contract also prohibited all Environment references even
after the shared weather-sensor policy had merged. It now positively requires
the native baseline, Titan sensor binding and lifecycle forwarding. The
offline, co-op and presentation suites remain the behavior checks.

## Completed native progression

| Map | Run | Result |
| --- | --- | --- |
| misn15 | `misn15-four-progression-20261016-082029` | PASS, four clients, 9 steps / 52 checks |
| misn04 | `misn04-four-progression-20261016-082029` | PASS, four clients, 20 steps / 41 checks |
| misn13 | `misn13-four-progression-20261016-085411` | PASS, four clients, 8 steps / 44 checks |
| misn14 | `misn14-four-progression-20261016-085411` | PASS, four clients, 10 steps / 54 checks |
| misn02b | `misn02b-four-progression-20261016-091838` | PASS, four clients, 22 steps / 42 checks |
| misn03 | `misn03-four-progression-20261016-124917` | PASS, four clients, 27 steps / 59 checks |
| misn12 | `misn12-four-progression-20261016-124917` | PASS, four clients, 10 steps / 47 checks |
| misn07 | `misn07-four-progression-20261016-124917` | PASS, four clients, 6 steps / 38 checks |
| misn08 | `misn08-four-progression-20261016-124917` | PASS, four clients, 5 steps / 39 checks |

Mission 15's guest recovered both waiting groups, all four clients saw the
same forty native Tartarus mines, an absent guest blocked extraction with the
reserve and Texas already present, and all four received exactly one shared
victory. Presentation, Lua/rendering/label health, audio, native network
diagnostics and final client liveness passed. Native DLL identities remained
unchanged across the run. Travel, reserve, survivability and damage assists
retain the limitations listed above.

The first matrix found generated-label identity failures in Missions 02b, 03
and 12, and static surrender ownership that remained host-local in Mission 14.
The repair candidate sends generated-label bindings with native handle identity,
gives the second authored Mission 02b turret a unique label, and presents static
Mission 14 surrender ownership on each peer. Mission 12's presentation check
compares each player's operations against the authority's recipient-specific
dispatch plan, with regression coverage for a missing fourth-player operation.

Scenario repairs also wait for Mission 13's first wave before shortening its AIP
deadline, verify actual cinematic-prop deletion in Mission 03, and use direct
owner-local vector positioning for Mission 07/08 travel. The failed reports are
retained; these changes require fresh native runs before adding passing rows.

Mission 13's retry verifies native CCA AIP assignment, four-human reinforcement
counts, factory/hangar/silo dependencies and one shared victory per client.
Mission 14's retry verifies all eight Furies on every peer, owner-local command
permissions, native rogue re-teaming, three rescues, static surrender ownership
on all four peers and the scientists' return followed by a shared victory.

The first Mission 12 repair run failed before mission startup because the new
probe wrapper exceeded Lua 5.1's 200-local limit. The wrapper now captures its
extra local in a nested function, and all nine complete instrumented missions
compile. That failure is retained and requires a fresh native retry.

Mission 02b's final label candidate passes the fourth-human intro skip, full
scavenger chain, all presentation streams and shared victory with no unresolved
labels. The label-binding fix applies native identity to custom assigned names
as well as `crco_` names, while authored map objects fall back to their existing
labels when native map-handle identity is unavailable.

Mission 03's final-candidate run reached shared victory and passed final
presentation/label/render/network health, but its immediate transport sample
failed at 74 host events / 73 guest events. That report remains FAIL. OpenShim's
follow-up waits up to 15 seconds for the sampled watermark, accepts a guest that
has already advanced beyond that earlier sample, and still rejects undelivered
events. Regression coverage includes all three cases. The fresh final-candidate
retry passes every one of its 27 steps / 59 checks, including the transport
sample, final presentation, shared victory and native network health.

The later unattended runs of Missions 12, 07, 08 and the recycler-loss scenarios
failed startup audio qualification before gameplay. They provide no story-path
evidence. Fresh runs keep the audio gate enabled after the render endpoint is
available again; do not substitute muted music/configuration or waive the gate.

Mission 12's fresh final-candidate run passes every human's three checkpoint
gates, the guest range-break and full 45-second uplink, extraction blocked by an
absent human, and shared victory after everyone returns. Each client's native
presentation stream matches its own authority dispatch plan. Labels, Lua,
rendering, audio, liveness and native network health pass. Physical sniping and
boarding remain unverified because this scenario supplies replacement key ships.

Mission 07's core-objective retry passes guest rendezvous, radar-array
destruction, Utah arrival and shared victory after the CCA recycler falls.
All presentation and native-health gates pass; the alarm/parachute and restored
test-range branches are outside this scenario.

Mission 08's core-objective retry confirms base destruction alone cannot win;
the fourth human then discovers the relic and all four receive shared victory.
All presentation and native-health gates pass. The Colorado/walker sequence
remains outside this scenario.

## Shared-loss coverage

| Map | Run | Result |
| --- | --- | --- |
| misn13 | `misn13-four-recycler-loss-20261016-130605` | PASS, four clients, 4 steps / 38 checks |
| misn14 | `misn14-four-recycler-loss-20261016-130605` | PASS, four clients, 4 steps / 42 checks |

Mission 13's loss run destroys the host-owned Texas and verifies exactly one
`misn13f1.des` failure result per human, matching presentation, clean labels and
script/rendering health, audio, liveness and native network health.

Mission 14's loss run verifies the initial eight dormant Furies on every peer,
then destroys the host-owned Texas and verifies exactly one `misn14l1.des`
failure result per human. Presentation, label/script/rendering health, audio,
liveness and native network health all pass.

## Human test handoff

Only hand over the exact native/content candidate used by passing runs. Host
on team 1, use separate guest teams 2–4, and start together. Late join/rejoin
requires restarting the mission; host departure ends it. Select the production
`CR: ... Coop` map listing. Confirm the same build on every PC before testing.

The private handoff contains uninstrumented `CampaignContent/`, the selected
`NativePayload/`, a SHA-256 candidate manifest, all eleven selected summaries
and input identities under `Evidence/`, and a read-only verification script.
The qualification index only admits PASS reports whose mission script and BZN
hashes match that candidate. Full logs/captures stay in the private run folders;
the archive excludes accounts, local redirects, debug configuration and caches.

A separate-PC human session must check natural mission flow, briefing and
objective clarity, real PDA/ping/rescue controls, player deaths/respawns and
unassisted difficulty. Loopback harness passes do not qualify a public server
or remove these gates. No Workshop publication is part of this workstream.
