# Co-op admission before Initialize - 2026-10-09

The host can receive a guest's `Q` handshake before mission `Start()` calls
`CRCoop.Initialize()`. Previously the host immediately marked that guest ready
and sent `K`. Initialize then cleared its ready flag and handle; the guest had
already accepted `K`, so it stopped retrying Q. The host waited indefinitely
for a handshake it had already acknowledged.

The private four-client GOG run `retry-battle-t1000x2500-i1-p1-20261009-183000`
captures that order directly on host c0:

| Time CDT | Event |
|---|---|
| 18:32:14.676491 | Guest c2's Q forwarded to host |
| 18:32:14.676997 | Host Receive after Q: player 3 ready=true, valid incoming handle |
| 18:32:14.677497..14.677999 | Initialize clears player 3 ready and handle |
| 18:32:14.677299 | Host K forwarded to c2 |
| 18:32:14.693533 | Guest c2 consumes K and subsequently stops Q retries |

The later Q requests from c1/c3 complete; c2 sends no second Q. Host readiness
never completes, and the run stops INCOMPLETE before impairment or battle.
Stock timers were verified on all four clients. No native crash occurred.
Independent capture audit: 40,729 decisions/submitted outcomes on twelve links,
zero missing outcomes/correlation errors/source-send mismatches, four clean
untruncated native captures with zero dropped events and full binary retention.
The causal Q/K copies have source send, socket submission and target receive
evidence. Forty-eight other RX deficits remain recorded (39 after final P2P
receive, nine earlier); a clean capture does not prove every event was recorded.
No relay loss caused the observed admission state reset. Payloads, identifiers,
exact raw records and dumps remain private outside Git.

`Scripts/CRCoop.lua` now consumes early Q/K/P messages without admitting state
or sending an acknowledgement. Update/session readiness waits for initialization
to finish. Existing guest retries request a fresh handshake after initialization.
Initialize still clears prior mission readiness, phase and remote handles;
post-initialization messages, protocol version checks and leader authority keep
their existing behavior. No new wire message or timer setting is introduced.
The observed race occurs in a fresh Lua module before its first Initialize.
A reused module remains initialized between missions until its next Initialize
begins; arbitrary messages in that interval require separate lifecycle/epoch
evidence and are not qualified by this fix.

`Tools/Test-CRCoopAdmission.lua` reproduces the early acknowledgement failure on
the original source and passes on the fix. It also checks early K/P, guest retry
and acknowledgement cessation, reinitialization, wrong version/non-leader ack
and single-player readiness. Existing CRCoop tests pass. Complete-script Lua
5.1 tests pass for misn02b (11,994 checks), misn03 (6,251) and misn04 (27,722).

Live validation is in progress with four internal clients and the passive
admission trace. The test applies exactly this admission-only source diff to
the immutable respawn-enabled release test baseline, preserving its existing
respawn features. The canonical source and release variant differ outside the
changed admission blocks; both variants pass the same lifecycle and registry
tests. This is a private test override, not a Workshop or installed-campaign
publication. GOG integration, Steam, Proton/Wine and longer-session outcomes
must be reported separately.


## Guarded live checkpoint — 2026-10-09 19:37 CDT

Private `193200` completed one stock 1000/2500 arm: gameplay/cleanup PASS,
80 fighting AI / 60 steady simulation seconds, 16 beacons, 64 powerups,
23 natural vehicle deaths and 94 new observed scrap handles. Native health
FAIL remains separate; full network qualification is OPEN. All four clients
ran the same hashed admission-only override. The host Initialize preceded Q,
so the original host race was not reproduced; early guest messages were
consumed without admission and subsequent startup completed.

Independent twelve-link audit: 55,114 decisions, 53,446 submitted outcomes,
1,668 intended loss drops, zero missing outcomes/correlation/source-TX errors,
four clean captures with zero drops/truncation/full binary retention. Nine
target RX deficits remain within the conservative 55.913-second combat interval.
Submission and clean retention do not establish native receipt/acceptance.

The shorter-timer arm stopped at c0-lounge navigation before impairment/combat;
the retained host screenshot shows Options instead of the expected lobby.
Zero relay decisions, four clean archived captures. Rate/queue arms did not
run, so no timer comparison is qualified. Defaults stay 1000/2500.
Graceful client exit and independent restoration audit passed: 128 targets,
zero mismatch/zero games at 19:36:59 CDT. Original incomplete attempts remain
retained. Exact timer/capture evidence lives in OpenShim netfix's
`reverse_engineering/p2p_retry_timing_validation_20261009.md`; raw data is private.

## Consolidated source and GOG installation — 2026-10-09

`agent/network-coop-integration` combines current main (`b3450f8`), the
admission guard (`938ed92`) and four-player mission work (`2452730`, PR #171).
Initialize marks the module ready only after the comms, respawn, rally and
lives services finish setup. Early Q/K/P are consumed before service handlers.
The fresh-module qualification limit described above still applies.

The merged admission fixture loads the real comms/respawn services. Lua 5.1
admission, registry, comms (510 checks), PDA/HUD (14), rally, misn02b (14,975),
misn03 (7,842), misn04 (34,483), misn05 presentation (22), owner-local/offline
PhysicsImpact and subtitle replacement (9) checks pass. Python co-op contracts
for misn02b/03/04/05 also pass. The earlier smaller fixture counts refer to the
admission-only checkpoint, not this combined source.

The campaign manager now copies all 17 OpenShim native UI images, including
the 13 painted hub/category/keybind assets that were missing from the old
four-image packaging list. Repository test fixtures are excluded from shipping.
The reviewed lock adds 77 runtime entries to the previous 3,712: 13 native UI
images and 64 already-authored current-main mission/content files. There are
no removals or remaps relative to the committed baseline. The manager refreshes
tracked binary caches and payload metadata from the explicitly selected
OpenShim integration build; these caches are generated, not independent source.

Local GOG deployment verifies 3,789 expected files, zero missing, differing or
unexpected managed files. The installed campaign CRCoop and suite payloads
match canonical source/cache; the root game load chain matches those payloads.
OpenShim plugin SHA256 is
`A1A3966EF25205634BF521485D700F75533076A5CEB8443FC4ADFA52763D6D4F`.
The plugin retains development version 1.0.0.47; its hash identifies this build.
The user's existing INI preferences are preserved, with redesigned Settings
and Keybind pages enabled and stock retry defaults 1000/2500 unchanged.

GOG menu checks cover the actual native category hub, Video category, Back
navigation and painted keybind editor. This is UI/deployment evidence, not
new multiplayer gameplay or Steam/Proton/Wine qualification. The full merged
campaign still needs mission gameplay requalification before release.

The cross-repository integration map is
[OpenShim NETWORK_UI_INTEGRATION_20261009.md](https://github.com/GrizzlyOne95/Battlezone98Redux_Shim/blob/agent/gog-ui-network-catchup/Docs/NETWORK_UI_INTEGRATION_20261009.md).
Combined reviews are [campaign draft #173](https://github.com/GrizzlyOne95/Battlezone98Redux_CampaignReimagined/pull/173)
and [OpenShim draft #419](https://github.com/GrizzlyOne95/Battlezone98Redux_Shim/pull/419).
Server observability and ticket redaction are consolidated in
[dedicated server PR #9](https://github.com/GrizzlyOne95/Battlezone98Redux_DedicatedServer/pull/9).
Raw captures, identities, backups and screenshots remain private under
`C:\BZRCoop\runs`; neither Workshop publication nor a PR merge occurred.
